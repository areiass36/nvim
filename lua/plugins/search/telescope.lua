return {
	'nvim-telescope/telescope.nvim',
	tag = '0.1.6',
	lazy = false,
	dependencies = {
		"nvim-lua/plenary.nvim",
		"nvim-telescope/telescope-live-grep-args.nvim",
		"gbrlsnchs/telescope-lsp-handlers.nvim",
		"nvim-tree/nvim-web-devicons",
		{ 'nvim-telescope/telescope-fzf-native.nvim', build = 'make' },
	},
	config = function()
		local telescope = require('telescope')

		telescope.setup({
			extensions = {
				fzf = {
					fuzzy = true,
					override_generic_sorter = true,
					override_file_sorter = true,
					case_mode = "smart_case",
				},
				{
					lsp_handlers = {
						code_action = {
							telescope = require('telescope.themes').get_dropdown({})
						}
					}
				}
			},
			defaults = {
				file_ignore_patterns = {
					"node_modules",
					"bin",
					"obj",
					".git"
				}
			}
		})


		telescope.load_extension('live_grep_args')
		telescope.load_extension('fzf')
		telescope.load_extension('lsp_handlers');
	end
}
