vim.lsp.config("yamlls", {
	settings = {
		yaml = {
			keyOrdering = false,
			schemaStore = { enable = true, url = "https://www.schemastore.org/api/json/catalog.json" },
		},
	},
})
