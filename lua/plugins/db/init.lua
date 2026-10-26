-- The database client lives in lua/db; this spec only decides when it loads,
-- the same way lua/plugins/dap/init.lua does for lua/debugger.
return {
	dir = vim.fn.stdpath("config"),
	name = "db",
	lazy = false,
	dependencies = { "nvim-telescope/telescope.nvim", "hrsh7th/nvim-cmp" },
	config = function()
		require("db").setup()
	end,
}
