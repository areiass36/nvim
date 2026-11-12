-- AI completion through your own API key, so no Copilot account is involved.
-- Suggestions arrive two ways: grey ghost text inline, and as a source in the
-- nvim-cmp popup next to the LSP items (see lsp/completion.lua).
--
-- The key is read from kvstore at request time (see lua/ai/keys.lua); neither
-- the secret nor an environment variable name is what matters here anymore.
--
-- The request carries project context the way Copilot does -- a summary of
-- every file's declarations plus the buffers you last visited, assembled in
-- lua/ai/context.lua. That digest is large and does not change while you type,
-- so it goes in the system prompt and the transform below marks it as a
-- cacheable prefix: written once, then read back at about a tenth of the input
-- price on every later keystroke pause.
return {
	"milanglacier/minuet-ai.nvim",
	dependencies = { "hrsh7th/nvim-cmp", "areiass36/kvstore.nvim" },
	event = "InsertEnter",
	-- At startup, so :AiContext and the index refresh exist without waiting for
	-- the first insert. Neither module pulls in minuet.
	init = function()
		require("ai.context").setup()
		require("ai.keys").setup()
	end,
	config = function()
		local defaults = require("minuet.config")

		require("minuet").setup({
			provider = "claude",

			-- A completion fires on every typing pause, so the request stays
			-- small: two candidates, a modest window, and a hard timeout that
			-- drops a slow answer instead of making you wait for it.
			-- One candidate. Each extra one is another generation to wait for;
			-- raise it and the virtualtext shows "(1/2)" to cycle with <A-]>.
			n_completions = 1,
			-- The current file is the only part of the prompt that cannot be
			-- cached -- it changes with every keystroke -- so it is also where
			-- the whole per-request bill is. Raised from 12000 because nine
			-- files here are longer than that and were being truncated, but no
			-- further: beyond the three largest files the project index below
			-- already covers what falls outside this window.
			context_window = 16000,
			debounce = 400,
			throttle = 1000,
			-- One second more than before: the prompt now carries the project
			-- digest, and a cold request -- the first of a session, or the first
			-- after the index is rebuilt -- has to prefill it uncached.
			request_timeout = 4,
			-- Only surface real failures (a missing key, a 401); "no completion
			-- this time" is not worth a message on every pause.
			notify = "error",

			provider_options = {
				claude = {
					-- Haiku, because time-to-first-token is the whole cost on a
					-- completion path. Moving to a Sonnet means revisiting the
					-- thinking setting below -- the two families do not accept
					-- the same values -- and re-checking that the digest still
					-- caches: the minimum cacheable prefix is per-model, and
					-- below it nothing is cached and nothing says so.
					model = "claude-haiku-5-5",
					api_key = require("ai.keys").reader("anthropic-api-key", "ANTHROPIC_API_KEY"),
					max_tokens = 256,
					stream = true,

					-- The project digest goes here rather than into the user
					-- message, for two reasons. The render order is tools, then
					-- system, then messages, so anything in the system prompt
					-- sits ahead of the volatile cursor context; and a single
					-- breakpoint at the end of system then covers the whole
					-- stable prefix. Keys not named here keep their defaults.
					system = {
						template = defaults.default_system.template .. "\n{{{project}}}",
						project = function()
							return require("ai.context").digest()
						end,
					},

					-- The backend sends `system` as a plain string, and
					-- cache_control only attaches to a content block, so this
					-- rewrites it into one. Everything before the breakpoint --
					-- here, the whole system prompt including the digest -- is
					-- cached; the messages after it are not, which is exactly
					-- the split we want.
					transform = {
						function(data)
							if type(data.body.system) == "string" then
								data.body.system = {
									{
										type = "text",
										text = data.body.system,
										cache_control = { type = "ephemeral" },
									},
								}
							end
							return data
						end,
					},

					optional = {
						-- The lowest thinking setting this model takes. Without tools
						-- in the request it means no thinking at all, so the first token
						-- arrives without waiting on reasoning. Takes no other field.
						-- Must stay at "high" or below for the setting above to be
						-- accepted; "low" also keeps the completion terse.
						output_config = { effort = "high" },
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
