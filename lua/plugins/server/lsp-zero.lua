return {
	'VonHeikemen/lsp-zero.nvim',
	branch = 'v4.x',
	dependencies = {
		'neovim/nvim-lspconfig',
		'hrsh7th/cmp-nvim-lsp',
		'hrsh7th/nvim-cmp',
		--{ 'L3MON4D3/LuaSnip' },
		--csharp
		'Hoffs/omnisharp-extended-lsp.nvim',
	},
	config = function()
		vim.opt.signcolumn = 'yes';
		local lspconfig = require('lspconfig');
		local lsp_zero = require('lsp-zero');
		local cmp = require('cmp');

		lspconfig.util.default_config.capabilities = vim.tbl_deep_extend(
			'force',
			lspconfig.util.default_config.capabilities,
			require('cmp_nvim_lsp').default_capabilities()
		);

		lsp_zero.set_sign_icons({
			error = '',
			warn = '',
			hint = '',
			info = ''
		})

		cmp.setup({
			window = {
				completion = cmp.config.window.bordered(),
				documentation = cmp.config.window.bordered()
			},
		})
	end,
}
