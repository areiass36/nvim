-- Public API of the workspace runner: it reads .nvim/workspace.json and starts
-- what it declares. Knows nothing about this config — no require of debugger,
-- core or tools, and nvim-dap is reached only from runner/dap.lua.
local M = {}

local defaults = {
	icons = { ok = "ok", warn = "!", error = "x", cluster = "#", runner = ">" },
}

M.options = vim.deepcopy(defaults)

function M.setup(opts)
	M.options = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
	require("runner.command").setup()
end

--- The workspace of a buffer, validated.
--- @return table|nil workspace, string|nil err
function M.check(bufnr)
	return require("runner.load").current(bufnr)
end

--- What running `target` would do: the runners, in waves, already expanded.
--- `target` is an address string, a reference object, or nil for the default.
--- @return table|nil plan, string|nil err
function M.plan(target, bufnr)
	local workspace, err = require("runner.load").current(bufnr)
	if not workspace then
		return nil, err
	end

	local ref = target
	if type(target) == "string" and target ~= "" then
		local parsed, parse_err = require("runner.address").parse(target)
		if not parsed then
			return nil, parse_err
		end
		ref = parsed
	elseif type(target) ~= "table" then
		ref = nil
	end

	return require("runner.resolve").plan(workspace, ref)
end

--- Every address declared in the buffer's workspace, for completion and pickers.
--- @return string[] addresses
function M.addresses(bufnr)
	local workspace = require("runner.load").current(bufnr)
	local doc = workspace and workspace.doc
	if not doc then
		return {}
	end

	local found = {}
	for _, cluster in ipairs(doc.cluster or {}) do
		found[#found + 1] = "#" .. cluster.name
	end
	for _, project in ipairs(doc.project or {}) do
		for _, runner in ipairs(project.runner or {}) do
			found[#found + 1] = ("%s:%s"):format(project.name, runner.label)
		end
	end
	return found
end

--- The `exclude` globs of the workspace above `dir` (the cwd by default) and
--- that workspace's root, or nothing when there is none. Read even when the rest
--- of the file has errors: hiding files from a picker does not depend on the
--- runners being right. The read is memoised on the file's mtime, so asking on
--- every picker costs a stat and an edit is seen on the next one.
--- @return string[] globs, string|nil root
function M.exclude(dir)
	local load = require("runner.load")
	local root = load.find_from(dir or vim.uv.cwd())
	local workspace = root and load.open(root)
	local globs = workspace and workspace.doc and workspace.doc.exclude
	if type(globs) ~= "table" then
		return {}, root
	end
	return vim.tbl_filter(function(glob)
		return type(glob) == "string" and glob ~= "" and not vim.startswith(glob, "!")
	end, globs), root
end

function M.reload()
	require("runner.load").invalidate()
end

return M
