local opts = { noremap = true, silent = true }
--define leader key
vim.g.mapleader = ","
vim.g.maplocalleader = ","

local keys = vim.api.nvim_set_keymap --nvim api 
-- Resize windows
keys("n","<C-Down>",":resize -2<CR>",opts)
keys("n","<C-Up>",":resize +2<CR>",opts)
keys("n","<C-Right>",":vertical resize +2<CR>",opts)
keys("n","<C-Left>",":vertical resize -2<CR>",opts)

-- Change between windows
keys("n","<C-j>","<C-w>j",opts)
keys("n","<C-k>","<C-w>k",opts)
keys("n","<C-l>","<C-w>l",opts)
keys("n","<C-h>","<C-w>h",opts)

-- Toggle explorer
keys("n","<leader>e",":Lex 30<cr>",opts)
