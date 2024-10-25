return {
	"nvim-telescope/telescope-file-browser.nvim",
	dependencies = { "nvim-telescope/telescope.nvim", "nvim-lua/plenary.nvim" },
	config = function()
		local telescope = require 'telescope';
		telescope.setup {
			extensions = {
				file_browser = {
				}
			}
		}
		vim.keymap.set("n", "<leader>ee", function()
			require("telescope").extensions.file_browser.file_browser()
		end)

		vim.keymap.set("n", "<leader>ef", function()
			require("telescope").extensions.file_browser.file_browser({ path = '%:p:h', select_buffer = true })
		end)
		telescope.load_extension 'file_browser'
	end
}
