return {
	'nvim-telescope/telescope.nvim',
	tag = '0.1.6',
	lazy = false,
	dependencies = {
		'nvim-lua/plenary.nvim',
		"nvim-telescope/telescope-live-grep-args.nvim"
	},
	config = function()
		-- Telescope keys
		local telescope = require('telescope')

		telescope.setup({
			defaults = {
				file_ignore_patterns = {
					"node_modules",
					".git"
				}
			}
		})
		-- Adds live grep plugin
		telescope.load_extension('live_grep_args')

		telescope.load_extension 'workspaces'
		local builtin = require('telescope.builtin')
		vim.keymap.set('n', '<leader>ff', builtin.find_files, {})
		vim.keymap.set('n', '<leader>fg',
			":lua require('telescope').extensions.live_grep_args.live_grep_args()<CR>", {})
		vim.keymap.set('n', '<leader>fb', builtin.buffers, {})
		vim.keymap.set('n', '<leader>fh', builtin.help_tags, {})
	end
}
