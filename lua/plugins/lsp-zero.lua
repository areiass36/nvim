require("utils")

return {
	{
		'VonHeikemen/lsp-zero.nvim',
		branch = 'v3.x',
		config = function()
			local lsp_zero = require('lsp-zero')
			lsp_zero.extend_lspconfig()
			lsp_zero.on_attach(function(client, bufnr)
				lsp_zero.default_keymaps({ buffer = bufnr })
			end)
		-- mason lsp installer
			require('mason').setup({})
			require('mason-lspconfig').setup({
				ensure_installed = { 'volar', 'tsserver', 'csharp_ls', 'lua_ls', },
				handlers = {
					lsp_zero.default_setup,
					vuels = lsp_zero.noop,

				},
			})
			require('lspconfig').csharp_ls.setup({})
			require('lspconfig').lua_ls.setup({})
			require('lspconfig').tsserver.setup({
				init_options = {
					plugins = {
						{
							name = "@vue/typescript-plugin",
							location = nodePath() .. "@vue/typescript-plugin",
							languages = { "javascript", "typescript", "vue" },
						},
					},
				},
				filetypes = {
					"javascript",
					"typescript",
					"vue",
				},
			})
			require('lspconfig').volar.setup({
				filetypes = { 'typescript', 'javascript', 'javascriptreact', 'typescriptreact', 'vue', 'json' },
				init_options = {
					typescript = {
						tsdk = nodePath() .. "@vue/typescript-plugin",
					}
				}
			})
		end,
	},
	{ 'neovim/nvim-lspconfig' },
	{ 'hrsh7th/cmp-nvim-lsp' },
	{ 'hrsh7th/nvim-cmp' },
	{ 'L3MON4D3/LuaSnip' },
	{ "williamboman/mason.nvim", },
	{ "williamboman/mason-lspconfig.nvim", }
}
