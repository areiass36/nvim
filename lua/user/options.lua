local options = {
	clipboard = "unnamedplus",
	number = true,
	relativenumber = true,
	--	tabstop = 4, -- set tab size
	--wildmenu = true,
	--wildmode = "list:longest",
}

for k, v in pairs(options) do
	vim.opt[k] = v
end


vim.api.nvim_create_autocmd("InsertLeave", {
	buffer = buffer,
	callback = function()
		vim.lsp.buf.format { async = false, tabSize = 4 }
	end
})
