-- Finding, reading and caching .nvim/workspace.json. The only module of the
-- runner that touches the filesystem.
local schema = require("runner.schema")

local M = {}

M.FILE = ".nvim/workspace.json"

local cache = {}

local function is_absolute(path)
	return path:match("^/") ~= nil or path:match("^%a:[/\\]") ~= nil
end

--- Absolute path of something written in a workspace file, read relative to the
--- workspace that declares it.
function M.resolve_path(root, path)
	local normalized = vim.fs.normalize(path)
	if is_absolute(normalized) then
		return normalized
	end
	return vim.fs.normalize(root .. "/" .. normalized)
end

local function search_from(bufnr)
	local name = vim.api.nvim_buf_get_name(bufnr or 0)
	if name == "" or not vim.uv.fs_stat(name) then
		return vim.fs.normalize(vim.uv.cwd())
	end
	return vim.fs.normalize(vim.fs.dirname(name))
end

--- Walk up from `from`, a directory, looking for the workspace file.
function M.find_from(from)
	from = vim.fs.normalize(from)
	if vim.uv.fs_stat(from .. "/" .. M.FILE) then
		return from
	end
	for dir in vim.fs.parents(from) do
		if vim.uv.fs_stat(dir .. "/" .. M.FILE) then
			return vim.fs.normalize(dir)
		end
	end
	return nil
end

--- Walk up from the buffer looking for the workspace file. Unlike nvim-dap's
--- launch.json provider, nothing here depends on the cwd.
function M.find(bufnr)
	return M.find_from(search_from(bufnr))
end

-- Only a line that starts with // is dropped, so a "http://host" value keeps
-- its slashes.
local function strip_comments(text)
	local kept = {}
	for line in (text .. "\n"):gmatch("([^\n]*)\n") do
		kept[#kept + 1] = vim.startswith(vim.trim(line), "//") and "" or line
	end
	return table.concat(kept, "\n")
end

--- @return table|nil doc, string|nil err
function M.read(file)
	local handle = io.open(file, "r")
	if not handle then
		return nil, ("cannot open %s"):format(file)
	end
	local text = handle:read("*a")
	handle:close()

	-- luanil on objects so a `"field": null` reads as absent instead of vim.NIL;
	-- arrays keep theirs, where a null is a typo worth reporting.
	local ok, decoded = pcall(vim.json.decode, strip_comments(text), { luanil = { object = true } })
	if not ok then
		return nil, ("invalid JSON: %s"):format(tostring(decoded):gsub("^.*:%s*", ""))
	end
	return decoded
end

local function warn_missing_links(report, workspace)
	local links = workspace.doc and workspace.doc.link
	if type(links) ~= "table" then
		return
	end
	for position, link in ipairs(links) do
		if type(link) == "table" and type(link.path) == "string" then
			local target = M.resolve_path(workspace.root, link.path) .. "/" .. M.FILE
			if not vim.uv.fs_stat(target) then
				report.warn(
					("link[%d].path"):format(position),
					("no workspace at %s yet — an error only when a member references it"):format(target)
				)
			end
		end
	end
end

local function stamp_of(stat)
	return ("%d:%d:%d"):format(stat.mtime.sec, stat.mtime.nsec, stat.size)
end

--- Read and validate the workspace rooted at `root`, memoised on the file's mtime.
--- Always returns a workspace table; `errors` says whether it is usable.
function M.open(root)
	local file = vim.fs.normalize(root) .. "/" .. M.FILE
	local stat = vim.uv.fs_stat(file)
	if not stat then
		return nil, ("no %s under %s"):format(M.FILE, root)
	end

	local stamp = stamp_of(stat)
	local hit = cache[file]
	if hit and hit.stamp == stamp then
		return hit.workspace
	end

	local workspace = { root = vim.fs.normalize(root), file = file }
	local doc, err = M.read(file)
	local report = schema.new_report()

	if not doc then
		report.error("", err)
	else
		workspace.doc = doc
		workspace.name = type(doc.workspace) == "string" and doc.workspace or nil
		local _, errors, warnings = schema.validate(doc)
		vim.list_extend(report.errors, errors)
		vim.list_extend(report.warnings, warnings)
		warn_missing_links(report, workspace)
	end

	workspace.errors = report.errors
	workspace.warnings = report.warnings
	cache[file] = { stamp = stamp, workspace = workspace }
	return workspace
end

--- The workspace a buffer belongs to.
function M.current(bufnr)
	local root = M.find(bufnr)
	if not root then
		return nil, ("no %s above this buffer"):format(M.FILE)
	end
	return M.open(root)
end

function M.invalidate()
	cache = {}
end

return M
