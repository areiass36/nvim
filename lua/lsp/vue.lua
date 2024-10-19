--[[
local npmPath = require('utils.nodepath')
require 'lspconfig'.volar.setup({
	filetypes = { 'typescript', 'javascript', 'javascriptreact', 'typescriptreact', 'vue', 'json' },
	init_options = {
		typescript = {
			tsdk = npmPath .. "@vue/typescript-plugin",
		}
	}
}) ]]
