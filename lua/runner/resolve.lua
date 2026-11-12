-- From a reference to a plan: which runners, in which order, with every ${...}
-- already expanded. `depends` is the runner's own edge and travels with it;
-- `after` belongs to a cluster member and lives only inside that cluster. Both
-- end up in the same graph, so parallelism is simply the absence of an edge.
local address = require("runner.address")
local interp = require("runner.interp")
local link = require("runner.link")
local load = require("runner.load")
local schema = require("runner.schema")

local M = {}

local function os_name()
	if vim.fn.has("win32") == 1 then
		return "windows"
	end
	local sysname = vim.uv.os_uname().sysname
	if sysname == "Darwin" then
		return "mac"
	end
	if sysname == "Linux" then
		return "linux"
	end
	return sysname
end

local function when_allows(when)
	if type(when) ~= "table" then
		return true, nil
	end
	if type(when.os) == "table" and not vim.tbl_contains(when.os, os_name()) then
		return false, ("this is for %s, and we are on %s"):format(table.concat(when.os, "/"), os_name())
	end
	if type(when.env) == "table" then
		for name, wanted in pairs(when.env) do
			if vim.env[name] ~= wanted then
				return false, ("%s is not %q here"):format(name, wanted)
			end
		end
	end
	return true, nil
end

local function find_project(workspace, name)
	for _, project in ipairs(workspace.doc.project or {}) do
		if project.name == name then
			return project
		end
	end
	return nil
end

local function find_runner(project, label)
	for _, runner in ipairs(project.runner or {}) do
		if runner.label == label then
			return runner
		end
	end
	return nil
end

local function find_cluster(workspace, name)
	for _, cluster in ipairs(workspace.doc.cluster or {}) do
		if cluster.name == name then
			return cluster
		end
	end
	return nil
end

