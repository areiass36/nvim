-- Debugging with nvim-dap: UI behaviour, one module per language and keymaps.
-- What to run comes from .nvim/workspace.json now (see lua/runner), so the
-- configurations here are the fallback for a project without one.
local M = {}

function M.setup()
	-- TODO(temporary): full protocol logging to diagnose a Windows issue;
	-- remove once stable. Log: stdpath("data")/dap.log
	local dap = require("dap")
	dap.set_log_level("DEBUG")
	-- .vscode/launch.json is no longer a source: its entries need preLaunchTask,
	-- which nvim-dap cannot run, so F5 used to land on a macOS-only script.
	dap.providers.configs["dap.launch.json"] = nil
	require("debugger.ui").setup()
	require("debugger.dotnet").setup()
	require("debugger.python").setup()
	require("debugger.javascript").setup()
	require("debugger.breakpoints").setup()
	require("debugger.keymaps").setup()
end

return M
