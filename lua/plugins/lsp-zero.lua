return {
	{
		'VonHeikemen/lsp-zero.nvim',
		branch = 'v3.x',

		config = function()
			local lsp_zero = require 'lsp-zero'
			lsp_zero.set_sign_icons({
				error = '',
				warn = '',
				hint = '',
				info = ''
			})

			lsp_zero.extend_lspconfig()
			lsp_zero.on_attach(function(client, bufnr)
				lsp_zero.default_keymaps({ buffer = bufnr })
				vim.api.nvim_set_keymap('n', '<leader>rn', '<cmd>lua vim.lsp.buf.rename()<CR>',
					{ noremap = true, silent = true })
				vim.keymap.set('n', '<leader>ca',
					'<cmd>lua vim.lsp.buf.code_action()<CR>',
					{ noremap = true, silent = true, buffer = bufnr })

				local cmp = require 'cmp';
				cmp.setup({
					window = {
						completion = cmp.config.window.bordered(),
						documentation = cmp.config.window.bordered()
					},
					mapping = cmp.mapping.preset.insert({
						['<C-Space>'] = cmp.mapping.complete(),
						['<CR>'] = cmp.mapping.confirm({
							behavior = cmp.ConfirmBehavior.Insert,
							select = true,
						})
					})
				})
			end)
			-- mason lsp installer
			require 'mason'.setup({})
			require 'mason-lspconfig'.setup({
				ensure_installed = { 'volar', 'lua_ls', 'angularls', 'omnisharp' },
				handlers = {
					lsp_zero.default_setup,
					vuels = lsp_zero.noop,
				},
			})
			require('mason-nvim-dap').setup({
				ensure_installed = { 'coreclr' },
				automatic_installation = true,
				handlers = {
					function(config)
						require('mason-nvim-dap').default_setup(config)
					end,
				}
			})

			require 'lsp'
		end,
	},
	{ 'Hoffs/omnisharp-extended-lsp.nvim' },
	{ 'neovim/nvim-lspconfig' },
	{ 'hrsh7th/cmp-nvim-lsp' },
	{ 'hrsh7th/nvim-cmp' },
	{ 'L3MON4D3/LuaSnip' },
	{ "williamboman/mason.nvim", },
	{ "williamboman/mason-lspconfig.nvim", },
	{ 'mfussenegger/nvim-dap' },
	{ 'rcarriga/nvim-dap-ui' },
	{ 'jay-babu/mason-nvim-dap.nvim' },
}
