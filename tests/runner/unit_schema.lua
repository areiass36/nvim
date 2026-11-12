-- Every validation rule of .nvim/workspace.json, one case each. No filesystem
-- except the two fixtures, which exist to exercise the real reader.
local support = require("tests.runner.support")
local schema = require("runner.schema")

local check = support.check
local doc = support.doc
local paths = support.paths
local message = support.message

local function ok_of(value)
	local ok = schema.validate(value)
	return ok
end

support.describe("version and overall shape")
check("nil is not a document", paths(nil), { "" })
check("an empty object is not a document", paths(vim.empty_dict()), { "" })
check("an unknown version stops everything else", paths({ version = 2, project = "nonsense" }), { "version" })
check("a missing version is reported as version", paths({ workspace = "demo" }), { "version" })
check("the minimal document is valid", ok_of(doc()), true)
check("an unknown root field is rejected", paths(doc({ projects = {} })), { "projects" })

support.describe("names")
check("workspace is required", paths({ version = 1, project = doc().project }), { "workspace" })
check("a space is not a name", paths(doc({ workspace = "my workspace" })), { "workspace" })
check(
	"two projects cannot share a name",
	paths(
		doc({ project = { doc().project[1], { name = "api", path = "x", runner = doc().project[1].runner } } })
	),
	{ "project[2].name" }
)
check(
	"two runners of a project cannot share a label",
	paths(doc({
		project = {
			{
				name = "api",
				path = "apps/api",
				runner = {
					{ label = "main", command = { "a" } },
					{ label = "main", command = { "b" } },
				},
			},
		},
	})),
	{ "project[1].runner[2].label" }
)
check(
	"two clusters cannot share a name",
	paths(doc({
		cluster = {
			{ name = "local", member = { { project = "api", runner = "main" } } },
			{ name = "local", member = { { project = "api", runner = "main" } } },
		},
	})),
	{ "cluster[2].name" }
)
check(
	"two links cannot share a name",
	paths(doc({ link = { { name = "e2e", path = "../a" }, { name = "e2e", path = "../b" } } })),
	{ "link[2].name" }
)

support.describe("runner")
check(
	"a command string is rejected with the array to use",
	message(
		doc({
			project = {
				{ name = "api", path = "apps/api", runner = { { label = "main", command = "npm run dev" } } },
			},
		}),
		"project[1].runner[1].command"
	),
	'expected an array of strings, got a string ("npm run dev") — use ["npm", "run", "dev"]'
)
check(
	"a runner must say what to run",
	paths(doc({ project = { { name = "api", path = "apps/api", runner = { { label = "main" } } } } })),
	{ "project[1].runner[1]" }
)
check(
	"an empty command is rejected",
	paths(doc({
		project = { { name = "api", path = "apps/api", runner = { { label = "main", command = {} } } } },
	})),
	{ "project[1].runner[1].command" }
)
check(
	"a non-string word is reported at its index",
	paths(doc({
		project = {
			{ name = "api", path = "apps/api", runner = { { label = "main", command = { "npm", 3 } } } },
		},
	})),
	{ "project[1].runner[1].command[2]" }
)
check(
	"env values must be strings",
	paths(doc({
		project = {
			{
				name = "api",
				path = "apps/api",
				runner = { { label = "main", command = { "a" }, env = { PORT = 3000 } } },
			},
		},
	})),
	{ "project[1].runner[1].env.PORT" }
)
check(
	"a typo in a runner field is caught",
	paths(doc({
		project = {
			{
				name = "api",
				path = "apps/api",
				runner = { { label = "main", command = { "a" }, singletn = true } },
			},
		},
	})),
	{ "project[1].runner[1].singletn" }
)
check(
	"project path is required",
	paths(doc({ project = { { name = "api", runner = { { label = "main", command = { "a" } } } } } })),
	{ "project[1].path" }
)

support.describe("ready")
local function with_ready(ready, debug_spec)
	return doc({
		project = {
			{
				name = "api",
				path = "apps/api",
				runner = { { label = "main", command = { "a" }, ready = ready, debug = debug_spec } },
			},
		},
	})
end
check(
	"two signals are rejected",
	paths(with_ready({ port = 3000, log = "up" })),
	{ "project[1].runner[1].ready" }
)
check("no signal is rejected", paths(with_ready({ timeout = 1000 })), { "project[1].runner[1].ready" })
check(
	"a port out of range is rejected",
	paths(with_ready({ port = 70000 })),
	{ "project[1].runner[1].ready.port" }
)
check(
	"status without http means nothing",
	paths(with_ready({ port = 3000, status = 200 })),
	{ "project[1].runner[1].ready.status" }
)
check("port alone is valid", ok_of(with_ready({ port = 3000 })), true)
check(
	"http with a status is valid",
	ok_of(with_ready({ http = "http://localhost:5173", status = 200 })),
	true
)
check(
	"log cannot be used with a dap-launched process",
	message(with_ready({ log = "listening" }, { adapter = "pwa-node" }), "project[1].runner[1].ready.log"),
	'cannot be used with debug.request "launch": the debug adapter owns the output — use port or http'
)
check(
	"log is fine when the dap only attaches",
	ok_of(with_ready({ log = "listening" }, { adapter = "pwa-node", request = "attach" })),
	true
)

