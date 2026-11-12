-- ${...} substitution. A variable always resolves in the workspace that
-- declares the runner, never in the one that references it, so a linked
-- workspace keeps its own roots.
local M = {}

local PLACEHOLDER = "%${([%w_:%.%-]+)}"

--- @return string|nil value, string|nil err
local function value_of(name, scope)
	if name == "workspaceRoot" then
		return scope.workspaceRoot
	end
	if name == "projectRoot" then
		return scope.projectRoot
	end

	-- An unset variable is an error, not an empty string: a half-expanded URL or
	-- path fails much later and much worse than a report here.
	local variable = name:match("^env:(.+)$")
	if variable then
		local found = vim.env[variable]
		if found == nil then
			return nil, ("%s is not set in the environment"):format(variable)
		end
		return found
	end

	local input = name:match("^input:(.+)$")
	if input then
		local answered = scope.inputs and scope.inputs[input]
		if answered == nil then
			return nil, ("no answer for ${input:%s} yet"):format(input)
		end
		return answered
	end

	return nil, ("unknown variable ${%s}"):format(name)
end

--- @return string expanded, string[] errors
function M.expand(text, scope)
	local errors = {}
	local expanded = text:gsub(PLACEHOLDER, function(name)
		local value, err = value_of(name, scope)
		if err then
			errors[#errors + 1] = err
			return nil
		end
		return value
	end)
	return expanded, errors
end

--- Deep copy with every string expanded. Errors are collected with the path of
--- the field that carried them.
--- @return any expanded, table errors
function M.apply(value, scope, path)
	local errors = {}

	local function walk(node, where)
		if type(node) == "string" then
			local expanded, found = M.expand(node, scope)
			for _, message in ipairs(found) do
				errors[#errors + 1] = { path = where, message = message }
			end
			return expanded
		end
		if type(node) ~= "table" then
			return node
		end
		local copy = {}
		for key, entry in pairs(node) do
			local child = type(key) == "number" and ("%s[%d]"):format(where, key)
				or ("%s.%s"):format(where, key)
			copy[key] = walk(entry, child)
		end
		return copy
	end

	return walk(value, path or ""), errors
end

--- Input names a declaration asks for, so the caller can prompt once per name
--- before expanding anything. Sorted, because a table has no order and the
--- prompts should not change places between runs.
function M.inputs_needed(value)
	local seen = {}

	local function walk(node)
		if type(node) == "string" then
			for name in node:gmatch(PLACEHOLDER) do
				local input = name:match("^input:(.+)$")
				if input then
					seen[input] = true
				end
			end
		elseif type(node) == "table" then
			for _, entry in pairs(node) do
				walk(entry)
			end
		end
	end

	walk(value)
	local found = vim.tbl_keys(seen)
	table.sort(found)
	return found
end

return M
