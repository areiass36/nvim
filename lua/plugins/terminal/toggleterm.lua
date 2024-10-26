return {
	"akinsho/toggleterm.nvim",
	config = function()
		local toggleterm = require('toggleterm');
		toggleterm.setup({
			direction = 'float',
			float_opts = {
				border = 'rounded',
				winblend = 3,
				highlights = {
					FloatBorder = {
						guifg = '#5a5a5a',
						guibg = 'NONE'
					}
				}
			}
		});
	end
}
