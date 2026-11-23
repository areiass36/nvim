-- Shape and reference rules of .nvim/workspace.json. Pure: no filesystem, no
-- processes, no knowledge of the rest of the runner. Cycles and cross-workspace
-- references need the neighbour files, so they are checked by resolve/link.
local M = {}

M.VERSION = 1
M.READY_TIMEOUT_MS = 60000

local SLUG = "^[%w][%w%-_%.]*$"
local REQUESTS = { launch = true, attach = true }
local OS_NAMES = { windows = true, mac = true, linux = true }
local READY_SIGNALS = { "port", "log", "http", "delay" }

local KNOWN = {
	root = {
		version = true,
		workspace = true,
		default = true,
		link = true,
		project = true,
		cluster = true,
		exclude = true,
	},
	project = { name = true, path = true, runner = true },
	runner = {
		label = true,
		command = true,
		cwd = true,
		env = true,
		ready = true,
		depends = true,
		debug = true,
		when = true,
		singleton = true,
		oneShot = true,
	},
	ready = { port = true, log = true, http = true, status = true, delay = true, timeout = true },
	when = { os = true, env = true },
	reference = { workspace = true, project = true, runner = true, cluster = true, after = true },
	cluster = { name = true, member = true, stopTogether = true },
	link = { name = true, path = true },
}

-- An empty JSON object and an empty JSON array decode to the same Lua table, so
-- both predicates accept it instead of guessing.
local function is_list(value)
	return type(value) == "table" and (next(value) == nil or vim.islist(value))
end

local function is_object(value)
	return type(value) == "table" and (next(value) == nil or not vim.islist(value))
end

local function describe(value)
	local kind = type(value)
	if kind == "nil" then
		return "nothing"
	elseif value == vim.NIL then
		return "null"
	elseif kind == "string" then
		return ("a string (%q)"):format(value)
	elseif kind == "number" or kind == "boolean" then
		return ("a %s (%s)"):format(kind, tostring(value))
	elseif kind == "table" then
		return is_list(value) and "an array" or "an object"
	end
	return kind
end

