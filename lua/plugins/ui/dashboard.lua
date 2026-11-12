-- Start screen. The logo is drawn in solid blocks rather than the outlined
-- figlet style this used before: the outline mixes box-drawing characters with
-- full blocks, which the terminal draws at two different weights, and every
-- line carried trailing spaces, which pushed the art left of everything below
-- it -- alpha centres on the longest line, spaces included.
local HEADER = {
	[[███    ██ ███████  ██████  ██    ██ ██ ███    ███]],
	[[████   ██ ██      ██    ██ ██    ██ ██ ████  ████]],
	[[██ ██  ██ █████   ██    ██ ██    ██ ██ ██ ████ ██]],
	[[██  ██ ██ ██      ██    ██  ██  ██  ██ ██  ██  ██]],
	[[██   ████ ███████  ██████    ████   ██ ██      ██]],
}

-- One colour per header line: the logo fades from the blue of the colorscheme
-- into its teal, both of which hold up against the pure black background.
local GRADIENT = { "#4fc1ff", "#4fc3eb", "#4ec5d8", "#4ec7c4", "#4ec9b0" }
local DIVIDER = "#3c3c3c"

-- Wide enough for the longest label and its shortcut, narrow enough that the
-- two columns still read as one block instead of two distant ones.
local WIDTH = 26

-- Rows the layout occupies: the five header lines, the subtitle, nine button
-- rows (the divider counts as one) and the footer, plus the padding between
-- them. Only used to centre the whole thing vertically.
local HEIGHT = 21

local icons = require("core.icons")

-- The branch comes out of .git/HEAD instead of asking git for it: 'shell' is
-- PowerShell on Windows (core.options), and spawning it once per draw would
-- cost more than everything else the start screen does put together.
local function git_branch()
	local git = vim.fs.find(".git", { upward = true, path = vim.uv.cwd() })[1]
	if not git then
		return nil
	end
	-- In a worktree or a submodule .git is a file pointing elsewhere, with no
	-- HEAD beside it; the subtitle then just has no branch in it.
	local ok, head = pcall(vim.fn.readfile, vim.fs.joinpath(git, "HEAD"), "", 1)
	if not ok or not head[1] then
		return nil
	end
	-- "ref: refs/heads/master" on a branch, a bare commit when detached.
	return head[1]:match("^ref: refs/heads/(.+)$") or head[1]:sub(1, 7)
end

local function subtitle()
	local version = vim.version()
	local parts = { icons.folder .. " " .. vim.fn.fnamemodify(vim.uv.cwd(), ":t") }
	local branch = git_branch()
	if branch then
		parts[#parts + 1] = icons.branch .. " " .. branch
	end
	parts[#parts + 1] = ("v%d.%d.%d"):format(version.major, version.minor, version.patch)
	return table.concat(parts, "  ·  ")
end

return {
	"goolord/alpha-nvim",
	dependencies = { "nvim-tree/nvim-web-devicons" },
	config = function()
		local alpha = require("alpha")
		local dashboard = require("alpha.themes.dashboard")

		-- A table of highlights is one entry per line, each a list of
		-- { group, first column, last column }; -1 reaches the end of the line.
		local header_hl = {}
		for i, color in ipairs(GRADIENT) do
			local group = ("AlphaHeader%d"):format(i)
			vim.api.nvim_set_hl(0, group, { fg = color })
			header_hl[i] = { { group, 0, -1 } }
		end
		vim.api.nvim_set_hl(0, "AlphaDivider", { fg = DIVIDER })

		dashboard.section.header.val = HEADER
		dashboard.section.header.opts.hl = header_hl

		local function button(shortcut, icon, text, command)
			local item = dashboard.button(shortcut, icon .. "  " .. text, command)
			item.opts.hl = "Normal"
			item.opts.hl_shortcut = "Keyword"
			item.opts.width = WIDTH
			return item
		end

		dashboard.section.buttons.val = {
			button(",ff", icons.find_file, "Find file", "<cmd>Telescope find_files<CR>"),
			button(
				",fg",
				icons.live_grep,
				"Live grep",
				"<cmd>lua require('telescope').extensions.live_grep_args.live_grep_args()<CR>"
			),
			button(",fr", icons.recent_files, "Recent files", "<cmd>Telescope oldfiles<CR>"),
			button(
				",ee",
				icons.browse,
				"Browse files",
				"<cmd>lua require('telescope').extensions.file_browser.file_browser()<CR>"
			),
			-- Above the divider is the project, below it the config itself.
			{
				type = "text",
				val = { ("─"):rep(WIDTH) },
				opts = { position = "center", hl = "AlphaDivider" },
			},
			button(
				"c",
				icons.settings,
				"Neovim config",
				"<cmd>cd " .. vim.fn.stdpath("config") .. " | Telescope find_files<CR>"
			),
			button("m", icons.mason, "Mason", "<cmd>Mason<CR>"),
			button("l", icons.lazy, "Lazy", "<cmd>Lazy<CR>"),
			button("q", icons.quit, "Quit", "<cmd>qa<CR>"),
		}
		dashboard.section.buttons.opts.spacing = 0
		dashboard.section.footer.opts.hl = "Comment"

		dashboard.config.layout = {
			-- Functions instead of fixed values: alpha redraws on resize and
			-- asks again, so the screen stays centred and the subtitle keeps up
			-- with the directory. vim.o.lines counts the status and command
			-- lines, which the alpha window does not get.
			{
				type = "padding",
				val = function()
					return math.max(1, math.floor((vim.o.lines - 2 - HEIGHT) / 2))
				end,
			},
			dashboard.section.header,
			{ type = "padding", val = 1 },
			{
				type = "text",
				val = function()
					return { subtitle() }
				end,
				opts = { position = "center", hl = "Comment" },
			},
			{ type = "padding", val = 2 },
			dashboard.section.buttons,
			{ type = "padding", val = 1 },
			dashboard.section.footer,
		}
		alpha.setup(dashboard.config)

		-- Footer with lazy.nvim stats, available only after every plugin loaded.
		vim.api.nvim_create_autocmd("User", {
			pattern = "LazyVimStarted",
			callback = function()
				local stats = require("lazy").stats()
				local millis = math.floor(stats.startuptime + 0.5)
				dashboard.section.footer.val = (icons.bolt .. "  %d plugins loaded in %d ms"):format(
					stats.loaded,
					millis
				)
				pcall(vim.cmd.AlphaRedraw)
			end,
		})
	end,
}
