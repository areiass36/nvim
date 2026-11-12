-- Running a plan: wave by wave, every runner in a wave started together and
-- waited for before the next wave begins. What to start comes from
-- runner.resolve; how to start it is runner.exec (a process) or runner.dap (a
-- debug session).
local M = {}

local function notify(message, level)
	vim.notify("[runner] " .. message, level or vim.log.levels.INFO)
end

local function wait_ready(node, done)
	require("runner.exec").wait_ready(node, function(ok, err)
		done(ok, err)
	end)
end

--- A launch: the debug adapter owns the process, so there is nothing to spawn.
local function start_launch(node, done)
	local ok, err = require("runner.dap").start(node)
	if not ok then
		return done(false, err)
	end
	wait_ready(node, done)
end

--- A process: a plain runner, or the tunnel an attach needs. The attach follows
--- once the `ready` signal fires.
local function start_process(node, done)
	local exec = require("runner.exec")
	local job, err = exec.start(node)
	if not job then
		return done(false, err)
	end

	wait_ready(node, function(ok, ready_err)
		if not ok then
			return done(false, ready_err)
		end
		if node.spec.debug then
			local started, dap_err = require("runner.dap").start(node)
			return done(started, dap_err)
		end
		done(true)
	end)
end

local function start(node, done)
	local spec = node.spec
	local request = spec.debug and (spec.debug.request or "launch") or nil

	if request == "launch" then
		return start_launch(node, done)
	end
	if spec.command then
		return start_process(node, done)
	end
	if spec.debug then
		local ok, err = require("runner.dap").start(node)
		return done(ok, err)
	end
	done(false, "nothing to run")
end

local function skip(node)
	local exec = require("runner.exec")
	return node.spec.singleton and exec.running(node.address)
end

--- Start every node of a wave, then report once the slowest one is ready.
local function run_wave(wave, done)
	local left, failed = #wave, nil

	for _, node in ipairs(wave) do
		if skip(node) then
			notify(("%s already running"):format(node.display))
			left = left - 1
			if left == 0 then
				done(failed == nil, failed)
			end
		else
			notify(("starting %s"):format(node.display))
			start(node, function(ok, err)
				if not ok then
					failed = failed or ("%s: %s"):format(node.display, err or "failed to start")
				end
				left = left - 1
				if left == 0 then
					done(failed == nil, failed)
				end
			end)
		end
	end

	if #wave == 0 then
		done(true)
	end
end

local function run_waves(waves, index, done)
	if index > #waves then
		return done(true)
	end
	run_wave(waves[index], function(ok, err)
		if not ok then
			return done(false, err)
		end
		run_waves(waves, index + 1, done)
	end)
end

--- Run an address (or the workspace default).
--- @param target string|table|nil
function M.run(target, bufnr)
	local plan, err = require("runner").plan(target, bufnr)
	if not plan then
		return notify(err, vim.log.levels.WARN)
	end
	if #plan.errors > 0 then
		local schema = require("runner.schema")
		return notify(schema.format(plan.errors[1]), vim.log.levels.ERROR)
	end

	for _, node in ipairs(plan.skipped) do
		notify(("skipping %s — %s"):format(node.display, node.skipped))
	end

	run_waves(plan.waves, 1, function(ok, failure)
		if not ok then
			return notify(failure, vim.log.levels.ERROR)
		end
		notify(("%s is up"):format(plan.entry))
	end)
end

--- Stop the processes the runner started. Debug sessions are the debugger's to
--- end (<leader>dx), so they are left alone.
function M.stop()
	local exec = require("runner.exec")
	local count = vim.tbl_count(exec.jobs)
	exec.stop_all()
	notify(count == 0 and "no processes to stop" or ("stopped %d process(es)"):format(count))
end

return M
