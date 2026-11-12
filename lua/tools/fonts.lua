-- Install font files for the current user. On Windows a font is only visible to
-- applications after it is also registered under HKCU, so that is done too.
local platform = require("core.platform")
local tools = require("tools")

local M = {}

local REGISTRY_KEY = [[HKCU\Software\Microsoft\Windows NT\CurrentVersion\Fonts]]

function M.user_font_dir()
	if platform.is_windows then
		return vim.env.LOCALAPPDATA .. "/Microsoft/Windows/Fonts"
	end
	if platform.detect() == "mac" then
		return vim.env.HOME .. "/Library/Fonts"
	end
	return (vim.env.XDG_DATA_HOME or (vim.env.HOME .. "/.local/share")) .. "/fonts"
end

--- Directories a font may already live in (user and system).
local function search_dirs()
	local dirs = { M.user_font_dir() }
	if platform.is_windows then
		dirs[#dirs + 1] = (vim.env.WINDIR or "C:/Windows") .. "/Fonts"
	elseif platform.detect() == "mac" then
		dirs[#dirs + 1] = "/Library/Fonts"
	else
		dirs[#dirs + 1] = "/usr/share/fonts"
		dirs[#dirs + 1] = "/usr/local/share/fonts"
	end
	return dirs
end

--- Is a font file with this name installed anywhere (user or system)?
function M.is_installed(file_name)
	for _, dir in ipairs(search_dirs()) do
		if #vim.fn.glob(dir .. "/**/" .. file_name, true, true) > 0 then
			return true
		end
	end
	return false
end

local function register_on_windows(target, display_name)
	vim.system({
		"reg",
		"add",
		REGISTRY_KEY,
		"/v",
		display_name .. " (TrueType)",
		"/t",
		"REG_SZ",
		"/d",
		target:gsub("/", "\\"),
		"/f",
	}, {}, function(result)
		if result.code ~= 0 then
			tools.notify(
				"could not register font " .. display_name .. " in the Windows registry",
				vim.log.levels.WARN
			)
		end
	end)
end

--- A short tag for a file's contents, so an installed name changes when the
--- font behind it does.
local function content_tag(path)
	local fd = vim.uv.fs_open(path, "r", 438)
	if not fd then
		return nil
	end
	local stat = vim.uv.fs_fstat(fd)
	local data = stat and vim.uv.fs_read(fd, stat.size, 0) or nil
	vim.uv.fs_close(fd)
	return data and vim.fn.sha256(data):sub(1, 8) or nil
end

--- Where `source` is, or would be, installed.
---
--- On Windows the name carries that tag, because an installed font cannot be
--- overwritten while anything is rendering with it -- and the terminal running
--- nvim is exactly that, so the plain name is locked from the moment the font
--- is first used. Rebuilding the font would then warn on every startup and
--- never take effect, with no way out that does not involve closing the
--- terminal nvim is running in. A new name sidesteps the lock: the registry
--- keeps one entry for the family, pointing at whichever file is current.
function M.installed_path(source)
	local dir = M.user_font_dir()
	local tag = platform.is_windows and content_tag(source) or nil
	if not tag then
		return dir .. "/" .. vim.fn.fnamemodify(source, ":t")
	end
	return ("%s/%s-%s.%s"):format(
		dir,
		vim.fn.fnamemodify(source, ":t:r"),
		tag,
		vim.fn.fnamemodify(source, ":e")
	)
end

--- Delete what earlier versions of this font were installed as. One that is
--- still being rendered with cannot be deleted; it is left where it is and
--- tried again next time.
local function prune(source, keep)
	local pattern = ("%s/%s*.%s"):format(
		M.user_font_dir(),
		vim.fn.fnamemodify(source, ":t:r"),
		vim.fn.fnamemodify(source, ":e")
	)
	for _, path in ipairs(vim.fn.glob(pattern, true, true)) do
		if vim.fs.normalize(path) ~= vim.fs.normalize(keep) then
			pcall(vim.fn.delete, path)
		end
	end
end

--- Copy `source` into the user font directory and register it.
--- @param display_name string font name as shown to applications
--- @return boolean ok
function M.install(source, display_name)
	local dir = M.user_font_dir()
	vim.fn.mkdir(dir, "p")
	local target = M.installed_path(source)
	if not vim.uv.fs_copyfile(source, target) then
		tools.notify("could not copy " .. source .. " into " .. dir, vim.log.levels.WARN)
		return false
	end
	if platform.is_windows then
		register_on_windows(target, display_name)
		prune(source, target)
	elseif platform.detect() == "linux" and vim.fn.executable("fc-cache") == 1 then
		vim.system({ "fc-cache", "-f" })
	end
	return true
end

return M
