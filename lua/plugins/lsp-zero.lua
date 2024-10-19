return {
	{
		'VonHeikemen/lsp-zero.nvim',
		branch = 'v3.x',
		config = function()
			local lsp_zero = require 'lsp-zero'
			lsp_zero.set_sign_icons({
				error = '',
				warn = '',
				hint = '󰌵',
				info = ''
			})

			lsp_zero.extend_lspconfig()
			lsp_zero.on_attach(function(client, bufnr)
				lsp_zero.default_keymaps({ buffer = bufnr })
				vim.keymap.set('n', '<leader>ca',
					'<cmd>lua vim.lsp.buf.code_action()<CR>',
					{ noremap = true, silent = true, buffer = bufnr })
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
}
