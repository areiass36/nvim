-- One key to debug the project, IDE style: it continues a running session or
-- starts the project's main configuration — the first entry of
-- .vscode/launch.json, which launch_json.lua makes the first compound.
local dap = require("dap")

local M = {}

local function project_configurations()
	local provider = dap.providers.configs["dap.launch.json"]
	if not provider then
		return {}
	end
	local ok, configs = pcall(provider, vim.api.nvim_get_current_buf())
	return ok and configs or {}
end

function M.start()
	if dap.session() then
		return dap.continue()
	end
	local main = project_configurations()[1]
	if not main then
		return dap.continue()
	end
	vim.notify("[dap] starting " .. vim.trim(main.name), vim.log.levels.INFO)
	dap.run(main)
end

return M
