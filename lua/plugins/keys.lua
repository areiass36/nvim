function Keys_terminal()
	vim.keymap.set("n", "<leader>t", "<cmd>Telescope toggleterm_manager<CR>", { noremap = true, silent = true });
	return {
		i = {
			["<CR>"] = { action = require("toggleterm-manager").actions.toggle_term, exit_on_action = false },
			["<C-i>"] = { action = require("toggleterm-manager").actions.create_term, exit_on_action = false },
			["<C-d>"] = { action = require("toggleterm-manager").actions.delete_term, exit_on_action = false },
			["<C-r>"] = { action = require("toggleterm-manager").actions.rename_term, exit_on_action = false },
		},
		n = {
			["<CR>"] = { action = require("toggleterm-manager").actions.open_term, exit_on_action = true }
		}
	}
end

function Keys_browser()
	vim.keymap.set("n", "<leader>ee", ":lua require('telescope').extensions.file_browser.file_browser()<CR>")
	vim.keymap.set("n", "<leader>ef",
		":lua require('telescope').extensions.file_browser.file_browser({ path = '%:p:h', select_buffer = true })<CR>");
end

function Keys_search()
	vim.keymap.set('n', '<leader>ff', require("telescope.builtin").find_files, {})
	vim.keymap.set('n', '<leader>fg', ":lua require('telescope').extensions.live_grep_args.live_grep_args()<CR>", {})
	vim.keymap.set('n', '<leader>fb', require("telescope.builtin").buffers, {})
end

function Keys_server()
	vim.keymap.set('n', 'K', '<cmd>lua vim.lsp.buf.hover()<cr>', { noremap = true, silent = true })
	vim.keymap.set('n', 'gd', '<cmd>lua vim.lsp.buf.definition()<cr>', { noremap = true, silent = true })
	vim.keymap.set('n', 'gD', '<cmd>lua vim.lsp.buf.declaration()<cr>', { noremap = true, silent = true })
	vim.keymap.set('n', 'gi', '<cmd>lua vim.lsp.buf.implementation()<cr>', { noremap = true, silent = true })
	vim.keymap.set('n', 'go', '<cmd>lua vim.lsp.buf.type_definition()<cr>', { noremap = true, silent = true })
	vim.keymap.set('n', 'gr', '<cmd>lua vim.lsp.buf.references()<cr>', { noremap = true, silent = true })
	vim.keymap.set('n', 'gs', '<cmd>lua vim.lsp.buf.signature_help()<cr>', { noremap = true, silent = true })
	vim.keymap.set('n', '<F2>', '<cmd>lua vim.lsp.buf.rename()<cr>', { noremap = true, silent = true })
	vim.keymap.set({ 'n', 'x' }, '<F3>', '<cmd>lua vim.lsp.buf.format({async = true})<cr>',
		{ noremap = true, silent = true })
	vim.keymap.set('n', '<F4>', '<cmd>lua vim.lsp.buf.code_action()<cr>', { noremap = true, silent = true })
	vim.keymap.set('n', 'rn', '<cmd>lua vim.lsp.buf.rename()<CR>', { noremap = true, silent = true });
	vim.keymap.set({ "v", "n" }, "gf", require("actions-preview").code_actions)
end
