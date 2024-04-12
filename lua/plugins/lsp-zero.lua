return {
	{
		'VonHeikemen/lsp-zero.nvim',
		branch = 'v3.x',
		config = function()
			local lsp_zero = require('lsp-zero')
			lsp_zero.set_sign_icons({
				error = '',
				warn = '',
				hint = '󰌵',
				info = ''
			})
			local lspconfig = require('lspconfig')

			lsp_zero.extend_lspconfig()
			lsp_zero.on_attach(function(client, bufnr)
				lsp_zero.default_keymaps({ buffer = bufnr })
			end)
			-- mason lsp installer
			require('mason').setup({})
			require('mason-lspconfig').setup({
				ensure_installed = { 'volar', 'tsserver', 'lua_ls', 'pylsp', 'angularls', 'omnisharp' },
				handlers = {
					lsp_zero.default_setup,
					vuels = lsp_zero.noop,
				},
			})

			local os = vim.loop.os_uname().sysname;
			local windowsNodePath = "C:\\Program Files\\nodejs\\node_modules"
			local macNodePath = "/Users/areiass36/.asdf/installs/nodejs/20.11.1/lib/node_modules"

			local npmPath = os == "Darwin" and macNodePath or windowsNodePath
			--	lspconfig.csharp_ls.setup({
			--		config = {
			--			handlers = {
			--				["textDocument/definition"] = require('csharpls_extended').handler,
			--				["textDocument/typeDefinition"] = require('csharpls_extended').handler,
			--			},
			--					cmd = { csharpls },
			--			cmd = { "dotnet", "/Users/areiass36/.local/share/nvim/mason/packages/omnisharp/libexec/OmniSharp.dll" },
			--			}
			--		})
			lspconfig.omnisharp.setup({
				cmd = { "dotnet", "/Users/areiass36/.local/share/nvim/mason/packages/omnisharp/libexec/OmniSharp.dll" },
				settings = {
					FormattingOptions = {
						VarForBuiltInType = true,
						OrganizaImports = true
					},
					RoslynExtensionsOptions = {
						EnableAnalyzerSupport = nil
					}
				},
				handlers = {
					["textDocument/definition"] = require('omnisharp_extended').definition_handler,
					["textDocument/typeDefinition"] = require('omnisharp_extended')
					    .type_definition_handler,
					["textDocument/references"] = require('omnisharp_extended').references_handler,
					["textDocument/implementation"] = require('omnisharp_extended')
					    .implementation_handler,
				}
			})
			lspconfig.lua_ls.setup({
				settings = {
					Lua = {
						diagnostics = {
							globals = { 'vim' }
						}

					}
				}
			})
			lspconfig.angularls.setup({})
			lspconfig.tsserver.setup({
				init_options = {
					plugins = {
						{
							name = "@vue/typescript-plugin",
							location = npmPath .. "@vue/typescript-plugin",
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
			lspconfig.volar.setup({
				filetypes = { 'typescript', 'javascript', 'javascriptreact', 'typescriptreact', 'vue', 'json' },
				init_options = {
					typescript = {
						tsdk = npmPath .. "@vue/typescript-plugin",
					}
				}
			})
		end,
	},
	{ 'Decodetalkers/csharpls-extended-lsp.nvim' },
	{ 'Hoffs/omnisharp-extended-lsp.nvim' },
	{ 'neovim/nvim-lspconfig' },
	{ 'hrsh7th/cmp-nvim-lsp' },
	{ 'hrsh7th/nvim-cmp' },
	{ 'L3MON4D3/LuaSnip' },
	{ "williamboman/mason.nvim", },
	{ "williamboman/mason-lspconfig.nvim", },
}
