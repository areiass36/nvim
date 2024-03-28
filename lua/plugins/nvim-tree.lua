return {
	"nvim-tree/nvim-tree.lua",
	version = "*",
	lazy = false,
	config = function()
		-- Disable netrw
		vim.g.loaded_netrw = 1
		vim.g.loaded_netrwPlugin = 1

		-- Toggle explorer
		vim.keymap.set("n", "<leader>ee", ":NvimTreeToggle<CR>", { silent = true })
		vim.keymap.set("n", "<leader>ef", ":NvimTreeFindFile<CR>", { silent = true })

		local height = 30
		local width = 120
		local screenH = vim.api.nvim_list_uis()[1].height
		local screenW = vim.api.nvim_list_uis()[1].width


		require("nvim-tree").setup({
			view = {
				float = {
					enable = true,
					open_win_config = {
						relative = "editor",
						width = width,
						height = height,
						row = (screenH - height) * 0.5,
						col = (screenW - width) * 0.5,
					}
				}
			},
			actions = {
				open_file = {
					quit_on_open = true,
				},

			}

		})
	end,
}
