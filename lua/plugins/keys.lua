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
	local telescope = require("telescope.config").values

	local function toggle_telescope(harpoon_files)
		local create_finder = function(files)
			local results = {}

			--print("received items in create_finder")
			--print(vim.inspect(files))
			local i = 1
			for _, item in pairs(files.items) do
				results[i] = item.value
				i = i + 1
			end
			--print("this is my result")
			--print(vim.inspect(results))
			return require("telescope.finders").new_table({
				results = results,
				entry_maker = function(entry)
					local display = vim.fn.fnamemodify(entry, ":t")
					return {
						value = entry,
						display = display,
						ordinal = display
					}
				end

			})
		end

		require("telescope.pickers").new({}, {
			prompt_title = "Harpoon",
			finder = create_finder(harpoon_files),
			previewer = telescope.file_previewer({}),
			sorter = telescope.generic_sorter({}),

			attach_mappings = function(prompt_buffer_number, map)
				map("n", "d", function()
					local state = require("telescope.actions.state")
					local selected_entry = state.get_selected_entry()
					local current_picker = state.get_current_picker(prompt_buffer_number)
					if not selected_entry then return end

					local list = harpoon:list()

					local file_name = selected_entry.value


					--print("picked file name")
					--print(file_name)
					local item_to_remove = nil

					for _, item in pairs(harpoon:list().items) do
						if item.value == file_name then
							item_to_remove = item
						end
					end

					--print("before remove list")
					--print(vim.inspect(list))
					list:remove(item_to_remove)
					--print("after remove list")
					--print(vim.inspect(list))
					local new_finder = create_finder(list)
					--print("inpected new_finder")
					--print(vim.inspect(new_finder))
					current_picker:refresh(new_finder)
				end)
				return true
			end,
		}):find()
	end

	vim.keymap.set('n', '<leader>ff', require("telescope.builtin").find_files, {})
	vim.keymap.set('n', '<leader>fg', ":lua require('telescope').extensions.live_grep_args.live_grep_args()<CR>", {})
	vim.keymap.set('n', '<leader>fb', require("telescope.builtin").buffers, {})
	vim.keymap.set("n", "<leader>es", function() toggle_telescope(harpoon:list()) end)
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
