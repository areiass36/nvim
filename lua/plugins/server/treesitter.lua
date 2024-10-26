return {
	'nvim-treesitter/nvim-treesitter',
	build = ":TSUpdate",
	config = function()
		local treesitter = require("nvim-treesitter.configs");
		treesitter.setup({
			ensure_installed = { "c", "lua", "vim", "vimdoc", "query", "elixir", "heex", "javascript", "html", "c_sharp", "typescript", "vue", 'python' },
			sync_install = false,
			highlight = { enable = true },
			indent = { enable = true },
		})
	end
}
