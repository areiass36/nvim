-- netcoredbg is the .NET debug adapter. It is downloaded from GitHub instead of
-- Mason because Mason ships an x86_64 build for Apple Silicon, which cannot
-- debug arm64 processes.
local platform = require("core.platform")
local tools = require("tools")
local download = require("tools.download")

local VERSION = "3.2.0-1092"
local ASSETS = {
	windows = { x64 = "netcoredbg-win64.zip" },
	mac = { arm64 = "netcoredbg-osx-arm64.zip" },
	linux = { x64 = "netcoredbg-linux-amd64.tar.gz", arm64 = "netcoredbg-linux-arm64.tar.gz" },
}
-- 3.2.0 has no Intel macOS build; fall back to the last release that had one.
local FALLBACK = { mac = { x64 = { version = "3.1.3-1062", asset = "netcoredbg-osx-amd64.tar.gz" } } }

local M = {}

-- Every archive has a "netcoredbg/" root folder.
M.path = tools.tools_dir .. "/netcoredbg/netcoredbg" .. platform.exe_suffix

function M.ensure(on_done)
	on_done = on_done or function() end
	if vim.fn.executable(M.path) == 1 then
		return on_done(true)
	end

	local os_name, arch = platform.detect()
	local version = VERSION
	local asset = ASSETS[os_name] and ASSETS[os_name][arch]
	local fallback = FALLBACK[os_name] and FALLBACK[os_name][arch]
	if not asset and fallback then
		version, asset = fallback.version, fallback.asset
	end
	if not asset then
		tools.notify(("no netcoredbg build for %s/%s"):format(os_name, arch), vim.log.levels.WARN)
		return on_done(false)
	end

	local url = ("https://github.com/Samsung/netcoredbg/releases/download/%s/%s"):format(version, asset)
	download.archive("netcoredbg " .. version, url, tools.tools_dir, 0, on_done)
end

return M
