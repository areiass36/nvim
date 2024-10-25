return {
	'nvim-lualine/lualine.nvim',
	config = function()
		local lualine = require('lualine');
		lualine.setup({
			options = {
				theme = 'vscode'
			}
		});
	end,
	dependencies = { 'nvim-tree/nvim-web-devicons' }
}
