-- Install missing Mason packages and fire `User ToolsReady` when done. Used
-- instead of mason-lspconfig's ensure_installed so LSP servers, debug adapters
-- and tree-sitter-cli are declared in one place and it also works headless.
local tools = require("tools")

local M = {}

local function fire_ready()
	vim.schedule(function()
		vim.api.nvim_exec_autocmds("User", { pattern = "ToolsReady", modeline = false })
	end)
end

--- @param packages string[] Mason package names
function M.ensure(packages)
	local registry = require("mason-registry")

	registry.refresh(function()
		local missing = {}
		for _, name in ipairs(packages) do
			local ok, package = pcall(registry.get_package, name)
			if not ok then
				tools.notify("unknown Mason package: " .. name, vim.log.levels.WARN)
			elseif not package:is_installed() and not package:is_installing() then
				missing[#missing + 1] = package
			end
		end

		if #missing == 0 then
			return fire_ready()
		end

		tools.notify(("installing %d tool(s) with Mason..."):format(#missing))
		local pending = #missing
		for _, package in ipairs(missing) do
			package:install({}, function(success, err)
				if not success then
					tools.notify(
						("failed to install %s: %s"):format(package.name, vim.inspect(err)),
						vim.log.levels.ERROR
					)
				end
				pending = pending - 1
				if pending == 0 then
					tools.notify("Mason tools ready")
					fire_ready()
				end
			end)
		end
	end)
end

return M
