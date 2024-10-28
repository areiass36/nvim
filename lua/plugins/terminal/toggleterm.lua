return {
	"akinsho/toggleterm.nvim",
	config = function()
		local toggleterm = require("toggleterm");
		toggleterm.setup({
			direction = 'float',
			float_opts = {
				border = 'rounded'
			}
		});
	end
}
