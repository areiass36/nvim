return {
	"williamboman/mason.nvim",
	dependencies = {
		"williamboman/mason-lspconfig.nvim",
		'VonHeikemen/lsp-zero.nvim',
		'neovim/nvim-lspconfig',
	},
	config = function()
		local mason = require('mason');
		local masonLspConfig = require('mason-lspconfig');
		local lsp_zero = require('lsp-zero');

		mason.setup({})
		masonLspConfig.setup({
			ensure_installed = { 'volar', 'lua_ls', 'angularls', 'omnisharp' },
			handlers = {
				lsp_zero.default_setup,
				vuels = lsp_zero.noop,
			},
		})
		require('language');
	end
}
