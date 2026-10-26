-- Behaviour for the buffers you write queries in.
--
-- Per-filetype behaviour goes in a FileType autocommand, the way
-- lua/csharp/init.lua does it; this config has no ftplugin/ directory.
local db = require("db")
local resolve = require("db.resolve")

local M = {}

local scratch_count = 0

--- A buffer for a query that has no file yet. acwrite plus a BufWriteCmd so :w
--- asks where to put it instead of failing or leaving litter in the project.
--- @return integer bufnr
function M.new_query(connection, text)
	scratch_count = scratch_count + 1
	local bufnr = vim.api.nvim_create_buf(true, false)
	vim.api.nvim_buf_set_name(bufnr, ("db://query/%d.sql"):format(scratch_count))
	vim.bo[bufnr].buftype = "acwrite"
	vim.bo[bufnr].filetype = connection.driver == "mongodb" and "mongodb" or "sql"
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(text or "", "\n"))
	vim.bo[bufnr].modified = false

	vim.api.nvim_create_autocmd("BufWriteCmd", {
		buffer = bufnr,
		callback = function()
			vim.ui.input({ prompt = "Save this query as: ", completion = "file" }, function(path)
				if not path or path == "" then
					return
				end
				vim.cmd(("write %s"):format(vim.fn.fnameescape(vim.fn.expand(path))))
				vim.bo[bufnr].modified = false
			end)
		end,
	})

	vim.cmd("vsplit")
	vim.api.nvim_win_set_buf(vim.api.nvim_get_current_win(), bufnr)
	if connection then
		resolve.bind(bufnr, connection.id)
		require("db.dialect").attach(bufnr, connection.driver)
	end
	M.attach(bufnr)
	return bufnr
end

--- Wire up a SQL or Mongo buffer: keymaps, the dialect layer, and the
--- connection shown in the statusline.
function M.attach(bufnr)
	if vim.b[bufnr].db_attached then
		return
	end
	vim.b[bufnr].db_attached = true

	require("db.keymaps").attach_query_buffer(bufnr)

	local connection = resolve.for_buf(bufnr)
	if connection then
		require("db.dialect").attach(bufnr, connection.driver)
	end
end

--- The connection of the current buffer, for the statusline.
function M.status()
	local bufnr = vim.api.nvim_get_current_buf()
	local filetype = vim.bo[bufnr].filetype
	if filetype ~= "sql" and filetype ~= "mongodb" and filetype ~= "dbresult" then
		return ""
	end
	local running = #require("db.runner").active() > 0
	local connection = resolve.for_buf(bufnr)
	if not connection then
		return running and "db: running" or "db: no connection"
	end
	return ("%s%s"):format(connection.name, running and " (running)" or "")
end

function M.setup()
	-- Neovim has no filetype for a mongosh script.
	vim.filetype.add({ extension = { mongodb = "mongodb" } })

	vim.api.nvim_create_autocmd("FileType", {
		group = vim.api.nvim_create_augroup("DbBuffers", { clear = true }),
		pattern = { "sql", "mysql", "plsql", "mongodb" },
		callback = function(args)
			M.attach(args.buf)
		end,
	})
	-- Buffers already open when the plugin loads.
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(bufnr) then
			local filetype = vim.bo[bufnr].filetype
			if filetype == "sql" or filetype == "mongodb" then
				M.attach(bufnr)
			end
		end
	end
end

return M
