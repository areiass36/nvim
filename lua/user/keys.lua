--define leader key
vim.g.mapleader = ","

-- Terminal keys
vim.keymap.set("t", "<Esc>", "<C-\\><C-n>", { silent = true })

-- Change between windows
vim.keymap.set("n", "<C-j>", "<C-w>j", { silent = true })
vim.keymap.set("n", "<C-k>", "<C-w>k", { silent = true })
vim.keymap.set("n", "<C-l>", "<C-w>l", { silent = true })
vim.keymap.set("n", "<C-h>", "<C-w>h", { silent = true })

-- Remap alt-w = "∑" for deleting previou word
vim.keymap.set("i", "∑", "<C-w>", { silent = true })
