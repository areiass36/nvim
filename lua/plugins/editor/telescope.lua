return {
	"nvim-telescope/telescope.nvim",
	tag = "v0.2.2",
	lazy = false,
	dependencies = {
		"nvim-lua/plenary.nvim",
		"nvim-telescope/telescope-live-grep-args.nvim",
		"nvim-telescope/telescope-file-browser.nvim",
		"areiass36/telepoon.nvim",
		"nvim-tree/nvim-web-devicons",
		-- Native sorter with prebuilt binaries for mac/linux/windows: nothing to compile.
		"natecraddock/telescope-zf-native.nvim",
		-- vim.ui.select (DAP menus, code actions, ...) becomes a Telescope picker.
		"nvim-telescope/telescope-ui-select.nvim",
	},
	config = function()
		local telescope = require("telescope")

		telescope.setup({
			defaults = {
				-- Hidden entries belong to the project just as much as the rest: .github,
				-- .editorconfig, .env.example, and on Windows everything under AppData,
				-- which is hidden by file attribute instead of a leading dot. rg's
				-- --hidden covers both conventions. Only .git stays out: a few thousand
				-- objects and refs would drown every result.
				vimgrep_arguments = {
					"rg",
					"--color=never",
					"--no-heading",
					"--with-filename",
					"--line-number",
					"--column",
					"--smart-case",
					"--hidden",
					"--glob=!**/.git/*",
				},
				layout_strategy = "horizontal",
				layout_config = {
					width = function()
						return vim.o.columns
					end,
					height = function()
						return vim.o.lines
					end,
					-- preview_width is only valid for the horizontal strategy; at the top
					-- level it breaks pickers that use another one (e.g. the ui-select dropdown).
					horizontal = {
						preview_width = function()
							return math.floor(vim.o.columns / 2)
						end,
					},
				},
				-- The patterns are Lua patterns matched against the whole path, so a bare
				-- ".git" also swallowed .gitignore and .github/: anchor it to the folder.
				file_ignore_patterns = { "node_modules", "bin", "obj", "%.git[/\\]" },
			},
			-- file_ignore_patterns applies to every picker that has a file attached,
			-- including the lsp_ ones: a definition inside node_modules (any npm
			-- dependency) or obj/ (generated C#) got filtered out and the picker
			-- reported "No Definitions found". Telescope documents this trap in
			-- config.lua. Jumping into a dependency is the point of gd, so the
			-- lsp_ pickers opt out of the ignore list.
			pickers = {
				lsp_definitions = { file_ignore_patterns = {} },
				lsp_references = { file_ignore_patterns = {} },
				lsp_implementations = { file_ignore_patterns = {} },
				lsp_type_definitions = { file_ignore_patterns = {} },
				-- Telescope appends --hidden on its own; the command is the rg default it
				-- would build anyway, plus the .git exclusion. rg is always available:
				-- tools/ripgrep.lua downloads it when the machine has none.
				find_files = {
					hidden = true,
					find_command = { "rg", "--files", "--color", "never", "--glob", "!**/.git/*" },
				},
			},
			extensions = {
				file_browser = {
					dir_icon = require("core.icons").folder,
					-- Dotfiles in both modes: the file list and the folder-only list (<C-f>).
					-- The browser reads the directory itself and only counts a leading dot as
					-- hidden, so AppData was already showing up there.
					hidden = { file_browser = true, folder_browser = true },
				},
				["ui-select"] = {
					require("telescope.themes").get_dropdown({
						layout_config = { width = 0.7, height = 0.45 },
						previewer = false,
					}),
				},
				["zf-native"] = {
					file = { enable = true, highlight_results = true, match_filename = true },
					generic = { enable = true, highlight_results = true, match_filename = false },
				},
			},
		})

		for _, extension in ipairs({ "live_grep_args", "zf-native", "ui-select", "telepoon", "file_browser" }) do
			telescope.load_extension(extension)
		end

		local builtin = require("telescope.builtin")
		local extensions = telescope.extensions
		local map = function(lhs, rhs)
			vim.keymap.set("n", lhs, rhs, { noremap = true, silent = true })
		end
		map("<leader>ff", builtin.find_files)
		map("<leader>fg", extensions.live_grep_args.live_grep_args)
		map("<leader>fb", builtin.buffers)
		map("<leader>fr", builtin.oldfiles)
		map("<leader>es", extensions.telepoon.telepoon)
		map("<leader>ee", extensions.file_browser.file_browser)
		map("<leader>ef", function()
			extensions.file_browser.file_browser({ path = "%:p:h", select_buffer = true })
		end)
	end,
}
