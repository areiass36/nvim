-- Moving around the result and taking things out of it.
--
-- Every yank and export reads the stored value, never the text on screen: what
-- is on screen may be truncated, and a WHERE clause built from an ellipsis
-- would be wrong.
--
-- gf follows the foreign key under the cursor, which is the one jump in a
-- database worth a key of its own: it reads the key out of the swept catalog
-- and the value out of the row, and opens a query buffer selecting the row
-- this cell points at.
local db = require("db")
local grid = require("db.grid")
local value_module = require("db.value")

local M = {}

local function state_of(bufnr)
	return grid.state(bufnr)
end

function M.move(bufnr, row_delta, column_delta)
	local state = state_of(bufnr)
	if not state then
		return
	end
	if row_delta ~= 0 then
		state.row = math.max(1, math.min(#state.rows, state.row + row_delta))
	end
	if column_delta ~= 0 then
		state.column = math.max(1, math.min(#state.columns, state.column + column_delta))
	end
	grid.focus_cell(bufnr, 0)
end

local function copy(text, what)
	vim.fn.setreg('"', text)
	vim.fn.setreg("+", text)
	db.notify(("%s copied (%d chars)"):format(what, #text))
end

function M.yank_cell(bufnr)
	local value = grid.cell_value(bufnr)
	if value == nil then
		return
	end
	copy(value_module.display(value, "NULL"), "cell")
end

function M.yank_row(bufnr)
	local state = state_of(bufnr)
	if not state then
		return
	end
	local csv = require("db.codec.csv")
	local row = state.rows[state.row]
	if not row then
		return
	end
	copy(csv.encode_row(row, { count = #state.columns }), "row")
end

function M.yank_column(bufnr)
	local state = state_of(bufnr)
	if not state then
		return
	end
	local values = {}
	for _, row in ipairs(state.rows) do
		values[#values + 1] = value_module.display(row[state.column], "NULL")
	end
	copy(table.concat(values, "\n"), ("column %s"):format(state.columns[state.column] or "?"))
end

--- The form a stored value takes in a generated statement.
---
--- A number goes in bare and everything else goes in quoted, which is the form
--- every engine here accepts for the types a key is made of. The quote is
--- doubled the way SQL doubles it, and on MySQL and MariaDB the backslash as
--- well: those read one inside a string literal as an escape unless the server
--- was started with NO_BACKSLASH_ESCAPES.
local function literal(driver, value)
	if type(value) == "number" then
		return value_module.display(value)
	end
	if type(value) == "boolean" then
		-- SQL Server has no boolean; a bit column is what arrives as one.
		if driver == "mssql" then
			return value and "1" or "0"
		end
		return value and "TRUE" or "FALSE"
	end
	local text = value_module.display(value)
	if driver == "mysql" or driver == "mariadb" then
		text = (text:gsub("\\", "\\\\"))
	end
	return ("'%s'"):format((text:gsub("'", "''")))
end

--- The foreign key this column takes part in, if any.
---
--- A key's `columns` and `ref_columns` are written in the order the driver
--- reported its parts, so the two line up by position.
--- @return table|nil key
local function key_of(details, column)
	for _, key in ipairs(details.foreign_keys or {}) do
		for _, name in ipairs(key.columns or {}) do
			if tostring(name) == tostring(column) then
				return key
			end
		end
	end
	return nil
end

--- Every part of the key, paired with the value the row under the cursor holds
--- for it.
---
--- One equality is enough for the single-column key that nearly every foreign
--- key is. A composite key needs all of its parts, or the statement lands on
--- more rows than the one the cursor is on -- so the other parts are read out
--- of the same row, which only works while the result carries them. A result
--- that dropped one still gets a statement, just a wider one.
--- @return table[]|nil pairs of { referenced column, stored value }
--- @return string|nil why there is nothing to select
local function key_values(state, key, table_name)
	local tables = state.result.column_tables or {}
	local row = state.rows[state.row] or {}
	local found = {}
	for position, name in ipairs(key.columns or {}) do
		local referenced = (key.ref_columns or {})[position]
		for index, column in ipairs(state.columns) do
			if referenced and tostring(column) == tostring(name) and tables[index] == table_name then
				local value = row[index]
				if value == nil or value == db.NULL then
					-- A key with a NULL in it points at nothing, and "= NULL"
					-- matches nothing either: say which it is.
					return nil, ("%s is NULL in this row, so it points at nothing"):format(tostring(name))
				end
				found[#found + 1] = { referenced, value }
				break
			end
		end
	end
	if #found == 0 then
		return nil, ("the result does not carry %s"):format(tostring(key.columns and key.columns[1]))
	end
	return found, nil
end

--- Follow the foreign key under the cursor: a query buffer selecting the row
--- this cell points at.
---
--- Which table a column came from is the driver's own answer, carried through
--- from the result's metadata, and the key is read out of the catalog the
--- sweep took. So the jump is instant or it does not happen: a table nobody
--- has introspected says so rather than making the editor wait on a round
--- trip for metadata it would then throw away.
function M.follow(bufnr)
	local state = state_of(bufnr)
	if not state then
		return
	end
	local schema = require("db.schema")
	local result = state.result
	local connection = result.connection
	local column = state.columns[state.column]
	if not connection or not column then
		return
	end

	local table_name = (result.column_tables or {})[state.column]
	if table_name == nil or table_name == "" then
		return db.notify(
			("the driver did not say which table %s came from"):format(tostring(column)),
			vim.log.levels.WARN
		)
	end
	-- Several drivers report the schema as an empty string rather than leaving
	-- it out, and the catalog keys an engine without schemas on "" as well, so
	-- the two have to arrive at the store the same way.
	local table_schema = (result.column_schemas or {})[state.column]
	if table_schema == "" then
		table_schema = nil
	end

	local catalog = schema.catalog_of(connection)
	local details = schema.details_ready(connection, catalog, table_schema, table_name)
	if not details then
		return db.notify(
			("%s has not been swept, so its keys are not known; :DbIntrospect would make this work"):format(
				schema.qualify(connection, table_schema, table_name)
			),
			vim.log.levels.WARN
		)
	end

	local key = key_of(details, column)
	if not key then
		return db.notify(("%s is not part of a foreign key"):format(tostring(column)))
	end

	local found, why = key_values(state, key, table_name)
	if not found then
		return db.notify(why, vim.log.levels.WARN)
	end

	local driver = connection.driver
	local predicates = {}
	for _, pair in ipairs(found) do
		predicates[#predicates + 1] =
			("%s = %s"):format(schema.quote(driver, pair[1]), literal(driver, pair[2]))
	end
	local statement = ("SELECT * FROM %s WHERE %s"):format(
		-- A key that names no schema of its own points inside this one.
		schema.qualify(connection, key.schema or table_schema, key.table),
		table.concat(predicates, " AND ")
	)

	-- The same cap the explorer's SELECT gets: a key usually points at one row,
	-- but nothing says the other side of it is unique.
	local limit = connection.limit or require("db.config").get().limit
	local text
	if driver == "mssql" then
		text = statement:gsub("^SELECT ", ("SELECT TOP %d "):format(limit)) .. ";"
	else
		text = ("%s LIMIT %d;"):format(statement, limit)
	end
	return require("db.buffer").new_query(connection, text)
end

--- Sort by re-running the statement with an ORDER BY, so the order is the
--- server's and covers every page -- not just the rows on screen.
function M.sort(bufnr, descending)
	local state = state_of(bufnr)
	if not state then
		return
	end
	local column = state.columns[state.column]
	if not column then
		return
	end
	require("db.execute").sort(state, column, descending)
end

function M.page(bufnr, delta)
	local state = state_of(bufnr)
	if not state then
		return
	end
	require("db.execute").page(state, delta)
end

function M.attach(bufnr)
	if vim.b[bufnr].db_grid_attached then
		return
	end
	vim.b[bufnr].db_grid_attached = true

	local function map(lhs, rhs, desc)
		vim.keymap.set("n", lhs, rhs, { buffer = bufnr, nowait = true, silent = true, desc = desc })
	end

	map("<Tab>", function()
		M.move(bufnr, 0, 1)
	end, "Grid: next column")
	map("<S-Tab>", function()
		M.move(bufnr, 0, -1)
	end, "Grid: previous column")
	map("l", function()
		M.move(bufnr, 0, 1)
	end, "Grid: next column")
	map("h", function()
		M.move(bufnr, 0, -1)
	end, "Grid: previous column")
	map("j", function()
		M.move(bufnr, 1, 0)
	end, "Grid: next row")
	map("k", function()
		M.move(bufnr, -1, 0)
	end, "Grid: previous row")
	map("0", function()
		local state = state_of(bufnr)
		state.column = 1
		grid.focus_cell(bufnr, 0)
	end, "Grid: first column")
	map("$", function()
		local state = state_of(bufnr)
		state.column = #state.columns
		grid.focus_cell(bufnr, 0)
	end, "Grid: last column")
	map("gg", function()
		local state = state_of(bufnr)
		state.row = 1
		grid.focus_cell(bufnr, 0)
	end, "Grid: first row")
	map("G", function()
		local state = state_of(bufnr)
		state.row = #state.rows
		grid.focus_cell(bufnr, 0)
	end, "Grid: last row")

	map("y", function()
		M.yank_cell(bufnr)
	end, "Grid: yank cell")
	map("Y", function()
		M.yank_row(bufnr)
	end, "Grid: yank row")
	map("<leader>qC", function()
		M.yank_column(bufnr)
	end, "Grid: yank column")

	map("s", function()
		M.sort(bufnr, false)
	end, "Grid: sort by this column")
	map("S", function()
		M.sort(bufnr, true)
	end, "Grid: sort by this column, descending")
	map("]p", function()
		M.page(bufnr, 1)
	end, "Grid: next page")
	map("[p", function()
		M.page(bufnr, -1)
	end, "Grid: previous page")
	map("gf", function()
		M.follow(bufnr)
	end, "Grid: follow this foreign key")

	map("<CR>", function()
		grid.show_document(bufnr)
	end, "Grid: show the whole document (Mongo)")
	map("q", function()
		grid.close(bufnr)
	end, "Grid: close")
	map("<Esc>", function()
		grid.close(bufnr)
	end, "Grid: close")
	map("e", function()
		require("db.grid.export").pick(bufnr)
	end, "Grid: export")
	map("d", function()
		require("db.grid.duckdb_view").materialise(bufnr)
	end, "Grid: query this result with SQL (DuckDB)")

	vim.api.nvim_create_autocmd("CursorMoved", {
		buffer = bufnr,
		group = vim.api.nvim_create_augroup("DbGrid" .. bufnr, { clear = true }),
		callback = function()
			grid.sync_from_cursor(bufnr, 0)
		end,
	})
end

return M
