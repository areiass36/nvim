function Keys_editor()
	-- Change between windows
	vim.keymap.set("n", "<C-j>", "<C-w>j", { silent = true })
	vim.keymap.set("n", "<C-k>", "<C-w>k", { silent = true })
	vim.keymap.set("n", "<C-l>", "<C-w>l", { silent = true })
	vim.keymap.set("n", "<C-h>", "<C-w>h", { silent = true })

	-- Escape terminal
	vim.keymap.set("t", "<Esc>", "<C-\\><C-n>", { silent = true })

	-- Remap alt-w = "∑" for deleting previou word
	vim.keymap.set("i", "∑", "<C-w>", { silent = true })

	vim.keymap.set("n", "<leader>s", ":lua vim.diagnostic.open_float()<CR>", { silent = true });
end
