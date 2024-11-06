return {
	"akinsho/toggleterm.nvim",
	config = function()
		local toggleterm = require("toggleterm");
		toggleterm.setup({
			direction = 'float',
			float_opts = {
				border = 'none',
				width = vim.o.columns,
				height = vim.o.lines - 2
			}
		});
	end
}
