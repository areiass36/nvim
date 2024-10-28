return {
	"ryanmsnyder/toggleterm-manager.nvim",
	dependencies = {
		"akinsho/nvim-toggleterm.lua",
		"nvim-telescope/telescope.nvim",
		"nvim-lua/plenary.nvim",
	},
	config = function()
		local toggleterm = require("toggleterm");
		toggleterm.setup({
			direction = 'float',
			float_opts = {
				border = 'rounded'
			}
		});

		local telescope = require("telescope");
		telescope.load_extension("toggleterm_manager");
	end
}
