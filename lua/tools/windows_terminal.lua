-- Point Windows Terminal at the fonts: "JetBrainsMono NFM, ConfigIcons" as the
-- default font face (the comma list is Windows Terminal's font fallback).
-- settings.json is JSON with comments, so comments are stripped before parsing.
local platform = require("core.platform")
local tools = require("tools")

local M = {}

M.font_face = "JetBrainsMono NFM, ConfigIcons"

local function settings_candidates()
	local local_app_data = vim.env.LOCALAPPDATA or ""
	return {
		local_app_data .. "/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json",
		local_app_data .. "/Packages/Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe/LocalState/settings.json",
		local_app_data .. "/Microsoft/Windows Terminal/settings.json",
	}
end

function M.settings_path()
	for _, path in ipairs(settings_candidates()) do
		if vim.fn.filereadable(path) == 1 then
			return path
		end
	end
	return nil
end

--- Remove // and /* */ comments and trailing commas from JSONC.
function M.strip_jsonc(text)
	local out, i, n = {}, 1, #text
	local in_string = false
	while i <= n do
		local c = text:sub(i, i)
		if in_string then
			out[#out + 1] = c
			if c == "\\" then
				out[#out + 1] = text:sub(i + 1, i + 1)
				i = i + 1
			elseif c == '"' then
				in_string = false
			end
		elseif c == '"' then
			in_string = true
			out[#out + 1] = c
		elseif text:sub(i, i + 1) == "//" then
			i = (text:find("\n", i, true) or n + 1) - 1
		elseif text:sub(i, i + 1) == "/*" then
			i = (text:find("*/", i, true) or n - 1) + 1
		else
			out[#out + 1] = c
		end
		i = i + 1
	end
	return (table.concat(out):gsub(",(%s*[}%]])", "%1"))
end

--- Returns the updated settings table, or nil when nothing has to change.
function M.with_font_face(settings)
	settings.profiles = settings.profiles or {}
	settings.profiles.defaults = settings.profiles.defaults or {}
	local defaults = settings.profiles.defaults
	defaults.font = type(defaults.font) == "table" and defaults.font or {}
	local face = defaults.font.face
	if
		type(face) == "string"
		and face:find("ConfigIcons", 1, true)
		and face:find("JetBrainsMono", 1, true)
	then
		return nil
	end
	defaults.font.face = M.font_face
	defaults.fontFace = nil -- legacy key would override "font.face"
	return settings
end

function M.update_settings_file(path)
	local text = table.concat(vim.fn.readfile(path), "\n")
	local ok, settings = pcall(vim.json.decode, M.strip_jsonc(text))
	if not ok or type(settings) ~= "table" then
		tools.notify(
			"could not parse " .. path .. '; set the font face to "' .. M.font_face .. '" manually.',
			vim.log.levels.WARN
		)
		return false
	end
	local updated = M.with_font_face(settings)
	if not updated then
		return true
	end
	vim.fn.writefile({ text }, path .. ".before-nvim-config")
	vim.fn.writefile({ vim.json.encode(updated) }, path)
	tools.notify(
		'Windows Terminal font set to "' .. M.font_face .. '" (backup: settings.json.before-nvim-config).'
	)
	return true
end

function M.ensure()
	if not platform.is_windows then
		return
	end
	local path = M.settings_path()
	if not path then
		return tools.notify(
			'Windows Terminal settings not found; set its font to "' .. M.font_face .. '".',
			vim.log.levels.WARN
		)
	end
	M.update_settings_file(path)
end

return M
