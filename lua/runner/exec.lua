-- Processes: starting a runner that is not a debug session, and deciding when
-- it is ready. Nothing here knows about plans or waves — runner.run owns the
-- order, this module owns one process at a time.
local M = {}

local POLL_MS = 200

--- address -> { id, output, exited, code }
M.jobs = {}

local function remember(address, job)
	M.jobs[address] = job
end

function M.running(address)
	local job = M.jobs[address]
	return job ~= nil and not job.exited
end

local function collect(job)
	return function(_, lines)
		for _, line in ipairs(lines or {}) do
			if line ~= "" then
				job.output[#job.output + 1] = line
			end
		end
	end
end

--- Start the process. The caller decides what "ready" means afterwards.
--- @return table|nil job, string|nil err
function M.start(node)
	local spec = node.spec
	if type(spec.command) ~= "table" or #spec.command == 0 then
		return nil, "this runner declares no command"
	end
	if spec.singleton and M.running(node.address) then
		return M.jobs[node.address]
	end

	local job = { output = {}, exited = false }
	local id = vim.fn.jobstart(spec.command, {
		cwd = spec.cwd,
		env = next(spec.env or {}) ~= nil and spec.env or nil,
		stdout_buffered = false,
		stderr_buffered = false,
		on_stdout = collect(job),
		on_stderr = collect(job),
		on_exit = function(_, code)
			job.exited, job.code = true, code
		end,
	})

	if id <= 0 then
		return nil, ("cannot start %s"):format(spec.command[1])
	end

	job.id = id
	remember(node.address, job)
	return job
end

function M.stop(address)
	local job = M.jobs[address]
	if job and not job.exited then
		pcall(vim.fn.jobstop, job.id)
	end
	M.jobs[address] = nil
end

function M.stop_all()
	for address in pairs(vim.deepcopy(M.jobs)) do
		M.stop(address)
	end
end

-- ------------------------------------------------------------------ probes
local function port_open(port, done)
	local client = vim.uv.new_tcp()
	if not client then
		return done(false)
	end
	client:connect("127.0.0.1", port, function(err)
		client:close()
		vim.schedule(function()
			done(err == nil)
		end)
	end)
end

local function http_answers(url, wanted, done)
	vim.system(
		{ "curl", "-sS", "-o", vim.fn.has("win32") == 1 and "NUL" or "/dev/null", "-w", "%{http_code}", url },
		{ text = true },
		function(result)
			local status = tonumber(vim.trim(result.stdout or "")) or 0
			local ok = wanted and status == wanted or (not wanted and status >= 100 and status < 400)
			vim.schedule(function()
				done(ok)
			end)
		end
	)
end

local function log_matched(job, pattern)
	for _, line in ipairs(job.output) do
		if line:match(pattern) then
			return true
		end
	end
	return false
end

--- One probe for the signal this runner declares.
--- @return function|nil probe(done)
local function probe_of(ready, job)
	if ready.port then
		return function(done)
			port_open(ready.port, done)
		end
	end
	if ready.http then
		return function(done)
			http_answers(ready.http, ready.status, done)
		end
	end
	if ready.log then
		return function(done)
			done(log_matched(job, ready.log))
		end
	end
	return nil
end

--- Poll `probe` until it says yes, the process dies, or the timeout runs out.
local function poll(probe, job, deadline, done)
	if job and job.exited then
		return done(false, ("the process exited with code %d"):format(job.code or 0))
	end
	probe(function(ok)
		if ok then
			return done(true)
		end
		if vim.uv.now() >= deadline then
			return done(false, "timed out waiting for it to be ready")
		end
		vim.defer_fn(function()
			poll(probe, job, deadline, done)
		end, POLL_MS)
	end)
end

--- Wait until the node's `ready` signal fires. No signal means "started is ready".
--- @param done function(ok, err)
function M.wait_ready(node, done)
	local ready = node.spec.ready
	if type(ready) ~= "table" then
		return done(true)
	end

	local job = M.jobs[node.address]
	if ready.delay then
		return vim.defer_fn(function()
			done(true)
		end, ready.delay)
	end

	local probe = probe_of(ready, job)
	if not probe then
		return done(true)
	end

	vim.uv.update_time()
	poll(probe, job, vim.uv.now() + (ready.timeout or 60000), done)
end

return M
