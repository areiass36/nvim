-- Make the project's .vscode/launch.json usable outside VS Code:
--   * "node-terminal" only exists inside VS Code (js-debug exits at once
--     elsewhere), so it is converted to an equivalent pwa-node launch.
--   * legacy "node"/"chrome" types become "pwa-node"/"pwa-chrome".
--   * preLaunchTask is not supported by nvim-dap and is dropped (and flagged).
--   * "compounds" run every member configuration as a parallel session.
local dap = require("dap")
local icons = require("core.icons")

local M = {}

--- Split a command line, honouring single and double quotes.
local function shell_split(command)
	local args, current, quote = {}, nil, nil
	for char in command:gmatch(".") do
		if quote then
			if char == quote then
				quote = nil
			else
				current = (current or "") .. char
			end
		elseif char == "'" or char == '"' then
			quote = char
			current = current or ""
		elseif char:match("%s") then
			if current then
				args[#args + 1] = current
				current = nil
			end
		else
			current = (current or "") .. char
		end
	end
	if current then
		args[#args + 1] = current
	end
	return args
end

--- `VAR=x npm run dev` -> env + runtimeExecutable + runtimeArgs
local function convert_node_terminal(config)
	local env, argv = {}, {}
	for _, token in ipairs(shell_split(config.command)) do
		local key, value = token:match("^([%w_]+)=(.*)$")
		if key and #argv == 0 then
			env[key] = value
		else
			argv[#argv + 1] = token
		end
	end
	config.type = "pwa-node"
	config.runtimeExecutable = table.remove(argv, 1)
	config.runtimeArgs = argv
	config.env = next(env) and env or nil
	config.console = config.console or "integratedTerminal"
	config.autoAttachChildProcesses = true
	config.command = nil
end

local function normalize(config)
	if config.type == "node-terminal" and config.command then
		convert_node_terminal(config)
	end
	if config.type == "node" then
		config.type = "pwa-node"
	elseif config.type == "chrome" then
		config.type = "pwa-chrome"
	end
	if config.preLaunchTask then
		config.name = config.name .. "  (without preLaunchTask: " .. config.preLaunchTask .. ")"
		config.preLaunchTask = nil
	end
end

local function read_compounds(bufnr)
	local root = vim.fs.root(bufnr or 0, ".vscode")
	if not root then
		return {}
	end
	local ok, lines = pcall(vim.fn.readfile, root .. "/.vscode/launch.json")
	if not ok then
		return {}
	end
	local decoded, data = pcall(vim.json.decode, table.concat(lines, "\n"))
	return decoded and type(data) == "table" and data.compounds or {}
end

--- A compound becomes its first member; starting it launches the others as
--- parallel sessions. The marker function returns nil so the key is dropped
--- before the configuration reaches the adapter.
local function compound_configuration(compound, by_name)
	local members = {}
	for _, name in ipairs(compound.configurations or {}) do
		if by_name[name] then
			members[#members + 1] = by_name[name]
		end
	end
	if #members == 0 then
		return nil
	end
	local config = vim.deepcopy(members[1])
	config.name = (icons.compound .. "  %s  (%s)"):format(
		compound.name,
		table.concat(compound.configurations, " + ")
	)
	config.__compound = function()
		for index = 2, #members do
			local member = vim.deepcopy(members[index])
			vim.defer_fn(function()
				dap.run(member)
			end, 1500 * (index - 1))
		end
		return nil
	end
	return config
end

function M.setup()
	local provider = dap.providers.configs["dap.launch.json"]
	dap.providers.configs["dap.launch.json"] = function(bufnr)
		local configs = provider(bufnr)
		local by_name = {}
		for _, config in ipairs(configs) do
			normalize(config)
			by_name[config.name] = config
		end
		for _, compound in ipairs(read_compounds(bufnr)) do
			local config = compound_configuration(compound, by_name)
			if config then
				table.insert(configs, 1, config)
			end
		end
		return configs
	end
end

return M
