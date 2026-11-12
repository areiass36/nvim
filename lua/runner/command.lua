-- User commands. Registered by runner.setup(); everything they touch is
-- required inside the callbacks, so opening nvim costs nothing.
local M = {}

local function notify(message, level)
	vim.notify("[runner] " .. message, level or vim.log.levels.INFO)
end

local function check()
	require("runner").reload()
	local workspace, err = require("runner").check()
	if not workspace then
		return notify(err, vim.log.levels.WARN)
	end
	local ui = require("runner.ui")
	ui.show(ui.check_lines(workspace), ":RunnerCheck")
end

local function plan(opts)
	require("runner").reload()
	local result, err = require("runner").plan(opts.args)
	if not result then
		return notify(err, vim.log.levels.WARN)
	end
	local ui = require("runner.ui")
	ui.show(ui.plan_lines(result), ":RunnerPlan " .. (opts.args ~= "" and opts.args or "(default)"))
end

local function complete(lead)
	return vim.tbl_filter(function(candidate)
		return vim.startswith(candidate, lead)
	end, require("runner").addresses())
end

local function run(opts)
	require("runner").reload()
	require("runner.run").run(opts.args ~= "" and opts.args or nil)
end

local function stop()
	require("runner.run").stop()
end

function M.setup()
	vim.api.nvim_create_user_command("RunnerCheck", check, {
		desc = "Validate the .nvim/workspace.json above this buffer",
	})
	vim.api.nvim_create_user_command("RunnerPlan", plan, {
		nargs = "?",
		complete = complete,
		desc = "Show what running an address would start, in order",
	})
	vim.api.nvim_create_user_command("RunnerRun", run, {
		nargs = "?",
		complete = complete,
		desc = "Start an address: processes with jobstart, debug runners with nvim-dap",
	})
	vim.api.nvim_create_user_command("RunnerStop", stop, {
		desc = "Stop the processes the runner started",
	})
end

return M
