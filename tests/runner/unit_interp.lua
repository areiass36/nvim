-- ${...} substitution: the names it knows, the ones it refuses, and the fact
-- that a variable resolves where the runner is declared.
local support = require("tests.runner.support")
local interp = require("runner.interp")

local check = support.check

local scope = {
	workspaceRoot = "P:/Sandbox/Notes",
	projectRoot = "P:/Sandbox/Notes/apps/api",
	inputs = { dbName = "peer" },
}

local function expanded(text)
	local value = interp.expand(text, scope)
	return value
end

local function errors(text)
	local _, found = interp.expand(text, scope)
	return found
end

support.describe("the names it knows")
check("workspaceRoot", expanded("${workspaceRoot}/scripts/x.mjs"), "P:/Sandbox/Notes/scripts/x.mjs")
check("projectRoot", expanded("${projectRoot}/data/mark.db"), "P:/Sandbox/Notes/apps/api/data/mark.db")
check(
	"two in one string",
	expanded("${projectRoot} under ${workspaceRoot}"),
	"P:/Sandbox/Notes/apps/api under P:/Sandbox/Notes"
)
check("an answered input", expanded("data/${input:dbName}.db"), "data/peer.db")
check("a string with no variable is untouched", expanded("npm run dev"), "npm run dev")

support.describe("env")
vim.env.RUNNER_TEST_VALUE = "3100"
check("a set variable", expanded("http://localhost:${env:RUNNER_TEST_VALUE}"), "http://localhost:3100")
vim.env.RUNNER_TEST_VALUE = nil
check("an unset variable is an error, not an empty string", errors("${env:RUNNER_TEST_VALUE}"), {
	"RUNNER_TEST_VALUE is not set in the environment",
})
check(
	"the token survives so the report can show it",
	expanded("${env:RUNNER_TEST_VALUE}"),
	"${env:RUNNER_TEST_VALUE}"
)

support.describe("what it refuses")
check("a typo is not silently empty", errors("${projectRot}/data"), { "unknown variable ${projectRot}" })
check("an unanswered input", errors("${input:ghost}"), { "no answer for ${input:ghost} yet" })

support.describe("deep application")
local applied, deep_errors = interp.apply({
	command = { "node", "${projectRoot}/x.mjs" },
	env = { MARK_DB_PATH = "${projectRoot}/data/peer.db", BAD = "${nope}" },
	ready = { port = 3000 },
}, scope, "project[1].runner[1]")
check("arrays are expanded", applied.command, { "node", "P:/Sandbox/Notes/apps/api/x.mjs" })
check("maps are expanded", applied.env.MARK_DB_PATH, "P:/Sandbox/Notes/apps/api/data/peer.db")
check("numbers pass through", applied.ready.port, 3000)
check("an error carries the field path", deep_errors, {
	{ path = "project[1].runner[1].env.BAD", message = "unknown variable ${nope}" },
})

support.describe("inputs needed")
check(
	"collected once each, before anything is expanded",
	interp.inputs_needed({
		env = { A = "${input:dbName}", B = "${input:dbName}" },
		command = { "x", "${input:port}" },
	}),
	{ "dbName", "port" }
)
check("none when there is no input", interp.inputs_needed({ command = { "npm", "run", "dev" } }), {})
