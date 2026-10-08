-- External binaries the config installs by itself, so a fresh machine only
-- needs Neovim and git (plus the toolchains of the languages you use).
--
--   ripgrep            -> GitHub release into stdpath("data")/bin
--   netcoredbg         -> GitHub release into stdpath("data")/tools/netcoredbg
--   roslyn, ilspycmd   -> `dotnet tool install` into stdpath("data")/tools/<name>
--   ConfigIcons.ttf    -> copied from assets/fonts into the user font directory
--   JetBrainsMono NFM  -> nerd-fonts release, when the terminal font is missing
--   zig                -> portable C compiler for treesitter when none is installed
--   language servers, debugpy, js-debug, tree-sitter-cli -> Mason
local platform = require("core.platform")

local M = {}

local data = vim.fn.stdpath("data")
M.bin_dir = data .. "/bin"
M.tools_dir = data .. "/tools"
M.mason_root = data .. "/mason"

function M.notify(message, level)
	vim.schedule(function()
		vim.notify("[tools] " .. message, level or vim.log.levels.INFO)
	end)
end

--- Create the download directories and put bin_dir first in PATH.
function M.setup_path()
	vim.fn.mkdir(M.bin_dir, "p")
	vim.fn.mkdir(M.tools_dir, "p")
	platform.prepend_path(M.bin_dir)
	require("tools.zig").setup_path()
end

--- Install directory of a Mason package.
function M.mason_package(name)
	return M.mason_root .. "/packages/" .. name
end

--- Everything that does not come from Mason. Runs once per startup.
function M.ensure_all()
	require("tools.ripgrep").ensure()
	require("tools.netcoredbg").ensure()
	require("tools.zig").ensure()
	require("tools.nerd_font").ensure()
	require("tools.icon_font").ensure()
end

return M
