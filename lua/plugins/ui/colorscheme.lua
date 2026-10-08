return {
	"Mofiqul/vscode.nvim",
	name = "vscode",
	priority = 1000,
	config = function()
		local black = "#000000"
		require("vscode").setup({
			color_overrides = {
				vscBack = black,
				vscTabCurrent = black,
				vscPopupBack = black,
			},
			-- Everything stays pure black; the rounded 'winborder' separates floating windows.
			group_overrides = {
				NormalFloat = { bg = black, fg = "#d4d4d4" },
				FloatBorder = { bg = black, fg = "#5f5f5f" },
				FloatTitle = { bg = black, fg = "#9cdcfe", bold = true },
				Pmenu = { bg = black, fg = "#d4d4d4" },
				PmenuSel = { bg = "#264f78", fg = "#ffffff" },
			},
		})
		vim.cmd.colorscheme("vscode")
	end,
}
