-- One workspace composing another. These write real files: link resolution is
-- the one part that has to read a neighbour's own workspace.json.
local support = require("tests.runner.support")
local load = require("runner.load")
local resolve = require("runner.resolve")

local check = support.check

local root = vim.fs.normalize(vim.fn.tempname())

local function write(where, doc)
	vim.fn.mkdir(where .. "/.nvim", "p")
	local handle = assert(io.open(where .. "/.nvim/workspace.json", "w"))
	handle:write(vim.json.encode(doc))
	handle:close()
	return where
end

local function runner(label, extra)
	return vim.tbl_extend("force", { label = label, command = { "run", label } }, extra or {})
end

local main = write(root .. "/main", {
	version = 1,
	workspace = "main",
	link = { { name = "probe", path = "../probe" } },
	project = { { name = "api", path = "apps/api", runner = { runner("dev") } } },
	cluster = {
		{ name = "local", member = { { project = "api", runner = "dev" } } },
		{
			name = "full",
			member = {
				{ cluster = "local" },
				{
					workspace = "probe",
					project = "playwright",
					runner = "audit",
					after = { { cluster = "local" } },
				},
			},
		},
		{ name = "borrowed", member = { { workspace = "probe", cluster = "audit" } } },
		{ name = "missing", member = { { workspace = "probe", project = "playwright", runner = "ghost" } } },
	},
})

write(root .. "/probe", {
	version = 1,
	workspace = "probe",
	project = {
		{
			name = "playwright",
			path = ".",
			runner = { { label = "audit", command = { "node", "${projectRoot}/audit.mjs" }, oneShot = true } },
		},
	},
	cluster = { { name = "audit", member = { { project = "playwright", runner = "audit" } } } },
})

local function plan_of(cluster)
	load.invalidate()
	return resolve.plan(load.open(main), { cluster = cluster })
end

local function waves(cluster)
	local plan = plan_of(cluster)
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

support.describe("composing a neighbour")
check("the foreign runner carries its workspace in the name", waves("full"), {
	{ "api:dev" },
	{ "probe/playwright:audit" },
})
check("a foreign cluster can be a member too", waves("borrowed"), { { "probe/playwright:audit" } })

support.describe("the neighbour's variables are the neighbour's")
local foreign = plan_of("full").nodes[2]
check(
	"projectRoot points into the linked workspace, not into this one",
	foreign.spec.command[2],
	vim.fs.normalize(root .. "/probe") .. "/audit.mjs"
)
check("and so does cwd", foreign.spec.cwd, vim.fs.normalize(root .. "/probe"))
check("the one shot flag survives the crossing", foreign.spec.oneShot, true)

support.describe("what it refuses")
check(
	"a label the neighbour does not declare",
	waves("missing"),
	'project "playwright" has no runner labelled "ghost"'
)

local renamed = {
	version = 1,
	workspace = "surprise",
	project = { { name = "p", path = ".", runner = { runner("r") } } },
}
write(root .. "/renamed", renamed)

local mismatched = write(root .. "/mismatch", {
	version = 1,
	workspace = "mismatch",
	link = { { name = "renamed", path = "../renamed" } },
	project = { { name = "api", path = ".", runner = { runner("dev") } } },
	cluster = { { name = "x", member = { { workspace = "renamed", project = "p", runner = "r" } } } },
})
load.invalidate()
local name_error = resolve.plan(load.open(mismatched), { cluster = "x" }).errors[1]
check(
	"a link whose target calls itself something else",
	name_error.message:match('^link %b"" points at a workspace called %b""') ~= nil,
	true
)

local a = root .. "/cycle-a"
local b = root .. "/cycle-b"
write(a, {
	version = 1,
	workspace = "cycle-a",
	link = { { name = "cycle-b", path = "../cycle-b" } },
	project = { { name = "p", path = ".", runner = { runner("r") } } },
	cluster = { { name = "x", member = { { workspace = "cycle-b", cluster = "y" } } } },
})
write(b, {
	version = 1,
	workspace = "cycle-b",
	link = { { name = "cycle-a", path = "../cycle-a" } },
	project = { { name = "q", path = ".", runner = { runner("s") } } },
	cluster = { { name = "y", member = { { workspace = "cycle-a", cluster = "x" } } } },
})
load.invalidate()
local cycle = resolve.plan(load.open(a), { cluster = "x" })
check(
	"a link cycle is reported, not followed forever",
	cycle.errors[1].message:find("link cycle") ~= nil,
	true
)

vim.fn.delete(root, "rf")
