local tools = require("tools")

-- The Vue language server runs in "hybrid mode": TypeScript inside .vue files
-- is served by ts_ls through the Vue plugin that ships with vue-language-server.
vim.lsp.config("ts_ls", {
	init_options = {
		plugins = {
			{
				name = "@vue/typescript-plugin",
				location = tools.mason_package("vue-language-server")
					.. "/node_modules/@vue/typescript-plugin",
				languages = { "javascript", "typescript", "vue" },
			},
		},
	},
	-- The lspconfig defaults (lsp/ts_ls.lua) plus "vue". Keep both React
	-- variants: .tsx maps to "typescriptreact" and .jsx to "javascriptreact",
	-- and dropping them leaves those files with no server attached.
	filetypes = {
		"javascript",
		"javascriptreact",
		"typescript",
		"typescriptreact",
		"vue",
	},
})
