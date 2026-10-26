-- AI completion through your own API key, so no Copilot account is involved.
-- Suggestions arrive two ways: grey ghost text inline, and as a source in the
-- nvim-cmp popup next to the LSP items (see lsp/completion.lua).
--
-- The key is read from $ANTHROPIC_API_KEY at request time; only the variable
-- name lives here, never the secret.
return {
	"milanglacier/minuet-ai.nvim",
	dependencies = { "hrsh7th/nvim-cmp" },
	event = "InsertEnter",
	config = function()
		require("minuet").setup({
			provider = "claude",

			-- A completion fires on every typing pause, so the request stays
			-- small: two candidates, a modest window, and a hard timeout that
			-- drops a slow answer instead of making you wait for it.
			-- One candidate. Each extra one is another generation to wait for;
			-- raise it and the virtualtext shows "(1/2)" to cycle with <A-]>.
			n_completions = 1,
			context_window = 12000,
			debounce = 400,
			throttle = 1000,
			request_timeout = 3,
			-- Only surface real failures (a missing key, a 401); "no completion
			-- this time" is not worth a message on every pause.
			notify = "error",

			provider_options = {
				claude = {
					-- Sonnet 5.5 is the best model that can shed up-front thinking,
					-- which is what time-to-first-token costs here. Haiku 5.5 is
					-- faster and far cheaper; to use it, swap the model line and
					-- change the thinking type to "disabled" (Sonnet rejects that one,
					-- Haiku rejects "between_tools" -- the two are not interchangeable).
					-- model = "claude-haiku-5-5",
					model = "claude-sonnet-5-5",
					api_key = "ANTHROPIC_API_KEY",
					max_tokens = 256,
					stream = true,
					optional = {
						-- The lowest thinking setting this model takes. Without tools
						-- in the request it means no thinking at all, so the first token
						-- arrives without waiting on reasoning. Takes no other field.
						thinking = { type = "between_tools" },
						-- Must stay at "high" or below for the setting above to be
						-- accepted; "low" also keeps the completion terse.
						output_config = { effort = "low" },
					},
				},
			},

			virtualtext = {
				-- Every filetype. ":Minuet virtualtext" toggles it off for the
				-- session when the grey text gets in the way.
				auto_trigger_ft = { "*" },
				auto_trigger_ignore_ft = { "TelescopePrompt", "dap-repl", "dapui_watches" },
				keymap = {
					-- "accept" is deliberately absent: Tab is bound below, where it
					-- can fall back to a real Tab when there is nothing to accept.
					accept_line = "<A-a>",
					accept_n_lines = "<A-z>",
					prev = "<A-[>",
					next = "<A-]>",
					dismiss = "<A-e>",
				},
			},
		})

		-- The ghost text links to Comment by default, which this colorscheme
		-- paints green (#6A9955). Grey reads as "not yours yet"; green reads as
		-- a comment. Re-applied on ColorScheme because :colorscheme clears every
		-- highlight group, including this one.
		local function ghost_text_grey()
			vim.api.nvim_set_hl(0, "MinuetVirtualText", { fg = "#6b6b6b" })
		end
		ghost_text_grey()
		vim.api.nvim_create_autocmd("ColorScheme", {
			group = vim.api.nvim_create_augroup("minuet_ghost_text", { clear = true }),
			callback = ghost_text_grey,
			desc = "Keep the AI ghost text grey across colorscheme changes",
		})

		-- Tab accepts the suggestion while one is on screen, and otherwise does
		-- what Tab did before: jump to the next snippet placeholder when a
		-- snippet is active (Neovim's own default, see vim/_core/defaults.lua),
		-- or insert an indent.
		--
		-- Not an expr mapping: accepting writes to the buffer, and expr mappings
		-- run under textlock, where that fails with E565. A plain callback is
		-- also what the plugin uses for its own keymaps.
		local tab = vim.keycode("<Tab>")
		vim.keymap.set("i", "<Tab>", function()
			local action = require("minuet.virtualtext").action
			if action.is_visible() then
				action.accept()
			elseif vim.snippet.active({ direction = 1 }) then
				vim.snippet.jump(1)
			else
				vim.api.nvim_feedkeys(tab, "n", false)
			end
		end, { desc = "Accept AI suggestion, else snippet jump or indent", silent = true })
	end,
}
