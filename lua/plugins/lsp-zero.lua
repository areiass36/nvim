return {
	{
		'VonHeikemen/lsp-zero.nvim',
		branch = 'v3.x',
		config = function()
			local lsp_zero = require('lsp-zero')
			local lspconfig = require('lspconfig')

			lsp_zero.extend_lspconfig()
			lsp_zero.on_attach(function(client, bufnr)
				lsp_zero.default_keymaps({ buffer = bufnr })
			end)
			-- mason lsp installer
			require('mason').setup({})
			require('mason-lspconfig').setup({
				ensure_installed = { 'volar', 'tsserver', 'csharp_ls', 'lua_ls', 'pylsp', 'angularls' },
				handlers = {
					lsp_zero.default_setup,
					vuels = lsp_zero.noop,

				},
			})

			local os = vim.loop.os_uname().sysname;
			local windowsNodePath = "C:\\Program Files\\nodejs\\node_modules"
			local macNodePath = "/Users/areiass36/.asdf/installs/nodejs/20.11.1/lib/node_modules"

			local npmPath = os == "Darwin" and macNodePath or windowsNodePath
			lspconfig.csharp_ls.setup({})
			lspconfig.lua_ls.setup({})
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
	{ 'neovim/nvim-lspconfig' },
	{ 'hrsh7th/cmp-nvim-lsp' },
	{ 'hrsh7th/nvim-cmp' },
	{ 'L3MON4D3/LuaSnip' },
	{ "williamboman/mason.nvim", },
	{ "williamboman/mason-lspconfig.nvim", }
}
