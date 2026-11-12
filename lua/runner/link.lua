-- Neighbour workspaces. A link only names a path: nothing from here overrides
-- anything there, and a linked workspace is read from its own file, validated
-- on its own.
local load = require("runner.load")

local M = {}

local function links_of(workspace)
	local declared = workspace.doc and workspace.doc.link
	local by_name = {}
	if type(declared) == "table" then
		for _, link in ipairs(declared) do
			if type(link) == "table" and type(link.name) == "string" and type(link.path) == "string" then
				by_name[link.name] = link.path
			end
		end
	end
	return by_name
end

--- The workspace a link points at, read and validated.
--- `seen` carries the files already visited so a link cycle cannot loop.
--- @return table|nil workspace, string|nil err
function M.resolve(workspace, name, seen)
	local path = links_of(workspace)[name]
	if not path then
		return nil, ("no link named %q in %s"):format(name, workspace.file)
	end

	local root = load.resolve_path(workspace.root, path)
	local neighbour, err = load.open(root)
	if not neighbour then
		return nil, ("link %q: %s"):format(name, err)
	end

	seen = seen or { [workspace.file] = true }
	if seen[neighbour.file] then
		return nil, ("link cycle: %s is already in the chain"):format(neighbour.file)
	end
	seen[neighbour.file] = true

	if #neighbour.errors > 0 then
		local first = neighbour.errors[1]
		return nil,
			("link %q is not usable: %s (%s)"):format(
				name,
				first.path == "" and first.message or ("%s: %s"):format(first.path, first.message),
				neighbour.file
			)
	end

	if neighbour.name ~= name then
		return nil,
			("link %q points at a workspace called %q (%s) — the names have to match"):format(
				name,
				tostring(neighbour.name),
				neighbour.file
			)
	end

	return neighbour
end

--- The workspace a reference belongs to: this one, or the neighbour it names.
--- @return table|nil workspace, string|nil err
function M.workspace_of(workspace, ref, seen)
	if ref.workspace == nil or ref.workspace == workspace.name then
		return workspace
	end
	return M.resolve(workspace, ref.workspace, seen)
end

return M
