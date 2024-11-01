return {
	"areiass36/toggleterm-manager.nvim",
	dependencies = {
		"akinsho/nvim-toggleterm.lua",
		"nvim-telescope/telescope.nvim",
		"nvim-lua/plenary.nvim",
	},
	config = function()
		local manager = require("toggleterm-manager");
		manager.setup({
			mappings = Keys_terminal(),
		});
	end
}
