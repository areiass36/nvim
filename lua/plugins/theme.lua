return {
	'Mofiqul/vscode.nvim',
	name = 'vscode',
	config = function()
		require('vscode').setup({
			color_overrides = {
				vscBack = '#000000'
			},
		})

		vim.cmd('colorscheme vscode')
	end
}