function M.new_report()
	local report = { errors = {}, warnings = {} }

	function report.error(path, message)
		report.errors[#report.errors + 1] = { path = path, message = message }
	end

	function report.warn(path, message)
		report.warnings[#report.warnings + 1] = { path = path, message = message }
	end

	return report
end

function M.format(entry)
	return entry.path == "" and entry.message or ("%s: %s"):format(entry.path, entry.message)
end

-- --------------------------------------------------------------- primitives
local function want_string(report, path, value, what)
	if type(value) ~= "string" or value == "" then
		report.error(path, ("expected %s, got %s"):format(what, describe(value)))
		return false
	end
	return true
end

local function want_slug(report, path, value, what)
	if not want_string(report, path, value, what) then
		return false
	end
	if not value:match(SLUG) then
		report.error(
			path,
			("%q is not a valid name: letters, digits, - _ . only, starting with a letter or digit"):format(
				value
			)
		)
		return false
	end
	return true
end

local function want_integer(report, path, value, what, min, max)
	if type(value) ~= "number" or value ~= math.floor(value) then
		report.error(path, ("expected %s, got %s"):format(what, describe(value)))
		return false
	end
	if (min and value < min) or (max and value > max) then
		local range = max and ("between %d and %d"):format(min, max) or ("of at least %d"):format(min)
		report.error(path, ("expected %s %s, got %d"):format(what, range, value))
		return false
	end
	return true
end

local function want_boolean(report, path, value)
	if type(value) ~= "boolean" then
		report.error(path, ("expected true or false, got %s"):format(describe(value)))
		return false
	end
	return true
end

local function want_array(report, path, value, what)
	if not is_list(value) then
		report.error(path, ("expected %s, got %s"):format(what, describe(value)))
		return false
	end
	if #value == 0 then
		report.error(path, ("expected %s with at least one entry, got an empty array"):format(what))
		return false
	end
	return true
end

local function want_object(report, path, value, what)
	if not is_object(value) then
		report.error(path, ("expected %s, got %s"):format(what, describe(value)))
		return false
	end
	return true
end

local function want_string_map(report, path, value, what)
	if not want_object(report, path, value, what) then
		return false
	end
	local ok = true
	for key, entry in pairs(value) do
		if type(key) ~= "string" then
			report.error(path, ("expected string keys, got a %s key"):format(type(key)))
			ok = false
		elseif type(entry) ~= "string" then
			report.error(("%s.%s"):format(path, key), ("expected a string, got %s"):format(describe(entry)))
			ok = false
		end
	end
	return ok
end

local function reject_unknown(report, path, value, known)
	for key in pairs(value) do
		if type(key) == "string" and not known[key] then
			report.error(path == "" and key or ("%s.%s"):format(path, key), "unknown field")
		end
	end
end

-- ----------------------------------------------------------------- pieces
local function validate_ready(report, path, ready, runner)
	if not want_object(report, path, ready, "an object") then
		return
	end

	local found = {}
	for _, signal in ipairs(READY_SIGNALS) do
		if ready[signal] ~= nil then
			found[#found + 1] = signal
		end
	end
	if #found ~= 1 then
		local got = #found == 0 and "none of them" or ("%s"):format(table.concat(found, ", "))
		report.error(path, ("expected exactly one of port, log, http or delay, got %s"):format(got))
	end

	if ready.port ~= nil then
		want_integer(report, path .. ".port", ready.port, "a TCP port", 1, 65535)
	end
	if ready.log ~= nil then
		want_string(report, path .. ".log", ready.log, "a Lua pattern to match in the output")
	end
	if ready.http ~= nil then
		want_string(report, path .. ".http", ready.http, "a URL")
	end
	if ready.status ~= nil then
		want_integer(report, path .. ".status", ready.status, "an HTTP status", 100, 599)
		if ready.http == nil then
			report.error(path .. ".status", "only means something next to http")
		end
	end
	if ready.delay ~= nil then
		want_integer(report, path .. ".delay", ready.delay, "a duration in milliseconds", 1, 3600000)
	end
	if ready.timeout ~= nil then
		want_integer(report, path .. ".timeout", ready.timeout, "a duration in milliseconds", 1, 3600000)
	end

	-- A dap-launched process writes to the adapter's own terminal, out of reach
	-- of the output matcher.
	if ready.log ~= nil and is_object(runner.debug) and (runner.debug.request or "launch") == "launch" then
		report.error(
			path .. ".log",
			'cannot be used with debug.request "launch": the debug adapter owns the output — use port or http'
		)
	end

	reject_unknown(report, path, ready, KNOWN.ready)
end

local function validate_debug(report, path, spec)
	if not want_object(report, path, spec, "an object") then
		return
	end
	want_string(report, path .. ".adapter", spec.adapter, "an adapter name registered in nvim-dap")
	if spec.request ~= nil then
		if type(spec.request) ~= "string" or not REQUESTS[spec.request] then
			report.error(
				path .. ".request",
				('expected "launch" or "attach", got %s'):format(describe(spec.request))
			)
		end
	end
end

local function validate_when(report, path, when)
	if not want_object(report, path, when, "an object") then
		return
	end
	if when.os ~= nil and want_array(report, path .. ".os", when.os, "an array of operating systems") then
		for index, name in ipairs(when.os) do
			local entry = ("%s.os[%d]"):format(path, index)
			if type(name) ~= "string" or not OS_NAMES[name] then
				report.error(entry, ('expected "windows", "mac" or "linux", got %s'):format(describe(name)))
			end
		end
	end
	if when.env ~= nil then
		want_string_map(report, path .. ".env", when.env, "an object of environment variables")
	end
	reject_unknown(report, path, when, KNOWN.when)
end

--- `opts.cluster` allows a cluster reference, `opts.after` allows the composition
--- edge, `opts.owner` is the project a bare `runner` belongs to.
local function validate_reference(report, path, ref, index, opts)
	if not is_object(ref) or next(ref) == nil then
		report.error(
			path,
			('expected an object like { "project": "api", "runner": "main" }, got %s'):format(describe(ref))
		)
		return
	end

	if ref.cluster ~= nil and ref.runner ~= nil then
		report.error(path, "expected either cluster or runner, not both")
		return
	end
	if ref.cluster == nil and ref.runner == nil then
		report.error(path, opts.cluster and "expected a runner or a cluster" or "expected a runner")
		return
	end
	if ref.cluster ~= nil and not opts.cluster then
		report.error(path .. ".cluster", "a runner can only depend on another runner, not on a cluster")
		return
	end

	local foreign = false
	if ref.workspace ~= nil then
		if want_slug(report, path .. ".workspace", ref.workspace, "a name declared in link[]") then
			foreign = true
			if not index.links[ref.workspace] then
				report.error(
					path .. ".workspace",
					("no link named %q — declare it in link[]"):format(ref.workspace)
				)
			end
		end
	end

	if ref.after ~= nil then
		if not opts.after then
			report.error(path .. ".after", "only a cluster member can declare after")
		elseif want_array(report, path .. ".after", ref.after, "an array of references") then
			for index_, entry in ipairs(ref.after) do
				validate_reference(report, ("%s.after[%d]"):format(path, index_), entry, index, {
					cluster = true,
					after = false,
					owner = opts.owner,
				})
			end
		end
	end

	reject_unknown(report, path, ref, KNOWN.reference)

	if ref.cluster ~= nil then
		if want_slug(report, path .. ".cluster", ref.cluster, "a cluster name") and not foreign then
			if not index.clusters[ref.cluster] then
				report.error(
					path .. ".cluster",
					("no cluster named %q in this workspace"):format(ref.cluster)
				)
			end
		end
		return
	end

	if not want_slug(report, path .. ".runner", ref.runner, "a runner label") then
		return
	end
	local project = ref.project
	if project ~= nil then
		if not want_slug(report, path .. ".project", project, "a project name") then
			return
		end
	else
		project = opts.owner
		if project == nil then
			report.error(path, "project is required here: there is no runner of its own to fall back to")
			return
		end
	end
	if foreign then
		return
	end

	local known = index.projects[project]
	if not known then
		report.error(
			path .. (ref.project and ".project" or ""),
			("no project named %q in this workspace"):format(project)
		)
	elseif not known[ref.runner] then
		report.error(path .. ".runner", ("project %q has no runner labelled %q"):format(project, ref.runner))
	end
end

local function command_hint(value)
	local parts = {}
	for _, word in ipairs(vim.split(value, "%s+", { trimempty = true })) do
		parts[#parts + 1] = ("%q"):format(word)
	end
	return ("[%s]"):format(table.concat(parts, ", "))
end

local function validate_runner(report, path, runner, index, owner)
	if not want_object(report, path, runner, "an object") then
		return
	end
	want_slug(report, path .. ".label", runner.label, "a label")

	if runner.command == nil and runner.debug == nil then
		report.error(path, "expected command, debug, or both: nothing here says what to run")
	end

	if runner.command ~= nil then
		local field = path .. ".command"
		if type(runner.command) == "string" then
			report.error(
				field,
				("expected an array of strings, got %s — use %s"):format(
					describe(runner.command),
					command_hint(runner.command)
				)
			)
		elseif want_array(report, field, runner.command, "an array of strings") then
			for index_, word in ipairs(runner.command) do
				want_string(report, ("%s[%d]"):format(field, index_), word, "a string")
			end
		end
	end

	if runner.cwd ~= nil then
		want_string(report, path .. ".cwd", runner.cwd, "a directory")
	end
	if runner.env ~= nil then
		want_string_map(report, path .. ".env", runner.env, "an object of environment variables")
	end
	if runner.ready ~= nil then
		validate_ready(report, path .. ".ready", runner.ready, runner)
	end
	if
		runner.depends ~= nil
		and want_array(report, path .. ".depends", runner.depends, "an array of references")
	then
		for index_, ref in ipairs(runner.depends) do
			validate_reference(report, ("%s.depends[%d]"):format(path, index_), ref, index, {
				cluster = false,
				after = false,
				owner = owner,
			})
		end
	end
	if runner.debug ~= nil then
		validate_debug(report, path .. ".debug", runner.debug)
	end
	if runner.when ~= nil then
		validate_when(report, path .. ".when", runner.when)
	end
	if runner.singleton ~= nil then
		want_boolean(report, path .. ".singleton", runner.singleton)
	end
	if runner.oneShot ~= nil then
		want_boolean(report, path .. ".oneShot", runner.oneShot)
	end

	reject_unknown(report, path, runner, KNOWN.runner)
end

local function validate_project(report, path, project, index)
	if not want_object(report, path, project, "an object") then
		return
	end
	want_slug(report, path .. ".name", project.name, "a project name")
	want_string(report, path .. ".path", project.path, "a path relative to the workspace root")
	if want_array(report, path .. ".runner", project.runner, "an array of runners") then
		for index_, runner in ipairs(project.runner) do
			validate_runner(report, ("%s.runner[%d]"):format(path, index_), runner, index, project.name)
		end
	end
	reject_unknown(report, path, project, KNOWN.project)
end

local function validate_cluster(report, path, cluster, index)
	if not want_object(report, path, cluster, "an object") then
		return
	end
	want_slug(report, path .. ".name", cluster.name, "a cluster name")
	if want_array(report, path .. ".member", cluster.member, "an array of members") then
		for index_, member in ipairs(cluster.member) do
			validate_reference(report, ("%s.member[%d]"):format(path, index_), member, index, {
				cluster = true,
				after = true,
				owner = nil,
			})
		end
	end
	if cluster.stopTogether ~= nil then
		want_boolean(report, path .. ".stopTogether", cluster.stopTogether)
	end
	reject_unknown(report, path, cluster, KNOWN.cluster)
end

local function validate_link(report, path, link)
	if not want_object(report, path, link, "an object") then
		return
	end
	want_slug(report, path .. ".name", link.name, "a name")
	want_string(report, path .. ".path", link.path, "a path to another workspace")
	reject_unknown(report, path, link, KNOWN.link)
end

-- --------------------------------------------------------------- the index
local function remember(report, path, seen, name, what)
	if type(name) ~= "string" then
		return
	end
	if seen[name] then
		report.error(path, ("duplicate %s %q, already declared at %s"):format(what, name, seen[name]))
		return
	end
	seen[name] = path
end

local function build_index(report, doc)
	local index =
		{ projects = {}, clusters = {}, links = {}, at = { projects = {}, clusters = {}, links = {} } }

	for position, link in ipairs(is_list(doc.link) and doc.link or {}) do
		if is_object(link) then
			remember(report, ("link[%d].name"):format(position), index.at.links, link.name, "link")
			if type(link.name) == "string" then
				index.links[link.name] = true
			end
		end
	end

	for position, project in ipairs(is_list(doc.project) and doc.project or {}) do
		if is_object(project) then
			local path = ("project[%d]"):format(position)
			remember(report, path .. ".name", index.at.projects, project.name, "project")
			if type(project.name) == "string" then
				local runners = index.projects[project.name] or {}
				index.projects[project.name] = runners
				local seen = {}
				for spot, runner in ipairs(is_list(project.runner) and project.runner or {}) do
					if is_object(runner) then
						remember(
							report,
							("%s.runner[%d].label"):format(path, spot),
							seen,
							runner.label,
							"runner"
						)
						if type(runner.label) == "string" then
							runners[runner.label] = true
						end
					end
				end
			end
		end
	end

	for position, cluster in ipairs(is_list(doc.cluster) and doc.cluster or {}) do
		if is_object(cluster) then
			remember(
				report,
				("cluster[%d].name"):format(position),
				index.at.clusters,
				cluster.name,
				"cluster"
			)
			if type(cluster.name) == "string" then
				index.clusters[cluster.name] = true
			end
		end
	end

	return index
end

-- ------------------------------------------------------------------ entry
--- @return boolean ok, table errors, table warnings
function M.validate(doc)
	local report = M.new_report()

	if not is_object(doc) or next(doc) == nil then
		report.error(
			"",
			("expected a JSON object with version, workspace and project, got %s"):format(describe(doc))
		)
		return false, report.errors, report.warnings
	end

	if doc.version ~= M.VERSION then
		report.error(
			"version",
			("expected %d, got %s: this runner does not know how to read that file"):format(
				M.VERSION,
				describe(doc.version)
			)
		)
		return false, report.errors, report.warnings
	end

	want_slug(report, "workspace", doc.workspace, "a workspace name")

	local index = build_index(report, doc)

	if want_array(report, "project", doc.project, "an array of projects") then
		for position, project in ipairs(doc.project) do
			validate_project(report, ("project[%d]"):format(position), project, index)
		end
	end

	if doc.cluster ~= nil and want_array(report, "cluster", doc.cluster, "an array of clusters") then
		for position, cluster in ipairs(doc.cluster) do
			validate_cluster(report, ("cluster[%d]"):format(position), cluster, index)
		end
	end

	if doc.link ~= nil and want_array(report, "link", doc.link, "an array of links") then
		for position, link in ipairs(doc.link) do
			validate_link(report, ("link[%d]"):format(position), link, index)
		end
	end

	-- Globs handed to rg as --glob=!<entry>, so a leading ! would turn the
	-- exclusion back into an inclusion.
	if doc.exclude ~= nil and want_array(report, "exclude", doc.exclude, "an array of globs") then
		for position, glob in ipairs(doc.exclude) do
			local path = ("exclude[%d]"):format(position)
			if want_string(report, path, glob, "a glob") and vim.startswith(glob, "!") then
				report.error(path, ("%q: every entry already excludes, drop the leading !"):format(glob))
			end
		end
	end

	if doc.default ~= nil then
		validate_reference(
			report,
			"default",
			doc.default,
			index,
			{ cluster = true, after = false, owner = nil }
		)
	end

	reject_unknown(report, "", doc, KNOWN.root)

	return #report.errors == 0, report.errors, report.warnings
end

return M
