-- Table and column completion from the schema cache.
--
-- Registered per filetype rather than added to the global source list in
-- plugins/lsp/completion.lua, so it never runs in a Lua or C# buffer. The
-- filetype list has to repeat nvim_lsp and minuet because cmp.setup.filetype
-- replaces the sources rather than adding to them.
local resolve = require("db.resolve")
local schema = require("db.schema")

local M = {}

local source = {}

function source.new()
	return setmetatable({}, { __index = source })
end

function source:is_available()
	local filetype = vim.bo.filetype
	return filetype == "sql" or filetype == "mysql" or filetype == "plsql" or filetype == "mongodb"
end

function source:get_debug_name()
	return "db"
end

--- An alias before the dot tells us which table's columns to offer.
--- "select u.| from users u" -> users
local function table_for_alias(bufnr, alias)
	local text = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
	local pattern = ('[Ff][Rr][Oo][Mm]%%s+([%%w_%%."`%%[%%]]+)%%s+%%f[%%w]%s%%f[^%%w]'):format(alias)
	local found = text:match(pattern)
	if not found then
		pattern = ('[Jj][Oo][Ii][Nn]%%s+([%%w_%%."`%%[%%]]+)%%s+%%f[%%w]%s%%f[^%%w]'):format(alias)
		found = text:match(pattern)
	end
	if not found then
		return nil
	end
	-- Strip quoting and any schema qualifier.
	return (found:gsub('["`%[%]]', ""):gsub(".*%.", ""))
end

function source:complete(request, callback)
	local bufnr = vim.api.nvim_get_current_buf()
	local connection = resolve.for_buf(bufnr)
	if not connection then
		return callback({ items = {}, isIncomplete = false })
	end

	local line = request.context.cursor_before_line or ""
	local alias = line:match("([%w_]+)%.$") or line:match("([%w_]+)%.[%w_]*$")

	local function finish(items)
		callback({ items = items, isIncomplete = false })
	end

	if alias then
		local table_name = table_for_alias(bufnr, alias) or alias
		return schema.columns(connection, connection.default_schema, table_name, function(columns, err)
			if err or not columns then
				return finish({})
			end
			local items = {}
			for _, column in ipairs(columns) do
				items[#items + 1] = {
					label = tostring(column.name),
					kind = require("cmp").lsp.CompletionItemKind.Field,
					detail = tostring(column.type or ""),
				}
			end
			finish(items)
		end)
	end

	schema.tables(connection, connection.default_schema, nil, function(tables, err)
		if err or not tables then
			return finish({})
		end
		local items = {}
		for _, record in ipairs(tables) do
			items[#items + 1] = {
				label = tostring(record.name),
				kind = require("cmp").lsp.CompletionItemKind.Class,
				detail = tostring(record.kind or "table"),
			}
		end
		finish(items)
	end)
end

function M.setup()
	local ok, cmp = pcall(require, "cmp")
	if not ok then
		return
	end
	cmp.register_source("db", source.new())
	cmp.setup.filetype({ "sql", "mysql", "plsql", "mongodb" }, {
		sources = {
			{ name = "db", group_index = 1 },
			{ name = "nvim_lsp", group_index = 1 },
			{ name = "minuet", group_index = 2 },
		},
	})
end

return M
