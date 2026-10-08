-- Install assets/fonts/ConfigIcons.ttf into the user's font directory so the
-- terminal can render the config's icons (see core/icons.lua). Terminals do
-- not fall back to arbitrary fonts for private-use code points, so they must
-- be told to use it for U+F600-U+F6FF; for iTerm2 this module writes a
-- Dynamic Profile with that rule (see README "Icon font" for the others).
local platform = require("core.platform")
local tools = require("tools")
local fonts = require("tools.fonts")

local M = {}

local FONT_FILE = "ConfigIcons.ttf"
local FONT_NAME = "ConfigIcons"
local ITERM_PROFILES_DIR = vim.env.HOME .. "/Library/Application Support/iTerm2/DynamicProfiles"

M.source = vim.fn.stdpath("config") .. "/assets/fonts/" .. FONT_FILE
M.target = fonts.user_font_dir() .. "/" .. FONT_FILE

local function is_installed()
	local source, target = vim.uv.fs_stat(M.source), vim.uv.fs_stat(M.target)
	return source and target and source.size == target.size and source.mtime.sec <= target.mtime.sec
end

-- ---------------------------------------------------------------- iTerm2
--- Name and font of the default iTerm2 profile (read with the system Python,
--- since the preferences plist contains binary data plutil cannot turn into JSON).
local function iterm2_default_profile()
	local script = table.concat({
		"import json, plistlib, os",
		"p = plistlib.load(open(os.path.expanduser('~/Library/Preferences/com.googlecode.iterm2.plist'), 'rb'))",
		"g = p.get('Default Bookmark Guid')",
		"b = [x for x in p.get('New Bookmarks', []) if x.get('Guid') == g]",
		"print(json.dumps({'name': b[0].get('Name'), 'font': b[0].get('Normal Font')} if b else None))",
	}, "\n")
	local result = vim.system({ "python3", "-c", script }, { text = true }):wait()
	local ok, profile = pcall(vim.json.decode, result.code == 0 and result.stdout or "null")
	return ok and type(profile) == "table" and profile or nil
end

local function icon_range()
	local first, count = math.huge, 0
	for _, glyph in pairs(require("core.icons")) do
		first = math.min(first, vim.fn.char2nr(glyph))
		count = count + 1
	end
	return first, count
end

--- Write a Dynamic Profile that inherits the default profile and maps the icon
--- range to the icon font. Special exceptions only apply with the non-ASCII font
--- enabled, so it is set to the same font: accents and box drawing keep working.
function M.write_iterm2_profile()
	if platform.detect() ~= "mac" or vim.fn.isdirectory(ITERM_PROFILES_DIR) == 0 then
		return
	end
	local parent = iterm2_default_profile()
	if not parent or not parent.name then
		return
	end
	local first, count = icon_range()
	local profile = {
		Name = FONT_NAME,
		Guid = "nvim-config-icons",
		["Dynamic Profile Parent Name"] = parent.name,
		["Use Non-ASCII Font"] = true,
		["Non Ascii Font"] = parent.font,
		["Special Font Config"] = vim.json.encode({
			version = 2,
			entries = { { start = first, count = count, fontName = FONT_NAME } },
		}),
	}
	local target = ITERM_PROFILES_DIR .. "/" .. FONT_NAME .. ".json"
	local current = nil
	if vim.fn.filereadable(target) == 1 then
		local ok, decoded = pcall(vim.json.decode, table.concat(vim.fn.readfile(target), "\n"))
		current = ok and decoded or nil
	end
	local wanted = { Profiles = { profile } }
	if not vim.deep_equal(current, wanted) then
		vim.fn.writefile({ vim.json.encode(wanted) }, target)
		tools.notify(
			('iTerm2 profile "%s" written. Select it in Settings > Profiles, or make it the default.'):format(
				FONT_NAME
			)
		)
	end
end

function M.ensure()
	if vim.fn.filereadable(M.source) == 0 then
		return
	end
	if not is_installed() and fonts.install(M.source, FONT_NAME) then
		tools.notify(FONT_FILE .. " installed in " .. fonts.user_font_dir())
	end
	M.write_iterm2_profile()
	require("tools.windows_terminal").ensure()
end

return M
