-- From a reference to waves: dependency order, dedupe, after edges, cycles and
-- the `when` filter. In-memory workspaces, so nothing here touches the disk.
local support = require("tests.runner.support")
local resolve = require("runner.resolve")

local check = support.check

local function workspace(doc)
	return {
		doc = doc,
		name = doc.workspace,
		root = "P:/ws",
		file = "P:/ws/.nvim/workspace.json",
		errors = {},
		warnings = {},
	}
end

--- The waves, as lists of display names: the whole point of the module.
local function waves(doc, ref)
	local plan = resolve.plan(workspace(doc), ref)
	if #plan.errors > 0 then
		return plan.errors[1].message
	end
	local shape = {}
	for _, wave in ipairs(plan.waves) do
		local names = {}
		for _, node in ipairs(wave) do
			names[#names + 1] = node.display
		end
		shape[#shape + 1] = names
	end
	return shape
end

local function first_error(doc, ref)
	local plan = resolve.plan(workspace(doc), ref)
	return plan.errors[1] and plan.errors[1].message or "no error"
end

local function runner(label, extra)
	return vim.tbl_extend("force", { label = label, command = { "run", label } }, extra or {})
end

--- api(main, peer) + web(http, chrome), the shape the Mark workspace has.
local function doc_of(overrides)
	return vim.tbl_deep_extend("force", {
		version = 1,
		workspace = "demo",
		project = {
			{ name = "api", path = "apps/api", runner = { runner("main"), runner("peer") } },
			{
				name = "web",
				path = "apps/web",
				runner = {
					runner("http", { depends = { { project = "api", runner = "main" } } }),
					runner("chrome", { depends = { { runner = "http" } } }),
				},
			},
		},
	}, overrides or {})
end

support.describe("a single runner")
check("one node, one wave", waves(doc_of(), { project = "api", runner = "main" }), { { "api:main" } })
check(
	"depends pulls what it needs into an earlier wave",
	waves(doc_of(), { project = "web", runner = "http" }),
	{ { "api:main" }, { "web:http" } }
)
check(
	"a chain of three keeps its order",
	waves(doc_of(), { project = "web", runner = "chrome" }),
	{ { "api:main" }, { "web:http" }, { "web:chrome" } }
)

support.describe("clusters")
check(
	"independent members share a wave",
	waves(
		doc_of({
			cluster = {
				{
					name = "pair",
					member = { { project = "api", runner = "main" }, { project = "api", runner = "peer" } },
				},
			},
		}),
		{ cluster = "pair" }
	),
	{ { "api:main", "api:peer" } }
)
check(
	"a member's own depends is honoured inside the cluster",
	waves(
		doc_of({
			cluster = {
				{
					name = "local",
					member = { { project = "api", runner = "main" }, { project = "web", runner = "http" } },
				},
			},
		}),
		{ cluster = "local" }
	),
	{ { "api:main" }, { "web:http" } }
)
check(
	"the same runner reached twice appears once",
	waves(
		doc_of({
			cluster = {
				{
					name = "twice",
					member = {
						{ project = "web", runner = "http" },
						{ project = "web", runner = "chrome" },
						{ project = "api", runner = "main" },
					},
				},
			},
		}),
		{ cluster = "twice" }
	),
	{ { "api:main" }, { "web:http" }, { "web:chrome" } }
)
check(
	"a nested cluster contributes its nodes",
	waves(
		doc_of({
			cluster = {
				{ name = "local", member = { { project = "api", runner = "main" } } },
				{ name = "wide", member = { { cluster = "local" }, { project = "api", runner = "peer" } } },
			},
		}),
		{ cluster = "wide" }
	),
	{ { "api:main", "api:peer" } }
)

support.describe("after: the edge that belongs to the composition")
check(
	"after forces a later wave for two otherwise parallel runners",
	waves(
		doc_of({
			cluster = {
				{
					name = "ordered",
					member = {
						{ project = "api", runner = "main" },
						{
							project = "api",
							runner = "peer",
							after = { { project = "api", runner = "main" } },
						},
					},
				},
			},
		}),
		{ cluster = "ordered" }
	),
	{ { "api:main" }, { "api:peer" } }
)
check(
	"after a nested cluster waits for every node in it",
	waves(
		doc_of({
			cluster = {
				{
					name = "local",
					member = { { project = "api", runner = "main" }, { project = "web", runner = "http" } },
				},
				{
					name = "probe",
					member = {
						{ cluster = "local" },
						{ project = "api", runner = "peer", after = { { cluster = "local" } } },
					},
				},
			},
		}),
		{ cluster = "probe" }
	),
	{ { "api:main" }, { "web:http" }, { "api:peer" } }
)

support.describe("cycles")
check(
	"two runners depending on each other",
	first_error(
		doc_of({
			project = {
				{
					name = "api",
					path = "apps/api",
					runner = {
						runner("main", { depends = { { runner = "peer" } } }),
						runner("peer", { depends = { { runner = "main" } } }),
					},
				},
			},
		}),
		{ project = "api", runner = "main" }
	),
	"dependency cycle between api:main, api:peer"
)
check(
	"a cluster that contains itself",
	first_error(
		doc_of({ cluster = { { name = "loop", member = { { cluster = "loop" } } } } }),
		{ cluster = "loop" }
	),
	"cluster cycle: loop contains itself"
)

support.describe("the when filter")
local gated = {
	cluster = {
		{
			name = "local",
			member = { { project = "api", runner = "main" }, { project = "api", runner = "peer" } },
		},
	},
	project = {
		{
			name = "api",
			path = "apps/api",
			runner = {
				runner("main"),
				runner("peer", {
					when = { env = { RUNNER_TEST_FLAG = "yes" } },
				}),
			},
		},
	},
}
vim.env.RUNNER_TEST_FLAG = "yes"
check("a satisfied when runs", waves(doc_of(gated), { cluster = "local" }), { { "api:main", "api:peer" } })
vim.env.RUNNER_TEST_FLAG = nil
check("an unsatisfied when drops the member from the cluster", waves(doc_of(gated), { cluster = "local" }), {
	{ "api:main" },
})
check(
	"asking for it directly is an error, not a silent skip",
	first_error(doc_of(gated), { project = "api", runner = "peer" }),
	'api:peer cannot run here: RUNNER_TEST_FLAG is not "yes" here'
)

local dependent = vim.tbl_deep_extend("force", gated, {
	project = {
		{
			name = "api",
			path = "apps/api",
			runner = { runner("main"), runner("peer", { when = { env = { RUNNER_TEST_FLAG = "yes" } } }) },
		},
		{
			name = "web",
			path = "apps/web",
			runner = { runner("http", { depends = { { project = "api", runner = "peer" } } }) },
		},
	},
	cluster = {
		{
			name = "local",
			member = { { project = "api", runner = "main" }, { project = "web", runner = "http" } },
		},
	},
})
check(
	"whatever needs a skipped runner is skipped too",
	waves(dependent, { cluster = "local" }),
	{ { "api:main" } }
)

support.describe("the spec each node carries")
local plan = resolve.plan(
	workspace(doc_of({
		project = {
			{
				name = "api",
				path = "apps/api",
				runner = {
					{
						label = "main",
						command = { "npm", "run", "dev" },
						env = { MARK_DB_PATH = "${projectRoot}/data/mark.db" },
						ready = { port = 3000 },
					},
					runner("peer"),
				},
			},
		},
	})),
	{ project = "api", runner = "main" }
)
local node = plan.nodes[1]
check("cwd defaults to the project root", node.spec.cwd, "P:/ws/apps/api")
check(
	"env is expanded where the runner is declared",
	node.spec.env.MARK_DB_PATH,
	"P:/ws/apps/api/data/mark.db"
)
check("ready gets the default timeout", node.spec.ready.timeout, 60000)
check("the address is absolute", node.address, "demo/api:main")
check("the display name drops the local workspace", node.display, "api:main")

support.describe("what it refuses")
check(
	"an unknown runner",
	first_error(doc_of(), { project = "api", runner = "ghost" }),
	'project "api" has no runner labelled "ghost"'
)
check(
	"an unknown cluster",
	first_error(doc_of(), { cluster = "ghost" }),
	'no cluster named "ghost" in P:/ws/.nvim/workspace.json'
)
check(
	"no target and no default",
	first_error(doc_of(), nil),
	"nothing to run: pass an address or declare default"
)
check(
	"the default is used when no target is given",
	waves(doc_of({ default = { project = "api", runner = "peer" } }), nil),
	{ { "api:peer" } }
)
local broken =
	workspace({ version = 1, workspace = "demo", project = { { name = "api", path = "x", runner = {} } } })
broken.errors =
	{ { path = "project[1].runner", message = "expected an array of runners with at least one entry" } }
check(
	"a workspace that does not validate never reaches the graph",
	resolve.plan(broken, { cluster = "any" }).errors[1].message,
	"expected an array of runners with at least one entry"
)
