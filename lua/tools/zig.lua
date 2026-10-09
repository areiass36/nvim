-- A C compiler is needed to build treesitter parsers. When none is installed
-- (typical on Windows) a portable zig is downloaded and used as `zig cc`.
local platform = require("core.platform")
local tools = require("tools")
local download = require("tools.download")

local VERSION = "0.17.0"
local TARGETS = {
	windows = { x64 = "x86_64-windows", arm64 = "aarch64-windows" },
	mac = { x64 = "x86_64-macos", arm64 = "aarch64-macos" },
	linux = { x64 = "x86_64-linux", arm64 = "aarch64-linux" },
}

local M = {}

M.dir = tools.tools_dir .. "/zig"
M.path = M.dir .. "/zig" .. platform.exe_suffix

local function activate()
	platform.prepend_path(M.dir)
	-- tree-sitter (and the cc crate behind it) honour CC/CXX, including arguments.
	vim.env.CC = "zig cc"
	vim.env.CXX = "zig c++"
	-- The cc crate appends a Rust-style --target (x86_64-pc-windows-msvc) that
	-- zig cannot parse. CFLAGS/CXXFLAGS land after it on the command line and
	-- the last --target wins, so override it with zig's own target spelling.
	local os_name, arch = platform.detect()
	local target = TARGETS[os_name] and TARGETS[os_name][arch]
	if target then
		local flag = "--target=" .. target .. (os_name == "windows" and "-gnu" or "")
		vim.env.CFLAGS = vim.env.CFLAGS and (vim.env.CFLAGS .. " " .. flag) or flag
		vim.env.CXXFLAGS = vim.env.CXXFLAGS and (vim.env.CXXFLAGS .. " " .. flag) or flag
	end
end

--- Put an already downloaded zig on PATH. Called before plugins load.
function M.setup_path()
	if vim.fn.executable(M.path) == 1 and not platform.has_c_compiler() then
		activate()
	end
end

function M.ensure(on_done)
	on_done = on_done or function() end
	if platform.has_c_compiler() then
		return on_done(true)
	end
	local os_name, arch = platform.detect()
	local target = TARGETS[os_name] and TARGETS[os_name][arch]
	if not target then
		tools.notify(
			"no C compiler and no zig build for "
				.. os_name
				.. "/"
				.. arch
				.. "; treesitter parsers will not be built",
			vim.log.levels.WARN
		)
		return on_done(false)
	end
	local extension = os_name == "windows" and ".zip" or ".tar.xz"
	local url = ("https://ziglang.org/download/%s/zig-%s-%s%s"):format(VERSION, target, VERSION, extension)
	tools.notify("no C compiler found; downloading zig (about 50-90 MB, once) to build treesitter parsers...")
	download.archive("zig " .. VERSION, url, M.dir, 1, function(ok)
		if ok then
			activate()
			vim.api.nvim_exec_autocmds("User", { pattern = "ZigReady", modeline = false })
		end
		on_done(ok)
	end)
end

return M
