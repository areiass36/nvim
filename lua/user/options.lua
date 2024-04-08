vim.opt.clipboard = "unnamedplus"
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.wrap = false

vim.api.nvim_create_autocmd("InsertLeave", {
	buffer = buffer,
	callback = function()
		vim.lsp.buf.format { async = false }
	end
})
