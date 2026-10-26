-- The explorer's preview pane.
--
-- What it draws lives in M.render, which takes a buffer and fills it; the
-- Telescope previewer is a thin adapter over that. Keeping them apart means the
-- content can be exercised without a running picker.
local layout = require("db.grid.layout")
local schema = require("db.schema")

local M = {}

local function set(bufnr, lines)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end
	vim.bo[bufnr].modifiable = true
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
	vim.bo[bufnr].modifiable = false
end

local function connection_lines(connection)
	local lines = {
		("name      %s"):format(connection.name),
		("driver    %s"):format(connection.driver),
		("scope     %s"):format(connection.scope or "-"),
	}
	if connection.file then
		lines[#lines + 1] = ("file      %s"):format(connection.file)
	else
		lines[#lines + 1] = ("host      %s:%s"):format(connection.host or "?", connection.port or "?")
		lines[#lines + 1] = ("database  %s"):format(connection.database or "-")
		lines[#lines + 1] = ("user      %s"):format(connection.user or "-")
	end
	lines[#lines + 1] = ("password  %s"):format((connection.password_source or {}).kind or "none")
	local jar = require("tools.jdbc").jar(connection.driver)
	lines[#lines + 1] = ("driver    %s"):format(jar and vim.fs.basename(jar) or "downloads on first use")
	local info = require("db.jvm").info(connection.id)
	if info and info.product then
		lines[#lines + 1] = ("server    %s"):format(info.product)
	end
	if connection.readonly then
		lines[#lines + 1] = "read-only"
	end
	if connection.production then
		lines[#lines + 1] = "production"
	end
	return lines
end

local function column_lines(column, name)
	return {
		("name       %s"):format(column.name or name),
		("type       %s"):format(column.type or "-"),
		("nullable   %s"):format(tostring(column.nullable)),
		("primary    %s"):format(tostring(column.is_pk)),
		("default    %s"):format(tostring(column.default_expr or "-")),
		column.count and ("documents  %s"):format(tostring(column.count)) or nil,
	}
end

local function flags_of(column)
	local flags = {}
	if column.is_pk == true or column.is_pk == 1 then
		flags[#flags + 1] = "PK"
	end
	if column.nullable == false or column.nullable == 0 then
		flags[#flags + 1] = "NOT NULL"
	end
	if column.count then
		flags[#flags + 1] = ("%s docs"):format(column.count)
	end
	return table.concat(flags, " ")
end

--- Fill `bufnr` with what is worth knowing about `entry`.
---
--- For a table that means two round trips -- the columns, then a handful of
--- rows -- so the buffer is written twice and `on_done` fires after the second.
--- @param on_done fun(lines: string[])|nil
function M.render(level_name, context, entry, bufnr, on_done)
	local function finish(lines)
		set(bufnr, lines)
		if on_done then
			on_done(lines)
		end
	end

	if level_name == "connections" then
		return finish(connection_lines(entry.value))
	end

	if level_name == "columns" then
		return finish(column_lines(entry.column or {}, entry.value))
	end

	if level_name ~= "tables" then
		return finish({ tostring(entry.text or entry.value) })
	end

	set(bufnr, { "loading..." })
	schema.columns(context.connection, context.schema, entry.value, function(columns, err)
		if err then
			return finish({ "columns: " .. err })
		end
		local lines = {}
		for _, column in ipairs(columns or {}) do
			lines[#lines + 1] = ("%-28s %-22s %s"):format(
				column.name or "",
				column.type or "",
				flags_of(column)
			)
		end
		lines[#lines + 1] = ""
		lines[#lines + 1] = "sample"
		lines[#lines + 1] = ""
		set(bufnr, lines)

		schema.sample(context.connection, context.schema, entry.value, 5, function(result, sample_err)
			if sample_err then
				lines[#lines + 1] = "(" .. sample_err .. ")"
			elseif not result or #(result.columns or {}) == 0 then
				lines[#lines + 1] = "(no rows)"
			else
				-- Narrow columns: the preview pane is half a window wide.
				local computed = layout.compute(result.columns, result.rows, { max_width = 24 })
				vim.list_extend(lines, (layout.render(computed, result.columns, result.rows, {})))
			end
			finish(lines)
		end)
	end, context.catalog)
end

function M.previewer(level_name, context)
	local ok, previewers = pcall(require, "telescope.previewers")
	if not ok then
		return nil
	end

	return previewers.new_buffer_previewer({
		title = "Details",
		define_preview = function(self, entry)
			M.render(level_name, context, entry.value, self.state.bufnr)
		end,
	})
end

return M