-- --------------------------------------------------------------- the spec
local function build_spec(state, workspace, project, declaration, path)
	local scope = {
		workspaceRoot = workspace.root,
		projectRoot = load.resolve_path(workspace.root, project.path),
		inputs = state.inputs,
	}

	local expanded, errors = interp.apply({
		command = declaration.command,
		cwd = declaration.cwd,
		env = declaration.env,
		ready = declaration.ready,
		debug = declaration.debug,
	}, scope, path)

	for _, entry in ipairs(errors) do
		state.errors[#state.errors + 1] = entry
	end

	expanded.cwd = expanded.cwd or scope.projectRoot
	expanded.env = expanded.env or {}
	if expanded.ready then
		expanded.ready.timeout = expanded.ready.timeout or schema.READY_TIMEOUT_MS
	end
	expanded.singleton = declaration.singleton == true
	expanded.oneShot = declaration.oneShot == true
	expanded.projectRoot = scope.projectRoot
	expanded.workspaceRoot = scope.workspaceRoot
	return expanded
end

-- --------------------------------------------------------------- the graph
local function fail(state, path, message)
	state.errors[#state.errors + 1] = { path = path, message = message }
end

local function edge(state, from, to, kind)
	state.edges[#state.edges + 1] = { from = from, to = to, kind = kind }
end

local add_runner, expand_ref

--- @return table|nil node
add_runner = function(state, workspace, project, declaration, path)
	local absolute = address.format({
		workspace = workspace.name,
		project = project.name,
		runner = declaration.label,
	})
	if state.by_address[absolute] then
		return state.by_address[absolute]
	end

	local allowed, why = when_allows(declaration.when)
	local node = {
		address = absolute,
		display = workspace.name == state.entry.name and address.format({
			project = project.name,
			runner = declaration.label,
		}) or absolute,
		workspace = workspace,
		project = project,
		declaration = declaration,
		spec = build_spec(state, workspace, project, declaration, path),
		skipped = not allowed and why or nil,
	}
	state.by_address[absolute] = node
	state.nodes[#state.nodes + 1] = node

	for position, ref in ipairs(declaration.depends or {}) do
		local where = ("%s.depends[%d]"):format(path, position)
		local targets = expand_ref(state, workspace, ref, where, project.name)
		for _, target in ipairs(targets) do
			edge(state, target.address, absolute, "depends")
		end
	end

	return node
end

local function add_cluster(state, workspace, cluster, path)
	local key = ("%s#%s"):format(workspace.file, cluster.name)
	if state.open_clusters[key] then
		fail(state, path, ("cluster cycle: %s contains itself"):format(cluster.name))
		return {}
	end
	state.open_clusters[key] = true

	local produced = {}
	for position, member in ipairs(cluster.member or {}) do
		local where = ("%s.member[%d]"):format(path, position)
		local nodes = expand_ref(state, workspace, member, where, nil)
		for _, node in ipairs(nodes) do
			produced[#produced + 1] = node
		end
		for spot, after in ipairs(member.after or {}) do
			local upstream = expand_ref(state, workspace, after, ("%s.after[%d]"):format(where, spot), nil)
			for _, source in ipairs(upstream) do
				for _, node in ipairs(nodes) do
					edge(state, source.address, node.address, "after")
				end
			end
		end
	end

	state.open_clusters[key] = nil
	return produced
end

--- Every node a reference stands for: one for a runner, all of them for a cluster.
--- @return table nodes
expand_ref = function(state, workspace, ref, path, owner)
	local target, err = link.workspace_of(workspace, ref, state.seen_links)
	if not target then
		fail(state, path, err)
		return {}
	end

	if ref.cluster then
		local cluster = find_cluster(target, ref.cluster)
		if not cluster then
			fail(state, path, ("no cluster named %q in %s"):format(ref.cluster, target.file))
			return {}
		end
		return add_cluster(state, target, cluster, ("%s -> #%s"):format(path, ref.cluster))
	end

	local project_name = ref.project or (target == workspace and owner or nil)
	if not project_name then
		fail(state, path, "project is required here")
		return {}
	end

	local project = find_project(target, project_name)
	if not project then
		fail(state, path, ("no project named %q in %s"):format(project_name, target.file))
		return {}
	end
	local declaration = find_runner(project, ref.runner)
	if not declaration then
		fail(state, path, ("project %q has no runner labelled %q"):format(project_name, tostring(ref.runner)))
		return {}
	end

	local node = add_runner(state, target, project, declaration, ("%s -> %s"):format(path, ref.runner))
	return node and { node } or {}
end

-- ---------------------------------------------------------------- ordering
--- A node whose prerequisite cannot exist here cannot run either.
local function propagate_skips(state)
	local changed = true
	while changed do
		changed = false
		for _, link_ in ipairs(state.edges) do
			local from, to = state.by_address[link_.from], state.by_address[link_.to]
			if from and to and from.skipped and not to.skipped then
				to.skipped = ("%s is skipped (%s)"):format(from.display, from.skipped)
				changed = true
			end
		end
	end
end

--- Kahn, keeping each level as a wave. Leftovers mean a cycle.
local function layer(nodes, edges)
	local indegree, adjacency = {}, {}
	for _, node in ipairs(nodes) do
		indegree[node.address] = 0
		adjacency[node.address] = {}
	end
	for _, link_ in ipairs(edges) do
		if indegree[link_.to] ~= nil and adjacency[link_.from] ~= nil then
			indegree[link_.to] = indegree[link_.to] + 1
			table.insert(adjacency[link_.from], link_.to)
		end
	end

	local by_address = {}
	for _, node in ipairs(nodes) do
		by_address[node.address] = node
	end

	local waves, placed = {}, 0
	local ready = {}
	for _, node in ipairs(nodes) do
		if indegree[node.address] == 0 then
			ready[#ready + 1] = node
		end
	end

	while #ready > 0 do
		table.sort(ready, function(a, b)
			return a.address < b.address
		end)
		waves[#waves + 1] = ready
		placed = placed + #ready
		local next_ready = {}
		for _, node in ipairs(ready) do
			for _, target in ipairs(adjacency[node.address]) do
				indegree[target] = indegree[target] - 1
				if indegree[target] == 0 then
					next_ready[#next_ready + 1] = by_address[target]
				end
			end
		end
		ready = next_ready
	end

	if placed < #nodes then
		local stuck = {}
		for _, node in ipairs(nodes) do
			if indegree[node.address] > 0 then
				stuck[#stuck + 1] = node.display
			end
		end
		table.sort(stuck)
		return nil, stuck
	end

	return waves
end

-- ------------------------------------------------------------------ entry
--- @param workspace table from runner.load
--- @param ref table reference object; the workspace default when nil
--- @param opts table|nil { inputs = { name = answer } }
--- @return table plan
function M.plan(workspace, ref, opts)
	opts = opts or {}
	local plan = { nodes = {}, waves = {}, edges = {}, skipped = {}, errors = {} }

	if not workspace or not workspace.doc then
		plan.errors = { { path = "", message = "no workspace file" } }
		return plan
	end
	if #workspace.errors > 0 then
		plan.errors = vim.deepcopy(workspace.errors)
		return plan
	end

	ref = ref or workspace.doc.default
	if not ref then
		plan.errors = { { path = "default", message = "nothing to run: pass an address or declare default" } }
		return plan
	end

	local state = {
		entry = workspace,
		inputs = opts.inputs or {},
		nodes = {},
		by_address = {},
		edges = {},
		errors = {},
		open_clusters = {},
		seen_links = { [workspace.file] = true },
	}

	local requested = expand_ref(state, workspace, ref, "target", nil)
	plan.entry = address.format(ref)
	plan.errors = state.errors
	plan.edges = state.edges

	if #plan.errors > 0 then
		return plan
	end
	if #requested == 0 then
		plan.errors = { { path = "target", message = ("%s resolves to nothing"):format(plan.entry) } }
		return plan
	end

	propagate_skips(state)

	-- An explicit target that cannot run here is an error; a cluster member that
	-- cannot is exactly what `when` is for, so it is only reported as skipped.
	if #requested == 1 and requested[1].skipped then
		plan.errors = {
			{
				path = "target",
				message = ("%s cannot run here: %s"):format(plan.entry, requested[1].skipped),
			},
		}
		return plan
	end

	local live, skipped = {}, {}
	for _, node in ipairs(state.nodes) do
		if node.skipped then
			skipped[#skipped + 1] = node
		else
			live[#live + 1] = node
		end
	end
	plan.skipped = skipped
	plan.by_address = state.by_address

	local waves, cycle = layer(live, state.edges)
	if not waves then
		plan.errors = {
			{ path = "target", message = ("dependency cycle between %s"):format(table.concat(cycle, ", ")) },
		}
		return plan
	end

	plan.waves = waves
	for _, wave in ipairs(waves) do
		for _, node in ipairs(wave) do
			plan.nodes[#plan.nodes + 1] = node
		end
	end
	return plan
end

return M
