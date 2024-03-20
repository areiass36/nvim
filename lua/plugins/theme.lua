return {
	'Mofiqul/vscode.nvim',
	name = 'vscode',
	config = function()
		require('vscode').setup({
			color_overrides = {
				vscBack = '#000000',
				vscPopupBack = '#000000',
				vscTabOutside = '#000000',
				vscLeftDark = '#000000',
			},
		})

		vim.cmd('colorscheme vscode')
	end
}
