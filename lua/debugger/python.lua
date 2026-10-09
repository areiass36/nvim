-- Python debugging with debugpy (installed by Mason).
local dap = require("dap")
local icons = require("core.icons")
local platform = require("core.platform")
local tools = require("tools")

local M = {}

local debugpy_python = tools.mason_package("debugpy")
	.. (platform.is_windows and "/venv/Scripts/python.exe" or "/venv/bin/python")

--- On Windows "python3" (and sometimes "python") on PATH may be the Microsoft
--- Store's App Execution Alias, a stub that only prints an install hint and
--- exits with 9009 — the debuggee would die instantly in an empty console.
local function real_python(name)
	if vim.fn.executable(name) ~= 1 then
		return false
	end
	return not (platform.is_windows and vim.fn.exepath(name):find("WindowsApps", 1, true))
end

--- The project's virtualenv interpreter when there is one, else the system python.
local function project_python()
	local cwd = vim.fn.getcwd()
	for _, venv in ipairs({ "/.venv", "/venv" }) do
		local candidate = cwd .. venv .. (platform.is_windows and "/Scripts/python.exe" or "/bin/python")
		if vim.fn.executable(candidate) == 1 then
			return candidate
		end
	end
	for _, name in ipairs({ "python3", "python" }) do
		if real_python(name) then
			return name
		end
	end
	return "python"
end

function M.setup()
	dap.adapters.python = function(callback, config)
		if config.request == "attach" then
			callback({ type = "server", host = config.connect.host, port = config.connect.port })
		else
			callback({
				type = "executable",
				command = debugpy_python,
				args = { "-m", "debugpy.adapter" },
				-- detached (the default) strips the adapter of a console on
				-- Windows; its children then get a fresh one, popping an empty
				-- external terminal window.
				options = { detached = false },
			})
		end
	end

	dap.configurations.python = {
		{
			type = "python",
			request = "launch",
			name = icons.python .. "  Python · current file",
			program = "${file}",
			cwd = "${workspaceFolder}",
			pythonPath = project_python,
			console = "integratedTerminal",
			justMyCode = true,
		},
		{
			type = "python",
			request = "attach",
			name = icons.python .. "  Python · attach on port 5678",
			connect = { host = "127.0.0.1", port = 5678 },
		},
	}
end

return M
