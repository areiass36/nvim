return {
	"ryanmsnyder/toggleterm-manager.nvim",
	dependencies = {
		"akinsho/nvim-toggleterm.lua",
		"nvim-telescope/telescope.nvim",
		"nvim-lua/plenary.nvim",
	},
	config = function()
		local manager = require('toggleterm-manager');
		manager.setup({
			mappings = Keys_terminal(),
			titles = {
				preview = "Preview",
				prompt = " Terminals",
				results = "Results",
			},
			results = {
				fields = {
					"state",
					"space",
					"term_icon",
					"term_name",
				},
				separator = " ",
				term_icon = "",
			},
			search = {
				field =
				"term_name"
			},
			sort = {
				field = "term_name",
				ascending = true,
			},
		});
	end,
}
