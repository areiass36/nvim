-- The schema explorer: a Telescope picker you walk into, like the file browser.
--
--   connections -> databases -> schemas -> tables -> columns
--
-- <CR> goes one level in, <BS> back out, <C-s> opens a SELECT on the thing
-- under the cursor, <C-y> writes its qualified name into the buffer the picker
-- was opened from, <C-d> shows the DDL.
--
-- The window is reused between levels by refreshing the finder, so walking the
-- tree does not flash a new picker each time. Telescope's refresh is not public
-- API, so every call is wrapped and falls back to reopening.
local db = require("db")
local connections = require("db.connections")
local icons = require("core.icons")
local schema = require("db.schema")

local M = {}

local KIND_ICON = {
	table = icons.file,
	view = icons.branch,
	matview = icons.branch,
	foreign = icons.branch,
	collection = icons.file,
}

--- Each level knows how to load its entries, how to show them, and what the
--- level below it is. Exposed as M.levels so the tests can walk the tree
--- without pretending to be a keyboard.
local levels = {}
M.levels = levels

local function entry_display(text, hint)
	if not hint or hint == "" then
		return text
	end
	return ("%-40s %s"):format(text, hint)
end

levels.connections = {
	title = "Connections",
	load = function(_, callback)
		local list = {}
		for _, connection in ipairs(connections.all()) do
			list[#list + 1] = {
				value = connection,
				text = connection.name,
				hint = ("%s · %s"):format(connection.driver, connection.scope),
			}
		end
		callback(list)
	end,
	child = function(_, entry)
		local connection = entry.value
		-- SQLite has neither catalogs nor schemas.
		if connection.driver == "sqlite" then
			return { level = "tables", context = { connection = connection } }
		end
		return { level = "databases", context = { connection = connection } }
	end,
}

