-- JetBrainsMono Nerd Font Mono: the terminal font this config is designed for
-- (powerline separators, box drawing). Downloaded from the nerd-fonts release
-- when it is not installed; only the four Mono faces are extracted.
local tools = require("tools")
local download = require("tools.download")
local fonts = require("tools.fonts")

local VERSION = "v3.5.1"
local URL = ("https://github.com/ryanoasis/nerd-fonts/releases/download/%s/JetBrainsMono.zip"):format(VERSION)
local FILES = {
	"JetBrainsMonoNerdFontMono-Regular.ttf",
	"JetBrainsMonoNerdFontMono-Bold.ttf",
	"JetBrainsMonoNerdFontMono-Italic.ttf",
	"JetBrainsMonoNerdFontMono-BoldItalic.ttf",
}

local M = {}

M.family = "JetBrainsMono NFM"

function M.is_installed()
	return fonts.is_installed(FILES[1])
end

function M.ensure(on_done)
	on_done = on_done or function() end
	if M.is_installed() then
		return on_done(true)
	end
	local staging = tools.tools_dir .. "/.nerd-font"
	tools.notify("JetBrainsMono Nerd Font is not installed; downloading it (about 130 MB, once)...")
	download.archive("JetBrainsMono Nerd Font", URL, staging, 0, function(ok)
		if not ok then
			return on_done(false)
		end
		for _, file in ipairs(FILES) do
			fonts.install(staging .. "/" .. file, vim.fn.fnamemodify(file, ":r"))
		end
		vim.fn.delete(staging, "rf")
		tools.notify("JetBrainsMono Nerd Font installed. Restart the terminal if it does not pick it up.")
		on_done(true)
	end, FILES)
end

return M
