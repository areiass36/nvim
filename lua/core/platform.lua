-- Facts about the operating system, shared by every module that touches paths
-- or external processes.
local M = {}

M.is_windows = vim.fn.has("win32") == 1
M.exe_suffix = M.is_windows and ".exe" or ""
M.path_separator = M.is_windows and ";" or ":"
M.null_device = M.is_windows and "NUL" or "/dev/null"

--- @return string os_name "windows" | "mac" | "linux" | raw sysname
--- @return string arch "x64" | "arm64" | raw machine name
function M.detect()
	local uname = vim.uv.os_uname()
	local is_arm = uname.machine == "arm64" or uname.machine == "aarch64"
	local arch = is_arm and "arm64" or "x64"
	if M.is_windows then
		return "windows", arch
	elseif uname.sysname == "Darwin" then
		return "mac", arch
	elseif uname.sysname == "Linux" then
		return "linux", arch
	end
	return uname.sysname, uname.machine
end

--- A C compiler is only needed to build treesitter parsers.
function M.has_c_compiler()
	for _, compiler in ipairs({ "cc", "gcc", "clang", "zig", "cl" }) do
		if vim.fn.executable(compiler) == 1 then
			return true
		end
	end
	return false
end

--- Prepend a directory to PATH once.
function M.prepend_path(dir)
	if not vim.env.PATH:find(dir, 1, true) then
		vim.env.PATH = dir .. M.path_separator .. vim.env.PATH
	end
end

return M
