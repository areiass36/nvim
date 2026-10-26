-- Breakpoints survive restarts: they are saved per project when nvim exits and
-- restored the first time a file that had them is opened.
local dap_breakpoints = require("dap.breakpoints")

local M = {}

local store = {}
local restored = {}

local function project_root()
	local cwd = vim.fn.getcwd()
	return vim.fs.root(cwd, ".git") or cwd
end

local function store_path()
	local dir = vim.fn.stdpath("state") .. "/dap-breakpoints"
	vim.fn.mkdir(dir, "p")
	return ("%s/%s.json"):format(dir, vim.fn.sha256(project_root()))
end

local function read_store()
	local path = store_path()
	if vim.fn.filereadable(path) == 0 then
		return {}
	end
	local ok, lines = pcall(vim.fn.readfile, path)
	if not ok then
		return {}
	end
	local decoded, data = pcall(vim.json.decode, table.concat(lines, "\n"))
	return (decoded and type(data) == "table") and data or {}
end

local function save()
	local saved = {}
	for bufnr, placed in pairs(dap_breakpoints.get()) do
		local name = vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_get_name(bufnr) or ""
		if name ~= "" and #placed > 0 then
			local entries = {}
			for _, breakpoint in ipairs(placed) do
				entries[#entries + 1] = {
					line = breakpoint.line,
					condition = breakpoint.condition,
					hitCondition = breakpoint.hitCondition,
					logMessage = breakpoint.logMessage,
				}
			end
			saved[name] = entries
		end
	end
	if next(saved) then
		pcall(vim.fn.writefile, { vim.json.encode(saved) }, store_path())
	else
		pcall(vim.fn.delete, store_path())
	end
end

--- Lines move while a file is edited outside nvim, so an entry past the end of
--- the buffer is dropped instead of placing a sign nvim would reject.
local function restore(bufnr)
	local name = vim.api.nvim_buf_get_name(bufnr)
	if name == "" or restored[name] then
		return
	end
	local entries = store[name]
	if not entries then
		return
	end
	restored[name] = true
	local last_line = vim.api.nvim_buf_line_count(bufnr)
	for _, entry in ipairs(entries) do
		if entry.line <= last_line then
			dap_breakpoints.set({
				condition = entry.condition,
				hitCondition = entry.hitCondition,
				logMessage = entry.logMessage,
			}, bufnr, entry.line)
		end
	end
end

function M.setup()
	store = read_store()
	local group = vim.api.nvim_create_augroup("DapBreakpointPersistence", { clear = true })
	vim.api.nvim_create_autocmd("BufReadPost", {
		group = group,
		callback = function(args)
			restore(args.buf)
		end,
	})
	vim.api.nvim_create_autocmd("VimLeavePre", { group = group, callback = save })
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(bufnr) then
			restore(bufnr)
		end
	end
end

return M
