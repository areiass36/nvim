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

			require('mason').setup({})
			require('mason-lspconfig').setup({
				-- Replace the language servers listed here
				-- with the ones you want to install
				ensure_installed = { 'volar' },
				handlers = {
					lsp_zero.default_setup,
				vuels = lsp_zero.noop,

				},
			})
			--			require('lspconfig').csharp_ls.setup({})
			--			require('lspconfig').tsserver.setup({})
			require('lspconfig').lua_ls.setup({})
			require('lspconfig').volar.setup({})
			--				filetypes = { 'typescript', 'javascript', 'javascriptreact', 'typescriptreact', 'vue', 'json' },
			--				init_options = {
			--					typescript = {
			--						tsdk = '/path/to/.npm/lib/node_modules/typescript/lib'
			-- Alternative location if installed as root:
			--						-- tsdk = '/usr/local/lib/node_modules/typescript/lib'
			--					}
			--				}
			--			})
		end,
	},
	{ 'neovim/nvim-lspconfig' },
	{ 'hrsh7th/cmp-nvim-lsp' },
	{ 'hrsh7th/nvim-cmp' },
	{ 'L3MON4D3/LuaSnip' },
	{ "williamboman/mason.nvim", },
	{ "williamboman/mason-lspconfig.nvim", }
}
