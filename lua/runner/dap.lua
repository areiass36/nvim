-- Turning a runner spec into a debug session. The only module of the runner
-- that knows nvim-dap exists; everything above it deals in plans and specs.
--
-- `debug` carries the adapter's own fields (program, module, pathMappings,
-- justMyCode, ...) straight through, so the file format does not have to grow a
-- mirror of every adapter. Only `adapter` and `request` are ours.
local M = {}

-- For these adapters the first word of `command` is the interpreter, not the
-- program: a launch takes it apart so one command serves both a plain run and a
-- debug session.
local INTERPRETER_FIELD = {
	python = "pythonPath",
}

local function own_fields(debug_spec)
	local config = vim.deepcopy(debug_spec)
	config.adapter = nil
	config.request = nil
	return config
end

--- Split `command` into the fields the adapter expects, unless the declaration
--- already named a program or a module.
--- @return string|nil err
local function from_command(config, spec, adapter)
	if config.program ~= nil or config.module ~= nil then
		return nil
	end

	local command = spec.command
	if type(command) ~= "table" or #command == 0 then
		return "launch needs program, module, or a command to derive them from"
	end

	local interpreter = INTERPRETER_FIELD[adapter]
	local first = 1
	if interpreter and #command > 1 then
		config[interpreter] = config[interpreter] or command[1]
		first = 2
	end

	config.program = command[first]
	local args = {}
	for index = first + 1, #command do
		args[#args + 1] = command[index]
	end
	if #args > 0 then
		config.args = config.args or args
	end
	return nil
end

--- The nvim-dap configuration a node stands for.
--- @return table|nil config, string|nil err
function M.config_of(node)
	local spec = node and node.spec
	if type(spec) ~= "table" or type(spec.debug) ~= "table" then
		return nil, "this runner declares no debug block"
	end

	local adapter = spec.debug.adapter
	if type(adapter) ~= "string" or adapter == "" then
		return nil, "debug.adapter is required"
	end

	local request = spec.debug.request or "launch"
	local config = own_fields(spec.debug)
	config.type = adapter
	config.request = request
	config.name = node.display or node.address

	config.cwd = config.cwd or spec.cwd
	if next(spec.env or {}) ~= nil then
		-- The declaration wins: an adapter-specific env in `debug` is more
		-- specific than the runner's process env.
		config.env = vim.tbl_extend("keep", config.env or {}, spec.env)
	end

	if request == "launch" then
		local err = from_command(config, spec, adapter)
		if err then
			return nil, err
		end
	elseif request == "attach" and config.connect == nil and config.processId == nil then
		return nil, 'attach needs connect (or processId) in the debug block'
	end

	return config
end

--- Start the session. `command` of an attach runner is a tunnel, not the
--- debuggee, so it is started by runner.exec before we get here.
--- @return boolean ok, string|nil err
function M.start(node)
	local config, err = M.config_of(node)
	if not config then
		return false, err
	end

	local ok, dap = pcall(require, "dap")
	if not ok then
		return false, "nvim-dap is not installed"
	end
	if dap.adapters[config.type] == nil then
		return false, ("no nvim-dap adapter named %q"):format(config.type)
	end

	dap.run(config, { new = true })
	return true
end

return M
