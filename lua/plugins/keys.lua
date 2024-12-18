function Keys_terminal()
	vim.keymap.set("n", "<leader>t", "<cmd>Telescope toggleterm_manager<CR>", { noremap = true, silent = true });

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

function Keys_browser()
	vim.keymap.set("n", "<leader>ee", ":lua require('telescope').extensions.file_browser.file_browser()<CR>")
	vim.keymap.set("n", "<leader>ef",
		":lua require('telescope').extensions.file_browser.file_browser({ path = '%:p:h', select_buffer = true })<CR>");
end

function Keys_search()
	local harpoon = require("harpoon")
	--local telescope = require("telescope.config").values

	--[[local function toggle_telescope(harpoon_files)
		local file_paths = {}
		for _, item in ipairs(harpoon_files.items) do
			table.insert(file_paths, item.value)
		end

		require("telescope.pickers").new({}, {
			prompt_title = "Harpoon",
			finder = require("telescope.finders").new_table({
				results = file_paths,
			}),
			previewer = telescope.file_previewer({}),
			sorter = telescope.generic_sorter({}),
		}):find()
	end ]] --

	vim.keymap.set('n', '<leader>ff', require("telescope.builtin").find_files, {})
	vim.keymap.set('n', '<leader>fg', ":lua require('telescope').extensions.live_grep_args.live_grep_args()<CR>", {})
	vim.keymap.set('n', '<leader>fb', require("telescope.builtin").buffers, {})
	vim.keymap.set("n", "<leader>es", function() harpoon.ui:toggle_quick_menu(harpoon:list()) end)
	vim.keymap.set("n", "<leader>a", function() harpoon:list():add() end)
	vim.keymap.set("n", "<C-S-P>", function() harpoon:list():prev() end)
	vim.keymap.set("n", "<C-S-N>", function() harpoon:list():next() end)
end

function Keys_server()
	vim.keymap.set('n', 'gh', '<cmd>lua vim.lsp.buf.hover()<cr>', { noremap = true, silent = true })
	vim.keymap.set({ "v", "n" }, "ga", require("actions-preview").code_actions)
	vim.keymap.set('n', 'gd', '<cmd>lua vim.lsp.buf.definition()<cr>', { noremap = true, silent = true })
	vim.keymap.set('n', 'gD', '<cmd>lua vim.lsp.buf.declaration()<cr>', { noremap = true, silent = true })
	vim.keymap.set('n', 'gi', '<cmd>lua vim.lsp.buf.implementation()<cr>', { noremap = true, silent = true })
	vim.keymap.set('n', 'go', '<cmd>lua vim.lsp.buf.type_definition()<cr>', { noremap = true, silent = true })
	vim.keymap.set('n', 'gr', '<cmd>lua vim.lsp.buf.references()<cr>', { noremap = true, silent = true })
	vim.keymap.set('n', 'gs', '<cmd>lua vim.lsp.buf.signature_help()<cr>', { noremap = true, silent = true })
	vim.keymap.set('n', 'rn', '<cmd>lua vim.lsp.buf.rename()<CR>', { noremap = true, silent = true });
end
