local HEADER = {
	[[                                                                       ]],
	[[  ███╗   ██╗ ███████╗  ██████╗  ██╗   ██╗ ██╗ ███╗   ███╗             ]],
	[[  ████╗  ██║ ██╔════╝ ██╔═══██╗ ██║   ██║ ██║ ████╗ ████║             ]],
	[[  ██╔██╗ ██║ █████╗   ██║   ██║ ██║   ██║ ██║ ██╔████╔██║             ]],
	[[  ██║╚██╗██║ ██╔══╝   ██║   ██║ ╚██╗ ██╔╝ ██║ ██║╚██╔╝██║             ]],
	[[  ██║ ╚████║ ███████╗ ╚██████╔╝  ╚████╔╝  ██║ ██║ ╚═╝ ██║             ]],
	[[  ╚═╝  ╚═══╝ ╚══════╝  ╚═════╝    ╚═══╝   ╚═╝ ╚═╝     ╚═╝             ]],
	[[                                                                       ]],
}

return {
	"goolord/alpha-nvim",
	dependencies = { "nvim-tree/nvim-web-devicons" },
	config = function()
		local icons = require("core.icons")
		local alpha = require("alpha")
		local dashboard = require("alpha.themes.dashboard")

		dashboard.section.header.val = HEADER
		dashboard.section.header.opts.hl = "Function"

		local function button(shortcut, icon, text, command)
			local item = dashboard.button(shortcut, icon .. "  " .. text, command)
			item.opts.hl = "Normal"
			item.opts.hl_shortcut = "Keyword"
			item.opts.width = 44
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
			{ type = "padding", val = 6 },
			dashboard.section.header,
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
