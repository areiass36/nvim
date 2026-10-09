-- Node, TypeScript, Vue and React debugging with vscode-js-debug (Mason).
local dap = require("dap")
local icons = require("core.icons")
local platform = require("core.platform")
local tools = require("tools")

local M = {}

local INSPECTOR_PORT = 9229
local CHROME_PORT = 9222
local SKIP_FILES = { "<node_internals>/**", "**/node_modules/**" }

-- Node processes that are never the application: language servers, the
-- debugger itself, editor helpers, and the tsx/nodemon supervisors whose child
-- is the real process.
local PROCESS_NOISE = {
	"/mason/",
	"Code Helper",
	"js%-debug",
	"tsserver",
	"typingsInstaller",
	"esbuild",
	"vite/node_modules",
	"/%.bin/tsx",
	"/%.bin/nodemon",
}

local function notify(message, level)
	vim.notify("[dap] " .. message, level or vim.log.levels.INFO)
end

--- Folder of the package.json closest to the current file (monorepo friendly).
local function package_dir()
	return vim.fs.root(0, "package.json") or vim.fn.getcwd()
end

-- --------------------------------------------------------------- helpers
--- Wait (inside nvim-dap's coroutine) until a local TCP port accepts connections.
local function wait_for_port(port, timeout_ms)
	local co = coroutine.running()
	local deadline = vim.uv.now() + timeout_ms
	local function attempt()
		local tcp = vim.uv.new_tcp()
		tcp:connect("127.0.0.1", port, function(err)
			tcp:close()
			if not err then
				return vim.schedule(function()
					coroutine.resume(co, true)
				end)
			end
			if vim.uv.now() > deadline then
				return vim.schedule(function()
					coroutine.resume(co, false)
				end)
			end
			vim.defer_fn(attempt, 250)
		end)
	end
	attempt()
	return coroutine.yield()
end

--- PID listening on a local TCP port (nil when nobody is, or without lsof).
local function port_owner(port)
	if vim.fn.executable("lsof") == 0 then
		return nil
	end
	local output = vim.fn.system({ "lsof", "-tiTCP:" .. port, "-sTCP:LISTEN", "-nP" })
	return tonumber(vim.trim(output):match("%d+"))
end

local function process_command(pid)
	return vim.trim(vim.fn.system({ "ps", "-o", "command=", "-p", tostring(pid) })):sub(1, 60)
end

--- Readable label for a node process: "src/server.ts   tsx   pid 55483".
local function process_label(process)
	local command = process.name
	local script = command:match("%s([^%s]+%.[cm]?[jt]sx?)%s*$")
		or command:match("%s([^%s]+%.[cm]?[jt]sx?)%s")
		or ""
	script = script:gsub("^file://", ""):gsub(vim.pesc(vim.fn.getcwd()) .. "/", "")
	local tool = command:match("/%.bin/([%w%-]+)")
		or (command:find("/tsx/", 1, true) and "tsx")
		or (command:find("nodemon", 1, true) and "nodemon")
		or "node"
	if script == "" then
		script = command:match("([^/%s]+)%s*$") or command
	end
	local args = command:match("/%.bin/[%w%-]+%s+(.*)$")
	if args and script == tool then
		script = args
	end
	return ("%-40s  %-8s  pid %d"):format(script:sub(1, 40), tool, process.pid)
end

local function pick_node_process()
	return require("dap.utils").pick_process({
		prompt = "Node process: ",
		label = process_label,
		filter = function(process)
			if not process.name:find("node", 1, true) then
				return false
			end
			for _, pattern in ipairs(PROCESS_NOISE) do
				if process.name:find(pattern) then
					return false
				end
			end
			return true
		end,
	})
end

--- Attach to a running node process. On Unix, SIGUSR1 makes Node open the
--- inspector on 9229 even without --inspect (tsx watch, nodemon, npm run dev).
--- Windows has no SIGUSR1, so js-debug's attach-by-pid is used there instead.
local function inspector_port_for_picked_process()
	if platform.is_windows then
		return nil
	end
	local pid = pick_node_process()
	if pid == dap.ABORT then
		return pid
	end
	local owner = port_owner(INSPECTOR_PORT)
	if owner and owner ~= pid then
		notify(
			("port %d is already taken by process %d (%s), so process %d cannot open its inspector. Restart the application (or stop process %d) and try again."):format(
				INSPECTOR_PORT,
				owner,
				process_command(owner),
				pid,
				owner
			),
			vim.log.levels.ERROR
		)
		return dap.ABORT
	end
	if not owner then
		vim.uv.kill(pid, "sigusr1")
	end
	if not wait_for_port(INSPECTOR_PORT, 4000) then
		notify(
			('process %d did not open the inspector on port %d. Is it really the node process of your application (e.g. "...preflight.cjs ... server.ts")? Is it running?'):format(
				pid,
				INSPECTOR_PORT
			),
			vim.log.levels.ERROR
		)
		return dap.ABORT
	end
	return INSPECTOR_PORT
end

local function require_listening(port, hint)
	return function()
		if not wait_for_port(port, 1000) then
			notify(("nothing is listening on 127.0.0.1:%d. %s"):format(port, hint), vim.log.levels.ERROR)
			return dap.ABORT
		end
		return port
	end
end

--- Pick an npm script of the current package (dev scripts first).
local function pick_npm_script()
	local package_json = package_dir() .. "/package.json"
	local ok, json = pcall(function()
		return vim.json.decode(table.concat(vim.fn.readfile(package_json), "\n"))
	end)
	local scripts = ok and json.scripts or {}
	local names = vim.tbl_keys(scripts)
	if #names == 0 then
		notify("no scripts in " .. package_json, vim.log.levels.ERROR)
		return dap.ABORT
	end
	table.sort(names, function(a, b)
		local a_dev, b_dev = a:match("^dev") and 0 or 1, b:match("^dev") and 0 or 1
		if a_dev ~= b_dev then
			return a_dev < b_dev
		end
		return a < b
	end)
	local prompt = "npm script in " .. vim.fn.fnamemodify(package_dir(), ":t") .. ": "
	local choice = require("dap.ui").pick_one(names, prompt, function(name)
		return ("%-16s %s"):format(name, scripts[name]:sub(1, 70))
	end)
	return choice and { "run", choice } or dap.ABORT
end

--- Suggest the dev server URL by probing the usual ports (https first: Vite with mkcert).
local function dev_server_url()
	local default = "http://localhost:5173"
	for _, url in ipairs({
		"https://localhost:5173",
		"http://localhost:5173",
		"https://localhost:3000",
		"http://localhost:3000",
	}) do
		local probe = vim.system({
			"curl",
			"-sk",
			"-o",
			platform.null_device,
			"-w",
			"%{http_code}",
			"--max-time",
			"1",
			url,
		}):wait()
		if probe.code == 0 and probe.stdout ~= "" and probe.stdout ~= "000" then
			default = url
			break
		end
	end
	return vim.fn.input("Dev server URL: ", default)
end

-- -------------------------------------------------------- configurations
local node_configurations = {
	{
		type = "pwa-node",
		request = "launch",
		name = icons.node .. "  Node · npm run <script>  (starts the current package)",
		cwd = package_dir,
		runtimeExecutable = "npm",
		runtimeArgs = pick_npm_script,
		-- tsx/vite/nodemon spawn children: js-debug attaches to all of them.
		autoAttachChildProcesses = true,
		console = "integratedTerminal",
		sourceMaps = true,
		skipFiles = SKIP_FILES,
	},
	{
		type = "pwa-node",
		request = "launch",
		name = icons.node .. "  Node · current file",
		program = "${file}",
		cwd = "${workspaceFolder}",
		sourceMaps = true,
		skipFiles = { "<node_internals>/**" },
	},
	{
		type = "pwa-node",
		request = "launch",
		name = icons.node .. "  Node · current file with tsx",
		program = "${file}",
		cwd = "${workspaceFolder}",
		runtimeExecutable = "npx",
		runtimeArgs = { "tsx" },
		sourceMaps = true,
		skipFiles = { "<node_internals>/**" },
	},
	{
		type = "pwa-node",
		request = "attach",
		name = icons.node .. "  Node · attach (running process)",
		processId = function()
			return platform.is_windows and pick_node_process() or nil
		end,
		port = inspector_port_for_picked_process,
		cwd = "${workspaceFolder}",
		sourceMaps = true,
		skipFiles = SKIP_FILES,
	},
	{
		type = "pwa-node",
		request = "attach",
		name = icons.node .. "  Node · attach on port 9229 (--inspect)",
		port = require_listening(
			INSPECTOR_PORT,
			"Start the process with --inspect (node --inspect ... or tsx --inspect ...)."
		),
		cwd = "${workspaceFolder}",
		sourceMaps = true,
		skipFiles = SKIP_FILES,
	},
}

local browser_configurations = {
	{
		type = "pwa-chrome",
		request = "launch",
		name = icons.chrome .. "  Chrome · open dev server (Vue/React)",
		url = dev_server_url,
		-- The web app root (its package.json folder), not the monorepo root.
		webRoot = package_dir,
		sourceMaps = true,
	},
	{
		type = "pwa-chrome",
		request = "attach",
		name = icons.chrome .. "  Chrome · attach to a running Chrome (port 9222)",
		port = require_listening(
			CHROME_PORT,
			'Start Chrome with --remote-debugging-port=9222 or use "Chrome · open dev server".'
		),
		webRoot = package_dir,
		sourceMaps = true,
	},
}

function M.setup()
	local server = tools.mason_package("js-debug-adapter") .. "/js-debug/src/dapDebugServer.js"
	-- "node", "node-terminal" and "chrome" are the type names used by .vscode/launch.json.
	for _, adapter in ipairs({ "pwa-node", "pwa-chrome", "node", "node-terminal", "chrome" }) do
		dap.adapters[adapter] = {
			type = "server",
			host = "localhost",
			port = "${port}",
			-- See python.lua: detached adapters pop console windows on Windows.
			executable = { command = "node", args = { server, "${port}" }, detached = false },
		}
	end

	local all = vim.list_extend(vim.deepcopy(node_configurations), browser_configurations)
	for _, filetype in ipairs({ "javascript", "typescript", "javascriptreact", "typescriptreact" }) do
		dap.configurations[filetype] = all
	end
	dap.configurations.vue = browser_configurations
end

return M
