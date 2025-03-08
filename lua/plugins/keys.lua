local opts = { noremap = true, silent = true }

function Keys_terminal()
	vim.keymap.set("n", "<leader>t", "<cmd>Telescope toggleterm_manager<CR>", opts);

	local actions = require("toggleterm-manager").actions;
	return {
		n = {
			["<CR>"] = { action = actions.open_term, exit_on_action = true },
			["r"] = { action = actions.rename_term, exit_on_action = false },
			["d"] = { action = actions.delete_term, exit_on_action = false },
			["c"] = { action = actions.create_and_name_term, exit_on_action = false }
		}
	}
end

function Keys_search()
	vim.keymap.set('n', '<leader>ff', require("telescope.builtin").find_files, opts)
	vim.keymap.set('n', '<leader>fg', ":lua require('telescope').extensions.live_grep_args.live_grep_args()<CR>",
		opts)
	vim.keymap.set('n', '<leader>fb', require("telescope.builtin").buffers, opts)
	vim.keymap.set("n", "<leader>es", ":lua require('telescope').extensions.telepoon.telepoon()<CR>", opts)
	vim.keymap.set("n", "<leader>a", ":lua require('harpoon'):list():add()<CR>", opts)
	vim.keymap.set("n", "<leader>ee", ":lua require('telescope').extensions.file_browser.file_browser()<CR>")
	vim.keymap.set("n", "<leader>ef",
		":lua require('telescope').extensions.file_browser.file_browser({ path = '%:p:h', select_buffer = true })<CR>");
end

function Keys_server()
	vim.keymap.set('n', 'gh', '<cmd>lua vim.lsp.buf.hover()<CR>', opts)
	vim.keymap.set({ "v", "n" }, "ga", ":lua require('actions-preview').code_actions()<CR>", opts)
	vim.keymap.set('n', 'gd', '<cmd>lua vim.lsp.buf.definition()<CR>', opts)
	vim.keymap.set('n', 'gD', '<cmd>lua vim.lsp.buf.declaration()<CR>', opts)
	vim.keymap.set('n', 'gi', '<cmd>lua vim.lsp.buf.implementation()<CR>', opts)
	vim.keymap.set('n', 'go', '<cmd>lua vim.lsp.buf.type_definition()<CR>', opts)
	vim.keymap.set('n', 'gr', '<cmd>lua vim.lsp.buf.references()<CR>', opts)
	vim.keymap.set('n', 'gs', '<cmd>lua vim.lsp.buf.signature_help()<CR>', opts)
	vim.keymap.set('n', 'rn', '<cmd>lua vim.lsp.buf.rename()<CR>', opts);
end
