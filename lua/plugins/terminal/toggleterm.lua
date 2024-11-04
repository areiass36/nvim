return {
	"akinsho/toggleterm.nvim",
	config = function()
		local toggleterm = require("toggleterm");
		toggleterm.setup({
			direction = 'float',
			float_opts = {
				border = 'none',
				width = function()
					return vim.o.columns
				end,
				height = function()
					return vim.o.lines - 2
				end
			}
		});
	end
}
