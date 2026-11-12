-- The display form of a reference: "project:label", "#cluster",
-- "ws/project:label", "ws/#cluster". UI sugar only — the file format itself
-- always carries objects, never parsed strings.
local M = {}

local NAME = "[%w][%w%-_%.]*"

function M.format(ref, owner)
	local prefix = ref.workspace and (ref.workspace .. "/") or ""
	if ref.cluster then
		return ("%s#%s"):format(prefix, ref.cluster)
	end
	local project = ref.project or owner or "?"
	return ("%s%s:%s"):format(prefix, project, ref.runner or "?")
end

--- @return table|nil ref, string|nil err
function M.parse(text)
	if type(text) ~= "string" or text == "" then
		return nil, "expected an address like api:main or #local"
	end

	local rest, workspace = text, nil
	local prefix, tail = text:match(("^(%s)/(.+)$"):format(NAME))
	if prefix then
		workspace, rest = prefix, tail
	end

	local cluster = rest:match(("^#(%s)$"):format(NAME))
	if cluster then
		return { workspace = workspace, cluster = cluster }
	end

	local project, runner = rest:match(("^(%s):(%s)$"):format(NAME, NAME))
	if project then
		return { workspace = workspace, project = project, runner = runner }
	end

	return nil, ("%q is not an address: use project:label, #cluster, or ws/ before either"):format(text)
end

return M
