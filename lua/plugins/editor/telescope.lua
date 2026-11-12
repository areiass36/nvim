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
		-- The extension loads this module itself; requiring it here avoids touching
		-- telescope.extensions before setup has run, which would set the extension up
		-- with an empty config.
		local fb_actions = require("telescope._extensions.file_browser.actions")

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
				-- Let a previewer name what it is showing -- the file, the table,
				-- the schema -- instead of every pane being titled "Preview".
				-- Telescope's own builtins carry a dyn_title and so does the
				-- database explorer's pane (lua/grip/preview.lua); without this
				-- none of them are ever asked for it.
				dynamic_preview_title = true,
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
					hidden = { file_browser = true, folder_browser = true },
					-- `hidden` is only the leading-dot filter; three more were hiding the
					-- rest, and a build directory belongs to the project being navigated,
					-- so dist/, bin/, obj/ and node_modules/ all show up now.
					--
					-- respect_gitignore defaults to whether fd happens to be installed
					-- (if_nil(opts.respect_gitignore, has_fd())), so the listing changed
					-- the day winget put fd on this machine, and would differ again on
					-- Debian, where the binary is called fdfind. no_ignore covers what fd
					-- reads beyond .gitignore: .ignore, .fdignore and the global one.
					respect_gitignore = false,
					no_ignore = true,
					-- Telescope applies file_ignore_patterns to every entry that has a
					-- path, the browser included, so node_modules/ and obj/ stayed
					-- invisible here even with gitignore off. Empty for this picker
					-- alone: find_files and the grep keep the defaults.
					file_ignore_patterns = {},
					-- toggle_respect_gitignore ships unmapped; <C-h> toggles only the dot
					-- filter. <A-i> joins the <A-*> family already used for create/rename.
					mappings = {
						["i"] = { ["<A-i>"] = fb_actions.toggle_respect_gitignore },
						["n"] = { ["<A-i>"] = fb_actions.toggle_respect_gitignore },
					},
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

		-- `nvim .` (or `nvim some/dir`) opens a buffer for the directory, which
		-- netrw takes over. Hand it to the file browser instead: the directory
		-- becomes the working directory, so every picker and the language
		-- servers root themselves there, and the start screen is drawn behind
		-- the browser, so closing it lands on the dashboard. The netrw buffer is
		-- deleted; nothing falls back to it.
		vim.api.nvim_create_autocmd("VimEnter", {
			group = vim.api.nvim_create_augroup("TelescopeDirectoryArgument", { clear = true }),
			-- Both the start screen and the picker set themselves up on autocmds.
			nested = true,
			callback = function()
				if vim.fn.argc() ~= 1 then
					return
				end
				-- When this Neovim runs in a terminal inside another one,
				-- nvim-unception forwards the argument to that one and this
				-- instance quits right after: nothing to open here. Every
				-- instance has the variable set, the host pointing it at a pipe
				-- of its own (nvim-unception's server.lua), so it only means
				-- "there is another Neovim to hand this to" when the pipe is
				-- not one of ours.
				local host = os.getenv("NVIM_UNCEPTION_PIPE_PATH_HOST")
				if host and not vim.list_contains(vim.fn.serverlist(), host) then
					return
				end
				local directory = vim.fn.fnamemodify(vim.fn.argv(0), ":p")
				if vim.fn.isdirectory(directory) == 0 then
					return
				end
				local directory_buffer = vim.api.nvim_get_current_buf()
				vim.api.nvim_set_current_dir(directory)
				-- Deferred rather than opened right here: a picker created inside
				-- the VimEnter callback comes up without focus -- the prompt
				-- window is drawn, but keystrokes go nowhere and <Esc> does not
				-- close it. One tick later startup is over and it takes focus the
				-- way it does from a keymap. That is also after netrw's own
				-- VimEnter handler, so the listing goes away whichever order the
				-- two autocmds ended up registered in.
				vim.schedule(function()
					-- alpha draws itself only when Neovim starts with no arguments.
					require("alpha").start(false)
					if vim.api.nvim_buf_is_valid(directory_buffer) then
						vim.api.nvim_buf_delete(directory_buffer, { force = true })
					end
					extensions.file_browser.file_browser({ path = directory })
				end)
			end,
		})
	end,
}
