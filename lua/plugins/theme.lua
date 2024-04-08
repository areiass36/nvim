return {
	'Mofiqul/vscode.nvim',
	name = 'vscode',
	config = function()
		require('vscode').setup({
			color_overrides = {
			},
		})

		vim.cmd('colorscheme vscode')
	end
}
