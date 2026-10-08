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
			sources = { { name = "nvim_lsp" } },
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
