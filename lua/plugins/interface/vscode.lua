return {
	'Mofiqul/vscode.nvim',
	name = 'vscode',
	config = function()
		local theme = require('vscode');
		theme.setup({
			color_overrides = {
				vscBack = '#000000',
				vscTabCurrent = '#000000',
				vscPopupBack = '#000000'
			},
		});
		vim.cmd('colorscheme vscode')
	end
}
