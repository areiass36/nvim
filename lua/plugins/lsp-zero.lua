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
			require('lspconfig').csharp_ls.setup({})
			--			require('lspconfig').tsserver.setup({})
			require('lspconfig').lua_ls.setup({})
			require('lspconfig').volar.setup({
				filetypes = { 'typescript', 'javascript', 'javascriptreact', 'typescriptreact', 'vue', 'json' },
				init_options = {
					languageFeatures = {
						implementation = true,
						references = true,
						definition = true,
						typeDefinition = true,
						callHierarchy = true,
						hover = true,
						rename = true,
						renameFileRefactoring = true,
						signatureHelp = true,
						codeAction = true,
						workspaceSymbol = true,
						completion = {
							defaultTagNameCase = 'kebabCase',
							defaultAttrNameCase = 'kebabCase',
							getDocumentNameCasesRequest = false,
							getDocumentSelectionRequest = false,
						},
					},
				}
			})
		end,
	},
	{ 'neovim/nvim-lspconfig' },
	{ 'hrsh7th/cmp-nvim-lsp' },
	{ 'hrsh7th/nvim-cmp' },
	{ 'L3MON4D3/LuaSnip' },
}
