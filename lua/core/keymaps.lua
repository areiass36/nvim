-- Editor-wide keymaps. Plugin keymaps live next to each plugin spec.
local map = vim.keymap.set
local silent = { silent = true }

-- Move between windows
map("n", "<C-h>", "<C-w>h", silent)
map("n", "<C-j>", "<C-w>j", silent)
map("n", "<C-k>", "<C-w>k", silent)
map("n", "<C-l>", "<C-w>l", silent)

-- Delete without touching registers
map("n", "X", '"_d')

-- Leave terminal mode
map("t", "<Esc>", "<C-\\><C-n>", silent)

-- Diagnostics under the cursor
map("n", "<leader>s", vim.diagnostic.open_float, silent)

-- Neovim 0.11+ ships gra/gri/grn/grr/grt. They make the "gr" mapping below wait
-- for 'timeoutlen', so they are removed in favour of the shorter LSP keymaps.
for _, key in ipairs({ "gra", "gri", "grn", "grr", "grt" }) do
	pcall(vim.keymap.del, { "n", "x" }, key)
end
