return {
	"hrsh7th/nvim-cmp",
	dependencies = { "hrsh7th/cmp-nvim-lsp" },
	config = function()
		local cmp = require("cmp")

		local function select_or_complete(direction)
			return cmp.mapping(function()
				if not cmp.visible() then
					return cmp.complete()
				end
				if direction == "prev" then
					cmp.select_prev_item({ behavior = "insert" })
				else
					cmp.select_next_item({ behavior = "insert" })
				end
			end)
		end

		cmp.setup({
			-- minuet is the AI source (lsp/minuet.lua). It sits in a second
			-- group so LSP items always rank above it: the LSP knows your types,
			-- the model is guessing.
			sources = {
				{ name = "nvim_lsp", group_index = 1 },
				{ name = "minuet", group_index = 2 },
			},
			-- A model answers in a second or two, far slower than any other
			-- source; the default 500ms would drop every AI item.
			performance = { fetching_timeout = 2000 },
			mapping = {
				["<C-y>"] = cmp.mapping.confirm({ select = false }),
				["<C-e>"] = cmp.mapping.abort(),
				["<Up>"] = cmp.mapping.select_prev_item({ behavior = "select" }),
				["<Down>"] = cmp.mapping.select_next_item({ behavior = "select" }),
				["<C-p>"] = select_or_complete("prev"),
				["<C-n>"] = select_or_complete("next"),
			},
			window = {
				completion = cmp.config.window.bordered(),
				documentation = cmp.config.window.bordered(),
			},
		})
	end,
}
