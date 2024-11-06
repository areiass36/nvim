local lspconfig = require('lspconfig');
lspconfig.ts_ls.setup({
	init_options = {
		plugins = {
			{
				name = "@vue/typescript-plugin",
				location = Path.npm .. "/@vue/typescript-plugin",
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
