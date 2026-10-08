-- .NET debugging with netcoredbg.
local dap = require("dap")
local icons = require("core.icons")
local platform = require("core.platform")
local dotnet = require("tools.dotnet")
local netcoredbg = require("tools.netcoredbg")
local ui = require("debugger.ui")

local M = {}

local function notify(message, level)
	vim.notify("[dap] " .. message, level or vim.log.levels.INFO)
end

--- Show a failed build in a float (a multi-line notify would block the editor
--- on "Press ENTER") and abort the launch.
local function report_build_failure(output)
	local lines = vim.split(output, "\n", { plain = true, trimempty = true })
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modifiable = false
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].filetype = "text"
	ui.float_buffer(buf, "dotnet build failed  (q / Esc closes)")

	local first_error = ""
	for _, line in ipairs(lines) do
		if line:find("error") then
			first_error = line:match("error%s+(.*)") or line
			break
		end
	end
	notify("dotnet build failed: " .. first_error:sub(1, 160), vim.log.levels.ERROR)
	return dap.ABORT
end

--- `dotnet <dll>` runs with the muxer found on PATH and ignores DOTNET_ROOT;
--- the apphost (same name without .dll) honours it, so prefer the apphost.
local function prefer_apphost(dll)
	local host = dll:gsub("%.dll$", platform.is_windows and ".exe" or "")
	return vim.fn.executable(host) == 1 and host or dll
end

--- Build the solution in the current directory and return the program to run.
local function build_and_pick_program()
	local cwd = vim.fn.getcwd()
	notify("dotnet build...")
	local output = vim.fn.system({ "dotnet", "build", "-c", "Debug", "--nologo", "-v", "q" })
	if vim.v.shell_error ~= 0 then
		return report_build_failure(output)
	end

	local project_names = {}
	for _, csproj in ipairs(vim.fn.glob(cwd .. "/**/*.csproj", true, true)) do
		project_names[vim.fn.fnamemodify(csproj, ":t:r")] = true
	end
	local dlls = vim.tbl_filter(function(dll)
		return project_names[vim.fn.fnamemodify(dll, ":t:r")] ~= nil
	end, vim.fn.glob(cwd .. "/**/bin/Debug/**/*.dll", true, true))

	if #dlls == 0 then
		local names = vim.tbl_keys(project_names)
		notify(
			("no dll found under %s/**/bin/Debug for projects: %s. Open Neovim in the solution or project folder."):format(
				cwd,
				#names > 0 and table.concat(names, ", ") or "(no .csproj below cwd)"
			),
			vim.log.levels.ERROR
		)
		return dap.ABORT
	end
	if #dlls == 1 then
		return prefer_apphost(dlls[1])
	end
	return coroutine.create(function(co)
		vim.ui.select(dlls, { prompt = "Which project to debug?" }, function(choice)
			coroutine.resume(co, choice and prefer_apphost(choice) or dap.ABORT)
		end)
	end)
end

--- DOTNET_ROOT for the target framework of the built dll (bin/Debug/net8.0 -> 8).
--- With several SDKs (asdf/mise) the shell's DOTNET_ROOT may lack that runtime
--- and the host fails with "You must install or update .NET to run this application".
local function runtime_environment()
	local dll = vim.fn.glob(vim.fn.getcwd() .. "/**/bin/Debug/net*/*.dll", true, true)[1]
	local major = dll and dll:match("/net(%d+)%.%d+/")
	local root = major and dotnet.root_with_runtime(major)
	if not root then
		return nil
	end
	return { DOTNET_ROOT = root, PATH = root .. platform.path_separator .. vim.env.PATH }
end

function M.setup()
	-- The binary is downloaded by tools/netcoredbg.lua; wait for it if needed.
	dap.adapters.coreclr = function(callback)
		netcoredbg.ensure(function(ok)
			if not ok then
				return notify("netcoredbg is not available", vim.log.levels.ERROR)
			end
			callback({ type = "executable", command = netcoredbg.path, args = { "--interpreter=vscode" } })
		end)
	end

	dap.configurations.cs = {
		{
			type = "coreclr",
			request = "launch",
			name = icons.dotnet .. "  .NET · build + launch",
			program = build_and_pick_program,
			cwd = "${workspaceFolder}",
			stopAtEntry = false,
			env = runtime_environment,
		},
		{
			type = "coreclr",
			request = "attach",
			name = icons.dotnet .. "  .NET · attach to process",
			processId = require("dap.utils").pick_process,
		},
	}
end

return M
