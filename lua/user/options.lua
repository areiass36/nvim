vim.opt.clipboard = "unnamedplus"
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.wrap = false

vim.api.nvim_create_autocmd("InsertLeave", {
	callback = function()
		vim.lsp.buf.format { async = false }
	end
})

vim.diagnostic.config {
	virtual_text = {
		prefix = ''
	}
}
