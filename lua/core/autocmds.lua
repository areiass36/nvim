local group = vim.api.nvim_create_augroup("CoreAutocmds", { clear = true })

-- Format with the attached LSP server whenever insert mode is left.
vim.api.nvim_create_autocmd("InsertLeave", {
	group = group,
	callback = function()
		vim.lsp.buf.format({ async = false })
	end,
})

-- Stop every language server on exit so none is left orphaned.
vim.api.nvim_create_autocmd("VimLeavePre", {
	group = group,
	callback = function()
		for _, client in ipairs(vim.lsp.get_clients()) do
			client:stop(true)
		end
	end,
})
