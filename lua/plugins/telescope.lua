return {
	'nvim-telescope/telescope.nvim',
	tag = '0.1.6',
	lazy = false,
	dependencies = {
		'nvim-lua/plenary.nvim',
		"nvim-telescope/telescope-live-grep-args.nvim",
		{ 'nvim-telescope/telescope-fzf-native.nvim', build = 'make' }
	},
	config = function()
		-- Telescope keys
		local telescope = require('telescope')

		telescope.setup({
			extensions = {
				fzf = {
					fuzzy = true, -- false will only do exact matching
					override_generic_sorter = true, -- override the generic sorter
					override_file_sorter = true, -- override the file sorter
					case_mode = "smart_case", -- or "ignore_case" or "respect_case"
					-- the default case_mode is "smart_case"
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
		-- Adds live grep plugin
		telescope.load_extension('live_grep_args')
		telescope.load_extension('fzf')

		local builtin = require('telescope.builtin')
		vim.keymap.set('n', '<leader>ff', builtin.find_files, {})
		vim.keymap.set('n', '<leader>fg',
			":lua require('telescope').extensions.live_grep_args.live_grep_args()<CR>", {})
		vim.keymap.set('n', '<leader>fb', builtin.buffers, {})
		vim.keymap.set('n', '<leader>fh', builtin.help_tags, {})
	end
}
