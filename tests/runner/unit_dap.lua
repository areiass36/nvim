-- From a spec to an nvim-dap configuration: the fields that are ours, the ones
-- that pass through, and how `command` becomes the debuggee. Pure: config_of
-- never touches nvim-dap, so no adapter has to be registered here.
local support = require("tests.runner.support")
local runner_dap = require("runner.dap")

local check = support.check

local function node(spec)
	return {
		address = "demo/motor:local",
		display = "motor:local",
		spec = vim.tbl_deep_extend("force", { cwd = "P:/ws/engine", env = {} }, spec),
	}
end

local function config_of(spec)
	local config, err = runner_dap.config_of(node(spec))
	return config or err
end

support.describe("dap.config_of — launch")

local launch = config_of({
	command = { "P:/ws/engine/.venv/Scripts/python.exe", "P:/ws/Cli/debug_motor.py", "--ticket", "CMGT-1" },
	debug = { adapter = "python", request = "launch", justMyCode = false },
})

check("type is the adapter", launch.type, "python")
check("request", launch.request, "launch")
check("name is the display address", launch.name, "motor:local")
check("the interpreter becomes pythonPath", launch.pythonPath, "P:/ws/engine/.venv/Scripts/python.exe")
check("the next word is the program", launch.program, "P:/ws/Cli/debug_motor.py")
check("the rest are args", launch.args, { "--ticket", "CMGT-1" })
check("cwd falls back to the spec", launch.cwd, "P:/ws/engine")
check("adapter fields pass through", launch.justMyCode, false)
check("adapter is not a dap field", launch.adapter, nil)

check(
	"a declared program wins over the command",
	config_of({
		command = { "python", "ignored.py" },
		debug = { adapter = "python", request = "launch", program = "chosen.py" },
	}).program,
	"chosen.py"
)

check(
	"a module needs no program",
	config_of({ command = { "python", "x.py" }, debug = { adapter = "python", module = "motor" } }).program,
	nil
)

check(
	"an adapter without an interpreter keeps the whole command",
	config_of({ command = { "./server", "--port", "1" }, debug = { adapter = "codelldb" } }).program,
	"./server"
)

check(
	"launch with nothing to run",
	config_of({ debug = { adapter = "python" } }),
	"launch needs program, module, or a command to derive them from"
)

support.describe("dap.config_of — attach")

local attach = config_of({
	command = { "kubectl", "port-forward", "deployment/motor", "5678:5678" },
	ready = { port = 5678 },
	debug = {
		adapter = "python",
		request = "attach",
		connect = { host = "127.0.0.1", port = 5678 },
		pathMappings = { { localRoot = "P:/ws/engine", remoteRoot = "/app" } },
	},
})

check("request", attach.request, "attach")
check("connect passes through", attach.connect, { host = "127.0.0.1", port = 5678 })
check(
	"pathMappings pass through",
	attach.pathMappings,
	{ { localRoot = "P:/ws/engine", remoteRoot = "/app" } }
)
check("the command is a tunnel, not the debuggee", attach.program, nil)

check(
	"attach without a target",
	config_of({ debug = { adapter = "python", request = "attach" } }),
	"attach needs connect (or processId) in the debug block"
)

support.describe("dap.config_of — env and rejections")

check(
	"the runner env reaches the session",
	config_of({
		env = { STAGE = "dev" },
		command = { "python", "x.py" },
		debug = { adapter = "python" },
	}).env,
	{ STAGE = "dev" }
)

check(
	"a debug env is more specific than the runner env",
	config_of({
		env = { STAGE = "dev", EXTRA = "1" },
		command = { "python", "x.py" },
		debug = { adapter = "python", env = { STAGE = "prd" } },
	}).env,
	{ STAGE = "prd", EXTRA = "1" }
)

check("no debug block", config_of({ command = { "python", "x.py" } }), "this runner declares no debug block")
check("no adapter", config_of({ debug = { request = "launch" } }), "debug.adapter is required")
