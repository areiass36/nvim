-- Config side of the workspace runner: the icons it borrows and the ,r keymaps.
-- lua/runner/ ships neither, so this file is what becomes
-- lua/plugins/runner/init.lua if the module moves to a repository of its own.
--
-- ,r is the runner prefix: ,d belongs to the debugger, ,q to the database.
local icons = require("core.icons")

require("runner").setup({
	icons = {
		ok = icons.check,
		warn = icons.diagnostic_warn,
		error = icons.cross,
		cluster = icons.compound,
		runner = icons.terminal,
	},
})

local function map(lhs, rhs, desc)
	vim.keymap.set("n", lhs, rhs, { noremap = true, silent = true, desc = desc })
end

map("<leader>rc", "<cmd>RunnerCheck<CR>", "Runner: validate the workspace file")
map("<leader>rp", "<cmd>RunnerPlan<CR>", "Runner: what the default target would start")
map("<leader>rr", "<cmd>RunnerRun<CR>", "Runner: start the default target")
map("<leader>rs", "<cmd>RunnerStop<CR>", "Runner: stop the processes it started")

-- Left on the command line on purpose, so completion can offer the addresses.
vim.keymap.set("n", "<leader>ra", ":RunnerRun ", {
	noremap = true,
	silent = false,
	desc = "Runner: start an address (completes)",
})