levels.databases = {
	title = "Databases",
	load = function(context, callback)
		schema.databases(context.connection, function(records, err)
			if err then
				return callback(nil, err)
			end
			local list = {}
			for _, record in ipairs(records) do
				list[#list + 1] = { value = record.name, text = tostring(record.name) }
			end
			callback(list)
		end)
	end,
	child = function(context, entry)
		-- Switching database means a connection pointed at that database.
		local connection = vim.tbl_extend("force", context.connection, { database = entry.value })
		if
			connection.driver == "mysql"
			or connection.driver == "mariadb"
			or connection.driver == "mongodb"
		then
			return { level = "tables", context = { connection = connection, schema = entry.value } }
		end
		return { level = "schemas", context = { connection = connection } }
	end,
}

levels.schemas = {
	title = "Schemas",
	load = function(context, callback)
		schema.schemas(context.connection, context.catalog, function(records, err)
			if err then
				return callback(nil, err)
			end
			local list = {}
			for _, record in ipairs(records) do
				list[#list + 1] = { value = record.name, text = tostring(record.name) }
			end
			if #list == 0 then
				list[1] = { value = context.connection.default_schema or "public", text = "public" }
			end
			callback(list)
		end)
	end,
	child = function(context, entry)
		return {
			level = "tables",
			context = { connection = context.connection, catalog = context.catalog, schema = entry.value },
		}
	end,
}

levels.tables = {
	title = "Tables",
	load = function(context, callback)
		schema.tables(context.connection, context.schema, nil, function(records, err)
			if err then
				return callback(nil, err)
			end
			local list = {}
			for _, record in ipairs(records) do
				local kind = tostring(record.kind or "table")
				list[#list + 1] = {
					value = record.name,
					kind = kind,
					text = ("%s %s"):format(KIND_ICON[kind] or icons.file, record.name),
					hint = kind ~= "table" and kind or nil,
				}
			end
			callback(list)
		end, context.catalog)
	end,
	child = function(context, entry)
		return {
			level = "columns",
			context = {
				connection = context.connection,
				catalog = context.catalog,
				schema = context.schema,
				table = entry.value,
			},
		}
	end,
}

levels.columns = {
	title = "Columns",
	load = function(context, callback)
		schema.columns(context.connection, context.schema, context.table, function(records, err)
			if err then
				return callback(nil, err)
			end
			local list = {}
			for _, record in ipairs(records) do
				local flags = {}
				if record.is_pk == true or record.is_pk == 1 or record.is_pk == "1" then
					flags[#flags + 1] = "PK"
				end
				if record.nullable == false or record.nullable == 0 or record.nullable == "0" then
					flags[#flags + 1] = "NOT NULL"
				end
				if record.count then
					flags[#flags + 1] = ("%s docs"):format(record.count)
				end
				list[#list + 1] = {
					value = record.name,
					column = record,
					text = tostring(record.name),
					hint = ("%s %s"):format(record.type or "", table.concat(flags, " ")),
				}
			end
			callback(list)
		end, context.catalog)
	end,
	child = function()
		return nil
	end,
}

--- What <C-y> inserts and <C-s> selects from, for the entry under the cursor.
function M.qualified_name(level, context, entry)
	if level == "columns" then
		return schema.quote(context.connection.driver, entry.value)
	end
	if level == "tables" then
		return schema.qualify(context.connection, context.schema, entry.value)
	end
	return tostring(entry.value)
end

function M.open_select(context, entry, on_done)
	local connection = context.connection
	schema.columns(connection, context.schema, entry.value, function(columns)
		local statement = schema.select_statement(connection, context.schema, entry.value, columns)
		local limit = connection.limit or require("db.config").get().limit
		local text
		if connection.driver == "mongodb" then
			text = ("%s.limit(%d)"):format(statement, limit)
		elseif connection.driver == "mssql" then
			text = statement:gsub("^SELECT ", ("SELECT TOP %d "):format(limit)) .. ";"
		else
			text = ("%s LIMIT %d;"):format(statement, limit)
		end
		local bufnr = require("db.buffer").new_query(connection, text)
		if on_done then
			on_done(bufnr, text)
		end
	end, context.catalog)
end

function M.show_ddl(context, entry, on_done)
	schema.ddl(context.connection, context.schema, entry.value, function(records, err)
		if err then
			return db.notify(err, vim.log.levels.ERROR)
		end
		local lines = {}
		for _, record in ipairs(records or {}) do
			if record.sql then
				vim.list_extend(lines, vim.split(tostring(record.sql), "\n"))
			elseif record["Create Table"] then
				vim.list_extend(lines, vim.split(tostring(record["Create Table"]), "\n"))
			else
				local flags = {}
				if record.is_pk == true or record.is_pk == 1 then
					flags[#flags + 1] = "PRIMARY KEY"
				end
				if record.nullable == false or record.nullable == 0 then
					flags[#flags + 1] = "NOT NULL"
				end
				if record.default_expr then
					flags[#flags + 1] = "DEFAULT " .. tostring(record.default_expr)
				end
				lines[#lines + 1] = ("%-30s %-24s %s"):format(
					record.name or "",
					record.type or "",
					table.concat(flags, " ")
				)
			end
		end
		if #lines == 0 then
			lines = { "(no definition reported)" }
		end
		local buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
		vim.bo[buf].filetype = "sql"
		vim.bo[buf].modifiable = false
		vim.bo[buf].bufhidden = "wipe"
		local width = math.min(110, vim.o.columns - 4)
		vim.api.nvim_open_win(buf, true, {
			relative = "editor",
			row = 1,
			col = math.floor((vim.o.columns - width) / 2),
			width = width,
			height = math.min(#lines + 2, vim.o.lines - 6),
			border = "rounded",
			title = (" %s "):format(entry.value),
			title_pos = "center",
			style = "minimal",
		})
		vim.keymap.set("n", "q", "<cmd>close<CR>", { buffer = buf, nowait = true })
		vim.keymap.set("n", "<Esc>", "<cmd>close<CR>", { buffer = buf, nowait = true })
		if on_done then
			on_done(lines, buf)
		end
	end, context.catalog)
end

--- Write a name into the buffer the picker was opened from.
---
--- Both the window and the buffer are remembered, because the window is not
--- enough: by the time this runs it may be showing something else, and putting
--- the text into whatever is current would edit the wrong file.
function M.insert_name(origin_win, origin_buf, name)
	local target_win = nil
	if
		origin_win
		and vim.api.nvim_win_is_valid(origin_win)
		and vim.api.nvim_win_get_buf(origin_win) == origin_buf
	then
		target_win = origin_win
	else
		for _, winid in ipairs(vim.api.nvim_list_wins()) do
			if vim.api.nvim_win_get_buf(winid) == origin_buf then
				target_win = winid
				break
			end
		end
	end

	if target_win then
		vim.api.nvim_set_current_win(target_win)
		vim.api.nvim_put({ name }, "c", true, true)
		return
	end

	-- The buffer is not on screen any more: write at its cursor position
	-- without making it current.
	if origin_buf and vim.api.nvim_buf_is_valid(origin_buf) then
		local mark = vim.api.nvim_buf_get_mark(origin_buf, '"')
		local row = math.max(mark[1] - 1, 0)
		local line = vim.api.nvim_buf_get_lines(origin_buf, row, row + 1, false)[1] or ""
		vim.api.nvim_buf_set_text(origin_buf, row, #line, row, #line, { name })
	end
end

--- @param opts table|nil { level, context, origin_buf, origin_win, stack }
function M.open(opts)
	opts = opts or {}
	local level_name = opts.level or "connections"
	local level = levels[level_name]
	local context = opts.context or {}
	local stack = opts.stack or {}
	local origin_buf = opts.origin_buf or vim.api.nvim_get_current_buf()
	local origin_win = opts.origin_win or vim.api.nvim_get_current_win()

	local ok_telescope, pickers = pcall(require, "telescope.pickers")
	if not ok_telescope then
		return db.notify("telescope is not available", vim.log.levels.ERROR)
	end
	local finders = require("telescope.finders")
	local conf = require("telescope.config").values
	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")

	level.load(context, function(entries, err)
		if err then
			return db.notify(err, vim.log.levels.ERROR)
		end
		if not entries or #entries == 0 then
			return db.notify(("nothing to show in %s"):format(level.title), vim.log.levels.WARN)
		end

		local title = level.title
		if context.connection then
			title = ("%s  %s"):format(level.title, context.connection.name)
			if context.schema then
				title = ("%s/%s"):format(title, context.schema)
			end
			if context.table then
				title = ("%s.%s"):format(title, context.table)
			end
		end

		pickers
			.new({
				-- Spelled out because the defaults in plugins/editor/telescope.lua
				-- are full-window and belong to the horizontal strategy.
				layout_strategy = "horizontal",
				layout_config = { width = 0.9, height = 0.85, preview_width = 0.55 },
			}, {
				prompt_title = title,
				finder = finders.new_table({
					results = entries,
					entry_maker = function(entry)
						return {
							value = entry,
							display = entry_display(entry.text, entry.hint),
							ordinal = tostring(entry.text) .. " " .. tostring(entry.hint or ""),
						}
					end,
				}),
				sorter = conf.generic_sorter({}),
				previewer = require("db.explorer.preview").previewer(level_name, context),
				attach_mappings = function(prompt_bufnr, map)
					local function selected()
						local entry = action_state.get_selected_entry()
						return entry and entry.value or nil
					end

					actions.select_default:replace(function()
						local entry = selected()
						if not entry then
							return
						end
						local child = level.child(context, entry)
						if not child then
							-- The deepest level: insert the name, which is the
							-- only useful thing left to do with a column.
							actions.close(prompt_bufnr)
							local name = M.qualified_name(level_name, context, entry)
							vim.api.nvim_win_set_cursor(origin_win, vim.api.nvim_win_get_cursor(origin_win))
							vim.api.nvim_put({ name }, "c", true, true)
							return
						end
						actions.close(prompt_bufnr)
						local next_stack = vim.deepcopy(stack)
						table.insert(next_stack, { level = level_name, context = context })
						M.open({
							level = child.level,
							context = child.context,
							stack = next_stack,
							origin_buf = origin_buf,
							origin_win = origin_win,
						})
					end)

					local function go_back()
						local previous = stack[#stack]
						if not previous then
							return
						end
						actions.close(prompt_bufnr)
						local next_stack = vim.deepcopy(stack)
						table.remove(next_stack)
						M.open({
							level = previous.level,
							context = previous.context,
							stack = next_stack,
							origin_buf = origin_buf,
							origin_win = origin_win,
						})
					end

					map("i", "<BS>", function()
						-- Only leave the level when the prompt is empty, so
						-- backspace still edits the filter.
						local prompt = action_state.get_current_line()
						if prompt == "" then
							go_back()
						else
							vim.api.nvim_feedkeys(vim.keycode("<BS>"), "n", false)
						end
					end)
					map("n", "<BS>", go_back)

					map({ "i", "n" }, "<C-s>", function()
						local entry = selected()
						if not entry or level_name ~= "tables" then
							return
						end
						actions.close(prompt_bufnr)
						M.open_select(context, entry)
					end)

					map({ "i", "n" }, "<C-y>", function()
						local entry = selected()
						if not entry then
							return
						end
						actions.close(prompt_bufnr)
						M.insert_name(origin_win, origin_buf, M.qualified_name(level_name, context, entry))
					end)

					map({ "i", "n" }, "<C-d>", function()
						local entry = selected()
						if not entry or (level_name ~= "tables" and level_name ~= "columns") then
							return
						end
						actions.close(prompt_bufnr)
						M.show_ddl(context, entry)
					end)

					map({ "i", "n" }, "<C-r>", function()
						local entry = selected()
						schema.invalidate(context.connection)
						actions.close(prompt_bufnr)
						db.notify("schema cache cleared")
						M.open({
							level = level_name,
							context = context,
							stack = stack,
							origin_buf = origin_buf,
							origin_win = origin_win,
						})
						return entry
					end)

					return true
				end,
			})
			:find()
	end)
end

return M
