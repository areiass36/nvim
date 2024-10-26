return {
	"nvim-telescope/telescope-file-browser.nvim",
	dependencies = {
		"nvim-telescope/telescope.nvim",
		"nvim-lua/plenary.nvim"
	},
	config = function()
		local telescope = require('telescope');

		telescope.setup({
			extensions = {
				file_browser = {
				}
			}
		});

		telescope.load_extension('file_browser');
	end
}
