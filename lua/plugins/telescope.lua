return {
	'nvim-telescope/telescope.nvim',
	tag = '0.1.6',
	lazy = false,
	dependencies = {
		'nvim-lua/plenary.nvim',
		{
			'aznhe21/actions-preview.nvim',
			config = function()
				vim.keymap.set({ "v", "n" }, "gf", require("actions-preview").code_actions)
			end
		},
		"nvim-telescope/telescope-live-grep-args.nvim",
		{ 'nvim-telescope/telescope-fzf-native.nvim', build = 'make' },
		'Slotos/telescope-lsp-handlers.nvim',
	},
	config = function()
		-- Telescope keys
		local telescope = require('telescope')
		local handlers = require('telescope-lsp-handlers')

		telescope.setup({
			extensions = {
				fzf = {
					fuzzy = true, -- false will only do exact matching
					override_generic_sorter = true, -- override the generic sorter
					override_file_sorter = true, -- override the file sorter
					case_mode = "smart_case", -- or "ignore_case" or "respect_case"
					-- the default case_mode is "smart_case"
				}
			},
			defaults = {
				file_ignore_patterns = {
					"node_modules",
					"bin",
					"obj",
					".git"
				}
			}
		})
		-- Adds live grep plugin
		telescope.load_extension('live_grep_args')
		telescope.load_extension('fzf')

		handlers.setup({
			declaration = {
				disabled = false,
				picker = { prompt_title = 'LSP Declarations' },
				no_results_message = 'Declaration not found',
			},
			definition = {
				disabled = false,
				picker = { prompt_title = 'LSP Definitions' },
				no_results_message = 'Definition not found',
			},
			implementation = {
				disabled = false,
				picker = { prompt_title = 'LSP Implementations' },
				no_results_message = 'Implementation not found',
			},
			type_definition = {
				disabled = false,
				picker = { prompt_title = 'LSP Type Definitions' },
				no_results_message = 'Type definition not found',
			},
			reference = {
				disabled = false,
				picker = { prompt_title = 'LSP References' },
				no_results_message = 'No references found'
			},
			document_symbol = {
				disabled = false,
				picker = { prompt_title = 'LSP Document Symbols' },
				no_results_message = 'No symbols found',
			},
			workspace_symbol = {
				disabled = false,
				picker = { prompt_title = 'LSP Workspace Symbols' },
				no_results_message = 'No symbols found',
			},
			incoming_calls = {
				disabled = false,
				picker = { prompt_title = 'LSP Incoming Calls' },
				no_results_message = 'No calls found',
			},
			outgoing_calls = {
				disabled = false,
				picker = { prompt_title = 'LSP Outgoing Calls' },
				no_results_message = 'No calls found',
			},
		})

		local builtin = require('telescope.builtin')
		vim.keymap.set('n', '<leader>ff', builtin.find_files, {})
		vim.keymap.set('n', '<leader>fg',
			":lua require('telescope').extensions.live_grep_args.live_grep_args()<CR>", {})
		vim.keymap.set('n', '<leader>fb', builtin.buffers, {})
		vim.keymap.set('n', '<leader>fh', builtin.help_tags, {})

		local actionsPreview = require('actions-preview')
		actionsPreview.setup {
			diff = {
				ctxlen = 3,
			},

			-- priority list of external command to highlight diff
			-- disabled by defalt, must be set by yourself
			highlight_command = {
				-- require("actions-preview.highlight").delta(),
				-- require("actions-preview.highlight").diff_so_fancy(),
				-- require("actions-preview.highlight").diff_highlight(),
			},

			-- priority list of preferred backend
			backend = { "telescope", "nui" },

			-- options related to telescope.nvim
			telescope = vim.tbl_extend(
				"force",
				-- telescope theme: https://github.com/nvim-telescope/telescope.nvim#themes
				require("telescope.themes").get_dropdown(),
				-- a table for customizing content
				{
					-- a function to make a table containing the values to be displayed.
					-- fun(action: Action): { title: string, client_name: string|nil }
					make_value = nil,

					-- a function to make a function to be used in `display` of a entry.
					-- see also `:h telescope.make_entry` and `:h telescope.pickers.entry_display`.
					-- fun(values: { index: integer, action: Action, title: string, client_name: string }[]): function
					make_make_display = nil,
				})
		}
	end
}
