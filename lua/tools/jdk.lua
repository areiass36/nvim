-- A JVM that belongs to this config and to nothing else.
--
-- The database client runs on Java (lua/db/jvm.lua). Using whatever `java`
-- happens to be on PATH would make the feature depend on the user's toolchain
-- -- a version manager with no version selected, a JRE without javac, a JDK 8
-- from years ago -- so a Temurin JDK is downloaded into stdpath("data") and
-- that one is used, always.
local platform = require("core.platform")
local tools = require("tools")
local download = require("tools.download")

local VERSION = "21"
-- Temurin publishes every combination this config supports.
local TARGETS = {
	mac = { arm64 = "mac/aarch64", x64 = "mac/x64" },
	linux = { arm64 = "linux/aarch64", x64 = "linux/x64" },
	windows = { arm64 = "windows/aarch64", x64 = "windows/x64" },
}

local M = {}

M.dir = tools.tools_dir .. "/jdk"

--- The layout differs: macOS nests the runtime under Contents/Home.
--- @return string|nil
local function find_executable(name)
	local candidates = {
		("%s/bin/%s%s"):format(M.dir, name, platform.exe_suffix),
		("%s/Contents/Home/bin/%s%s"):format(M.dir, name, platform.exe_suffix),
	}
	for _, path in ipairs(candidates) do
		if vim.fn.executable(path) == 1 then
			return path
		end
	end
	return nil
end

--- @return string|nil path to java
function M.java()
	return find_executable("java")
end

--- @return string|nil path to javac, needed once to build the query runner
function M.javac()
	return find_executable("javac")
end

function M.installed()
	return M.java() ~= nil
end

--- @param on_done fun(ok: boolean)
function M.ensure(on_done)
	on_done = on_done or function() end
	if M.installed() then
		return on_done(true)
	end

	local os_name, arch = platform.detect()
	local target = TARGETS[os_name] and TARGETS[os_name][arch]
	if not target then
		tools.notify(("no Temurin JDK for %s/%s"):format(os_name, arch), vim.log.levels.WARN)
		return on_done(false)
	end

	-- The API redirects to the current build for this platform, so the
	-- version does not have to be pinned by hand on every bump.
	local url = ("https://api.adoptium.net/v3/binary/latest/%s/ga/%s/jdk/hotspot/normal/eclipse"):format(
		VERSION,
		target
	)
	tools.notify("downloading a JDK for the database client (about 190 MB, once)")
	-- The archive has a single jdk-<version> directory at its root.
	download.archive("jdk " .. VERSION, url, M.dir, 1, function(ok)
		if ok and not M.installed() then
			tools.notify("the JDK archive extracted but no java was found in it", vim.log.levels.ERROR)
			return on_done(false)
		end
		on_done(ok)
	end)
end

return M
