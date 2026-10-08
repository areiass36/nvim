return {
	"aznhe21/actions-preview.nvim",
	dependencies = { "nvim-telescope/telescope.nvim" },
	keys = {
		{
			"ga",
			function()
				require("actions-preview").code_actions()
			end,
			mode = { "n", "v" },
			desc = "Code actions with preview",
		},
	},
	opts = function()
		return { telescope = require("telescope.config") }
	end,
}
