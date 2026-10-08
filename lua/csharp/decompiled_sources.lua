-- Buffers under the ILSpy source cache: read-only, no diagnostics (generated
-- code does not build as a regular project) and loaded into the running
-- Roslyn client so navigation works inside them.
local ilspy = require("csharp.ilspy")

local M = {}

local opened_projects = {}

local function normalized_root()
	return vim.fs.normalize(ilspy.source_root) .. "/"
end

--- Is this file part of the decompiled source cache?
function M.owns(filename)
	return vim.fs.normalize(filename):find(normalized_root(), 1, true) ~= nil
end

function M.project_root(bufnr)
	return vim.fs.root(bufnr, function(name)
		return name:match("%.csproj$") ~= nil
	end)
end

--- Ask the running Roslyn client to load the decompiled project (once per project).
function M.open_in_roslyn(project_dir)
	local csproj = vim.fn.glob(project_dir .. "/*.csproj")
	if csproj == "" or opened_projects[csproj] then
		return
	end
	local client = vim.lsp.get_clients({ name = "roslyn_ls" })[1]
	if not client then
		return
	end
	opened_projects[csproj] = true
	client:notify("project/open", { projects = { vim.uri_from_fname(csproj) } })
end

function M.on_buffer_read(bufnr)
	if not M.owns(vim.api.nvim_buf_get_name(bufnr)) then
		return
	end
	vim.bo[bufnr].readonly = true
	vim.diagnostic.enable(false, { bufnr = bufnr })
	local root = M.project_root(bufnr)
	if root then
		M.open_in_roslyn(root)
	end
end

return M
