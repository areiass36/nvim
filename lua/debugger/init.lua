-- Debugging with nvim-dap: UI behaviour, one module per language, VS Code
-- launch.json support and keymaps.
local M = {}

function M.setup()
	require("debugger.ui").setup()
	require("debugger.dotnet").setup()
	require("debugger.python").setup()
	require("debugger.javascript").setup()
	require("debugger.launch_json").setup()
	require("debugger.keymaps").setup()
end

return M
