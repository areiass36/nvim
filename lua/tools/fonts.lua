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

--- Copy `source` into the user font directory and register it.
--- @param display_name string font name as shown to applications
--- @return boolean ok
function M.install(source, display_name)
	local dir = M.user_font_dir()
	vim.fn.mkdir(dir, "p")
	local target = dir .. "/" .. vim.fn.fnamemodify(source, ":t")
	if not vim.uv.fs_copyfile(source, target) then
		tools.notify("could not copy " .. source .. " into " .. dir, vim.log.levels.WARN)
		return false
	end
	if platform.is_windows then
		register_on_windows(target, display_name)
	elseif platform.detect() == "linux" and vim.fn.executable("fc-cache") == 1 then
		vim.system({ "fc-cache", "-f" })
	end
	return true
end

return M
