return {
	"neovim/nvim-lspconfig",
	dependencies = { "hrsh7th/nvim-cmp", "nvim-telescope/telescope.nvim" },
	config = function()
		-- Completion capabilities for every server.
		vim.lsp.config("*", { capabilities = require("cmp_nvim_lsp").default_capabilities() })

		-- Per-server configuration (lua/servers/*.lua). Servers installed by Mason are
		-- enabled by mason-lspconfig; Roslyn enables itself once installed.
		require("servers")

		local builtin = require("telescope.builtin")
		local map = function(mode, lhs, rhs)
			vim.keymap.set(mode, lhs, rhs, { noremap = true, silent = true })
		end
		map("n", "gh", function()
			vim.lsp.buf.hover({ max_width = 90, max_height = 25 })
		end)
		map("n", "gs", function()
			vim.lsp.buf.signature_help({ max_width = 90 })
		end)
		map("n", "gd", builtin.lsp_definitions)
		map("n", "gD", vim.lsp.buf.declaration)
		map("n", "gi", builtin.lsp_implementations)
		map("n", "go", builtin.lsp_type_definitions)
		map("n", "gr", builtin.lsp_references)
		map("n", "rn", vim.lsp.buf.rename)
	end,
}