support.describe("debug and when")
check(
	"an adapter name is required",
	paths(doc({
		project = {
			{
				name = "api",
				path = "apps/api",
				runner = { { label = "main", debug = { request = "launch" } } },
			},
		},
	})),
	{ "project[1].runner[1].debug.adapter" }
)
check(
	"request is launch or attach",
	paths(doc({
		project = {
			{
				name = "api",
				path = "apps/api",
				runner = { { label = "main", debug = { adapter = "pwa-node", request = "start" } } },
			},
		},
	})),
	{ "project[1].runner[1].debug.request" }
)
check(
	"an unknown os is rejected",
	paths(doc({
		project = {
			{
				name = "api",
				path = "apps/api",
				runner = { { label = "main", command = { "a" }, when = { os = { "darwin" } } } },
			},
		},
	})),
	{ "project[1].runner[1].when.os[1]" }
)
check(
	"mac, windows and linux are the names",
	ok_of(doc({
		project = {
			{
				name = "api",
				path = "apps/api",
				runner = {
					{ label = "main", command = { "a" }, when = { os = { "mac", "windows", "linux" } } },
				},
			},
		},
	})),
	true
)

support.describe("references")
local function two_runners(extra)
	local main = vim.tbl_extend("force", { label = "main", command = { "a" } }, extra or {})
	return {
		{ name = "api", path = "apps/api", runner = { main, { label = "peer", command = { "b" } } } },
	}
end
check(
	"a bare runner reference means the same project",
	ok_of(doc({ project = two_runners({ depends = { { runner = "peer" } } }) })),
	true
)
check(
	"an unknown runner is reported",
	paths(doc({ project = two_runners({ depends = { { runner = "ghost" } } }) })),
	{ "project[1].runner[1].depends[1].runner" }
)
check(
	"an unknown project is reported",
	paths(doc({ project = two_runners({ depends = { { project = "web", runner = "http" } } }) })),
	{ "project[1].runner[1].depends[1].project" }
)
check(
	"a runner cannot depend on a cluster",
	message(
		doc({
			project = two_runners({ depends = { { cluster = "local" } } }),
			cluster = { { name = "local", member = { { project = "api", runner = "peer" } } } },
		}),
		"project[1].runner[1].depends[1].cluster"
	),
	"a runner can only depend on another runner, not on a cluster"
)
check(
	"after belongs to a cluster member, not to depends",
	message(
		doc({ project = two_runners({ depends = { { runner = "peer", after = { { runner = "peer" } } } } }) }),
		"project[1].runner[1].depends[1].after"
	),
	"only a cluster member can declare after"
)
check(
	"a cluster member can carry after",
	ok_of(doc({
		project = two_runners(),
		cluster = {
			{
				name = "local",
				member = {
					{ project = "api", runner = "main" },
					{ project = "api", runner = "peer", after = { { project = "api", runner = "main" } } },
				},
			},
		},
	})),
	true
)
check(
	"a member needs a project when there is nothing to fall back to",
	paths(
		doc({ project = two_runners(), cluster = { { name = "local", member = { { runner = "main" } } } } })
	),
	{ "cluster[1].member[1]" }
)
check(
	"an unknown cluster is reported",
	paths(
		doc({ project = two_runners(), cluster = { { name = "local", member = { { cluster = "ghost" } } } } })
	),
	{ "cluster[1].member[1].cluster" }
)
check(
	"a foreign workspace must be declared in link",
	paths(doc({
		project = two_runners(),
		cluster = { { name = "probe", member = { { workspace = "e2e", project = "p", runner = "r" } } } },
	})),
	{ "cluster[1].member[1].workspace" }
)
check(
	"a linked workspace resolves later, not here",
	ok_of(doc({
		project = two_runners(),
		link = { { name = "e2e", path = "../mark-e2e" } },
		cluster = { { name = "probe", member = { { workspace = "e2e", project = "p", runner = "r" } } } },
	})),
	true
)
check(
	"a reference typo is caught",
	paths(
		doc({ project = two_runners(), cluster = { { name = "local", member = { { runners = "main" } } } } })
	),
	{ "cluster[1].member[1]" }
)

support.describe("default")
check(
	"a cluster default resolves",
	ok_of(doc({
		project = two_runners(),
		cluster = { { name = "local", member = { { project = "api", runner = "main" } } } },
		default = { cluster = "local" },
	})),
	true
)
check(
	"a runner default needs its project",
	message(doc({ project = two_runners(), default = { runner = "main" } }), "default"),
	"project is required here: there is no runner of its own to fall back to"
)
check(
	"a runner default resolves with the project",
	ok_of(doc({ project = two_runners(), default = { project = "api", runner = "main" } })),
	true
)

support.describe("fixtures read from disk")
local valid = support.fixture("valid")
local valid_ok, valid_errors = schema.validate(valid)
check("the valid fixture passes", valid_ok, true)
if not valid_ok then
	for _, entry in ipairs(valid_errors) do
		support.note(schema.format(entry))
	end
end
check("comments do not reach the decoder", valid.workspace, "demo")
check("the broken fixture reports every path", paths(support.fixture("broken")), {
	"cluster[1].member[2].runner",
	"project[1].runner[1].command",
	"project[1].runner[2].ready",
})
