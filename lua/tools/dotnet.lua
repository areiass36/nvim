-- .NET tooling: global dotnet tools installed into the config's data directory
-- (Roslyn language server, ILSpy) and SDK discovery for multi-SDK setups.
local platform = require("core.platform")
local tools = require("tools")

local M = {}

local in_flight = {}

--- Install a dotnet tool into its own folder. Runs from stdpath("data") so a
--- project's global.json (which may pin an old SDK) does not affect it.
local function install_tool(package, directory, extra_args, on_done)
	if in_flight[package] then
		table.insert(in_flight[package], on_done)
		return
	end
	in_flight[package] = { on_done }

	local function finish(ok)
		local callbacks = in_flight[package]
		in_flight[package] = nil
		for _, callback in ipairs(callbacks) do
			callback(ok)
		end
	end

	local command = { "dotnet", "tool", "install", package, "--tool-path", directory }
	vim.list_extend(command, extra_args)
	local env = {
		DOTNET_CLI_TELEMETRY_OPTOUT = "1",
		PATH = vim.env.PATH,
		HOME = vim.env.HOME,
		DOTNET_ROOT = vim.env.DOTNET_ROOT,
	}

	tools.notify("installing " .. package .. " (dotnet tool)...")
	vim.system(
		command,
		{ cwd = vim.fn.stdpath("data"), env = env },
		vim.schedule_wrap(function(result)
			local ok = result.code == 0
			if ok then
				tools.notify(package .. " ready")
			else
				tools.notify(
					"failed to install " .. package .. ": " .. (result.stderr or result.stdout or ""),
					vim.log.levels.ERROR
				)
			end
			finish(ok)
		end)
	)
end

local function ensure_tool(package, executable, extra_args)
	return function(on_done)
		on_done = on_done or function() end
		if vim.fn.executable(executable) == 1 then
			return on_done(true)
		end
		if vim.fn.executable("dotnet") == 0 then
			return on_done(false) -- no .NET SDK, no C# support
		end
		install_tool(package, vim.fn.fnamemodify(executable, ":h"), extra_args, function(ok)
			on_done(ok and vim.fn.executable(executable) == 1)
		end)
	end
end

-- Microsoft's C# language server (the one used by VS Code). Not in Mason.
M.roslyn = tools.tools_dir .. "/roslyn/roslyn-language-server" .. platform.exe_suffix
M.ensure_roslyn = ensure_tool("roslyn-language-server", M.roslyn, { "--prerelease" })

-- ILSpy command line decompiler, used to read the implementation of .NET types.
M.ilspy = tools.tools_dir .. "/ilspy/ilspycmd" .. platform.exe_suffix
M.ensure_ilspy = ensure_tool("ilspycmd", M.ilspy, {})

--- Root of a .NET installation that contains the Microsoft.NETCore.App runtime
--- of the given major version. With asdf/mise every SDK lives in its own
--- folder and the shell's DOTNET_ROOT may point to a different version.
--- @param major string|integer e.g. 8
--- @return string|nil
function M.root_with_runtime(major)
	local roots = {}
	local function add(root)
		if root and root ~= "" and not vim.tbl_contains(roots, root) then
			roots[#roots + 1] = root
		end
	end

	local sdks = vim.system({ "dotnet", "--list-sdks" }, { text = true }):wait()
	for line in (sdks.stdout or ""):gmatch("[^\n]+") do
		local path = line:match("%[(.-)%]")
		if path then
			add(vim.fn.fnamemodify(path, ":h"))
		end
	end
	add(vim.env.DOTNET_ROOT)
	local common = {
		vim.env.HOME .. "/.asdf/installs/dotnet/*",
		vim.env.HOME .. "/.local/share/mise/installs/dotnet/*",
		"/usr/local/share/dotnet",
		"/usr/share/dotnet",
		"C:/Program Files/dotnet",
	}
	for _, pattern in ipairs(common) do
		for _, dir in ipairs(vim.fn.glob(pattern, true, true)) do
			add(dir)
		end
	end

	for _, root in ipairs(roots) do
		if #vim.fn.glob(root .. "/shared/Microsoft.NETCore.App/" .. major .. ".*", true, true) > 0 then
			return root
		end
	end
	return nil
end

return M
