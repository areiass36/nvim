return {
	"areiass36/toggleterm-manager.nvim",
	dependencies = {
		{
			"akinsho/toggleterm.nvim",
			opts = {
				direction = "float",
				float_opts = {
					border = "none",
					width = function()
						return vim.o.columns
					end,
					height = function()
						return vim.o.lines - 2
					end,
				},
			},
		},
		"nvim-telescope/telescope.nvim",
		"nvim-lua/plenary.nvim",
	},
	config = function()
		local manager = require("toggleterm-manager")
		local actions = manager.actions

		manager.setup({
			mappings = {
				n = {
					["<CR>"] = { action = actions.open_term, exit_on_action = true },
					["r"] = { action = actions.rename_term, exit_on_action = false },
					["d"] = { action = actions.delete_term, exit_on_action = false },
					["c"] = { action = actions.create_and_name_term, exit_on_action = false },
				},
			},
			term_icon = require("core.icons").terminal,
			results = { fields = { "term_icon", "term_name" } },
		})

		vim.keymap.set(
			"n",
			"<leader>t",
			"<cmd>Telescope toggleterm_manager<CR>",
			{ noremap = true, silent = true }
		)
	end,
}
