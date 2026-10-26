-- Moving around the result and taking things out of it.
--
-- Every yank and export reads the stored value, never the text on screen: what
-- is on screen may be truncated, and a WHERE clause built from an ellipsis
-- would be wrong.
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
