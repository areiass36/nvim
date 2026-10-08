return {
	"nvim-telescope/telescope.nvim",
	tag = "v0.2.2",
	lazy = false,
	dependencies = {
		"nvim-lua/plenary.nvim",
		"nvim-telescope/telescope-live-grep-args.nvim",
		"nvim-telescope/telescope-file-browser.nvim",
		"areiass36/telepoon.nvim",
		"nvim-tree/nvim-web-devicons",
		-- Native sorter with prebuilt binaries for mac/linux/windows: nothing to compile.
		"natecraddock/telescope-zf-native.nvim",
		-- vim.ui.select (DAP menus, code actions, ...) becomes a Telescope picker.
		"nvim-telescope/telescope-ui-select.nvim",
	},
	config = function()
		local telescope = require("telescope")

		telescope.setup({
			defaults = {
				layout_strategy = "horizontal",
				layout_config = {
					width = function()
						return vim.o.columns
					end,
					height = function()
						return vim.o.lines
					end,
					-- preview_width is only valid for the horizontal strategy; at the top
					-- level it breaks pickers that use another one (e.g. the ui-select dropdown).
					horizontal = {
						preview_width = function()
							return math.floor(vim.o.columns / 2)
						end,
					},
				},
				file_ignore_patterns = { "node_modules", "bin", "obj", ".git" },
			},
			extensions = {
				file_browser = { dir_icon = require("core.icons").folder },
				["ui-select"] = {
					require("telescope.themes").get_dropdown({
						layout_config = { width = 0.7, height = 0.45 },
						previewer = false,
					}),
				},
				["zf-native"] = {
					file = { enable = true, highlight_results = true, match_filename = true },
					generic = { enable = true, highlight_results = true, match_filename = false },
				},
			},
		})

		for _, extension in ipairs({ "live_grep_args", "zf-native", "ui-select", "telepoon", "file_browser" }) do
			telescope.load_extension(extension)
		end

		local builtin = require("telescope.builtin")
		local extensions = telescope.extensions
		local map = function(lhs, rhs)
			vim.keymap.set("n", lhs, rhs, { noremap = true, silent = true })
		end
		map("<leader>ff", builtin.find_files)
		map("<leader>fg", extensions.live_grep_args.live_grep_args)
		map("<leader>fb", builtin.buffers)
		map("<leader>fr", builtin.oldfiles)
		map("<leader>es", extensions.telepoon.telepoon)
		map("<leader>ee", extensions.file_browser.file_browser)
		map("<leader>ef", function()
			extensions.file_browser.file_browser({ path = "%:p:h", select_buffer = true })
		end)
	end,
}
