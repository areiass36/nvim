local lspconfig = require('lspconfig');
local kvstore = require('kvstore');

lspconfig.ts_ls.setup({
	init_options = {
		plugins = {
			{
				name = "@vue/typescript-plugin",
				location = kvstore.get(Keys.path.npm) .. "/@vue/typescript-plugin",
				languages = { "javascript", "typescript", "vue" },
			},
		},
	},
	filetypes = {
		"javascript",
		"typescript",
		"vue",
	},
});
