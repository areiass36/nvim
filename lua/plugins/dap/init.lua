return {
	"mfussenegger/nvim-dap",
	dependencies = {
		{ "rcarriga/nvim-dap-ui", dependencies = { "nvim-neotest/nvim-nio" } },
		"mason-org/mason.nvim",
	},
	config = function()
		require("debugger").setup()
	end,
}
