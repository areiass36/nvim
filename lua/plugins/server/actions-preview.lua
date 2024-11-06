return {
	"aznhe21/actions-preview.nvim",
	dependencies =
	{
		'nvim-telescope/telescope.nvim',
	},
	config = function()
		local actions = require("actions-preview");
		actions.setup({
			telescope = require('telescope.config')
		});
	end
}
