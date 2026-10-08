-- Everything installed through Mason. Install order matters only for the first
-- two: ts_ls uses the Vue plugin that ships inside vue-language-server.
local PACKAGES = {
	-- language servers
	"vue-language-server",
	"typescript-language-server",
	"lua-language-server",
	"angular-language-server",
	"json-lsp",
	"pyright",
	"css-lsp",
	-- debug adapters (netcoredbg comes from tools/netcoredbg.lua)
	"debugpy",
	"js-debug-adapter",
	-- builds treesitter parsers
	"tree-sitter-cli",
}

return {
	"mason-org/mason.nvim",
	dependencies = { "mason-org/mason-lspconfig.nvim", "neovim/nvim-lspconfig" },
	config = function()
		require("mason").setup({})
		-- mason-lspconfig v2 calls vim.lsp.enable() for every installed server,
		-- including the ones that finish installing later.
		require("mason-lspconfig").setup({
			-- C# uses roslyn_ls (servers/roslyn.lua), not omnisharp.
			automatic_enable = { exclude = { "omnisharp" } },
		})
		require("tools.mason").ensure(PACKAGES)
	end,
}
