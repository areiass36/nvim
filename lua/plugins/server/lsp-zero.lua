return {
	'VonHeikemen/lsp-zero.nvim',
	branch = 'v3.x',
	dependencies = {
		'neovim/nvim-lspconfig',
		'hrsh7th/cmp-nvim-lsp',
		'hrsh7th/nvim-cmp',
		--{ 'L3MON4D3/LuaSnip' },
		--csharp
		{ 'Hoffs/omnisharp-extended-lsp.nvim' },
	},
	config = function()
		vim.opt.signcolumn = 'yes';

		local lsp_zero = require('lsp-zero');
		local cmp = require('cmp');

		lsp_zero.set_sign_icons({
			error = '',
			warn = '',
			hint = '',
			info = ''
		})

		lsp_zero.extend_lspconfig();
		lsp_zero.on_attach(function(client, bufnr)
			cmp.setup({
				window = {
					completion = cmp.config.window.bordered(),
					documentation = cmp.config.window.bordered()
				},
			})
		end)
	end,
}
