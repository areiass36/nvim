-- Without a root_dir angularls attaches to every .ts file (single-file mode),
-- even outside Angular projects. Only attach when angular.json or nx.json exists.
vim.lsp.config("angularls", {
	root_dir = function(bufnr, on_dir)
		local root = vim.fs.root(bufnr, { "angular.json", "nx.json" })
		if root then
			on_dir(root)
		end
	end,
})
