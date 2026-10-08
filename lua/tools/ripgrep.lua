-- ripgrep powers Telescope's live grep.
local platform = require("core.platform")
local tools = require("tools")
local download = require("tools.download")

local VERSION = "14.1.1"
local ASSETS = {
	windows = { x64 = "x86_64-pc-windows-msvc.zip", arm64 = "aarch64-pc-windows-msvc.zip" },
	mac = { x64 = "x86_64-apple-darwin.tar.gz", arm64 = "aarch64-apple-darwin.tar.gz" },
	linux = { x64 = "x86_64-unknown-linux-musl.tar.gz", arm64 = "aarch64-unknown-linux-gnu.tar.gz" },
}

local M = {}

M.path = tools.bin_dir .. "/rg" .. platform.exe_suffix

function M.ensure(on_done)
	on_done = on_done or function() end
	if vim.fn.executable("rg") == 1 then
		return on_done(true)
	end

	local os_name, arch = platform.detect()
	local asset = ASSETS[os_name] and ASSETS[os_name][arch]
	if not asset then
		tools.notify(
			("no ripgrep build for %s/%s; install rg manually"):format(os_name, arch),
			vim.log.levels.WARN
		)
		return on_done(false)
	end

	local url = ("https://github.com/BurntSushi/ripgrep/releases/download/%s/ripgrep-%s-%s"):format(
		VERSION,
		VERSION,
		asset
	)
	-- The archive has one root folder (ripgrep-<version>-<target>/rg).
	download.archive("ripgrep", url, tools.bin_dir, 1, on_done)
end

return M
