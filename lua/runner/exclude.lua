-- The `exclude` globs of .nvim/workspace.json, made usable by a picker. Pure:
-- paths in, answers out. Every glob is relative to the workspace root, with the
-- gitignore reading of a slash: `dist` or `*.min.js` match a name at any depth,
-- `apps/legacy` or `apps/*/dist` only from the root.
local M = {}

local function trim(glob)
	return (glob:gsub("^/+", ""):gsub("/+$", ""))
end

local function anchored(glob)
	return glob:find("/", 1, true) ~= nil
end

--- A predicate over absolute paths: true when one of `globs` hides the path
--- itself or a folder above it. Paths outside `root` are never hidden.
--- @return fun(path: string): boolean
function M.matcher(globs, root)
	local rules = {}
	for _, glob in ipairs(globs) do
		glob = trim(glob)
		if glob ~= "" then
			rules[#rules + 1] = { lpeg = vim.glob.to_lpeg(glob), anchored = anchored(glob) }
		end
	end

	return function(path)
		local relative = vim.fs.relpath(root, vim.fs.normalize(path))
		if not relative or relative == "." or #rules == 0 then
			return false
		end
		local parts = vim.split(relative, "/", { plain = true })
		for _, rule in ipairs(rules) do
			for depth = 1, #parts do
				local subject = rule.anchored and table.concat(parts, "/", 1, depth) or parts[depth]
				if rule.lpeg:match(subject) then
					return true
				end
			end
		end
		return false
	end
end

--- The same globs as rg arguments for a search that runs in `cwd`. rg reads an
--- anchored glob from the directory it searches, so one written from the root
--- is rewritten from `cwd`, and dropped when it points somewhere else.
--- @return string[] args
function M.rg_args(globs, root, cwd)
	local below = vim.fs.relpath(root, vim.fs.normalize(cwd))
	local args = {}
	for _, glob in ipairs(globs) do
		glob = trim(glob)
		if glob ~= "" and (not anchored(glob) or vim.startswith(glob, "**/")) then
			args[#args + 1] = "--glob=!" .. glob
		elseif glob ~= "" and below == "." then
			args[#args + 1] = "--glob=!/" .. glob
		elseif glob ~= "" and below and vim.startswith(glob, below .. "/") then
			args[#args + 1] = "--glob=!/" .. glob:sub(#below + 2)
		end
	end
	return args
end

return M
