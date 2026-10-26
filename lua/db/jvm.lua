-- The Java side: compiling the query runner once, and keeping one of it alive
-- per connection.
--
-- Why a long-lived process instead of one per query, which is what the old
-- command line clients did: measured on this machine, a fresh JVM costs 50 ms,
-- but the DuckDB driver unpacks a native library on every start (~2.5 s) and
-- the MongoDB driver boots a JavaScript engine on its first query (~12 s).
-- Alive, those same queries take 1-2 ms and ~110 ms.
--
-- Each connection gets its own process, with only its own driver on the
-- classpath. The MongoDB driver bundles GraalVM; sharing a classpath would
-- slow every other connection down for nothing.
local db = require("db")
local jdbc = require("tools.jdbc")
local jdk = require("tools.jdk")
local tools = require("tools")

local M = {}

M.classes_dir = tools.tools_dir .. "/db-runner"

local processes = {}
local sequence = 0

local function source_dir()
	return vim.fn.stdpath("config") .. "/java"
end

--- Is the compiled runner newer than its source?
local function compiled()
	local marker = M.classes_dir .. "/nvimdb/Runner.class"
	local built = vim.uv.fs_stat(marker)
	if not built then
		return false
	end
	for _, file in ipairs(vim.fn.glob(source_dir() .. "/nvimdb/*.java", true, true)) do
		local source = vim.uv.fs_stat(file)
		if source and source.mtime.sec > built.mtime.sec then
			return false
		end
	end
	return true
end

--- Build the runner. Done once, and again when its source changes, which only
--- happens when this config is updated.
--- @param on_done fun(ok: boolean, err: string|nil)
function M.build(on_done)
	if compiled() then
		return on_done(true, nil)
	end
	local javac = jdk.javac()
	if not javac then
		return on_done(false, "no JDK available")
	end

	vim.fn.mkdir(M.classes_dir, "p")
	local sources = vim.fn.glob(source_dir() .. "/nvimdb/*.java", true, true)
	if #sources == 0 then
		return on_done(false, "the runner source is missing from " .. source_dir())
	end

	local command = { javac, "-d", M.classes_dir }
	vim.list_extend(command, sources)
	db.notify("building the database runner...")
	vim.system(
		command,
		{ text = true },
		vim.schedule_wrap(function(result)
			if result.code ~= 0 then
				return on_done(false, (result.stderr or "javac failed"):gsub("\n", " "))
			end
			on_done(true, nil)
		end)
	)
end

--- Everything the Java side needs, in place.
--- @param on_done fun(ok: boolean, err: string|nil)
function M.ensure(driver, on_done)
	jdk.ensure(function(has_jdk)
		if not has_jdk then
			return on_done(false, "no JDK; the database client cannot run")
		end
		jdbc.ensure(driver, function(jar, err)
			if not jar then
				return on_done(false, err)
			end
			M.build(function(built, build_err)
				on_done(built, build_err)
			end)
		end)
	end)
end

--- @class db.Process
--- @field handle table vim.system handle
--- @field pending table<integer, fun(response: table)>
--- @field ready boolean
--- @field buffer string
--- @field connection table

local function fail_all(process, message)
	for id, callback in pairs(process.pending) do
		process.pending[id] = nil
		callback({ ok = false, message = message })
	end
end

local function handle_line(process, line)
	if line == "" then
		return
	end
	local decoded, response = pcall(vim.json.decode, line)
	if not decoded or type(response) ~= "table" then
		-- A driver that writes to stdout on its own (warnings, banners) would
		-- land here; it is not an answer to anything.
		return
	end

	if response.ready then
		process.ready = true
		process.product = response.product
		process.driver_name = response.driver
		for _, callback in ipairs(process.on_ready) do
			callback(true, nil)
		end
		process.on_ready = {}
		return
	end

	if response.fatal then
		process.fatal = response.message
		for _, callback in ipairs(process.on_ready) do
			callback(false, response.message)
		end
		process.on_ready = {}
		fail_all(process, response.message)
		return
	end

	local callback = process.pending[response.id]
	if callback then
		process.pending[response.id] = nil
		callback(response)
	end
end

local function consume(process, chunk)
	process.buffer = process.buffer .. chunk
	while true do
		local newline = process.buffer:find("\n", 1, true)
		if not newline then
			break
		end
		local line = process.buffer:sub(1, newline - 1)
		process.buffer = process.buffer:sub(newline + 1)
		handle_line(process, (line:gsub("\r$", "")))
	end
end

local function spawn(connection, password, on_ready)
	local jar = jdbc.jar(connection.driver)
	local java = jdk.java()
	if not jar or not java then
		return on_ready(false, "the Java runtime or the driver is missing")
	end

	local separator = require("core.platform").is_windows and ";" or ":"
	local url, url_err = require("db.dsn").build(connection)
	if not url then
		return on_ready(false, url_err)
	end

	local process = {
		pending = {},
		on_ready = { on_ready },
		buffer = "",
		connection = connection,
		started_at = vim.uv.now(),
	}

	local command = {
		java,
		-- A client process does not benefit from the heavy JIT, and this
		-- shaves startup.
		"-XX:TieredStopAtLevel=1",
		"-XX:+UseSerialGC",
		"-Xss4m",
		"-Dfile.encoding=UTF-8",
		"-cp",
		M.classes_dir .. separator .. jar,
		"nvimdb.Runner",
		url,
		connection.user or "",
	}
	for key, value in pairs(connection.options or {}) do
		table.insert(command, ("%s=%s"):format(key, value))
	end

	process.handle = vim.system(command, {
		text = false,
		stdin = true,
		stdout = function(_, data)
			if data then
				vim.schedule(function()
					consume(process, data)
				end)
			end
		end,
		stderr = function(_, data)
			if data and data ~= "" then
				-- Drivers log to stderr; only keep the tail, for :DbDoctor.
				process.stderr = ((process.stderr or "") .. data):sub(-4000)
			end
		end,
	}, function(result)
		vim.schedule(function()
			processes[connection.id] = nil
			local message = process.fatal
				or ("the database process for %s stopped (exit %d)"):format(
					connection.name,
					result.code or -1
				)
			for _, callback in ipairs(process.on_ready) do
				callback(false, message)
			end
			process.on_ready = {}
			fail_all(process, message)
		end)
	end)

	-- The password goes in as the first line of stdin, never in argv.
	process.handle:write(vim.base64.encode(password or "") .. "\n")
	processes[connection.id] = process
	return process
end

--- A live process for this connection, starting one if needed.
--- @param on_ready fun(ok: boolean, err: string|nil)
function M.connect(connection, password, on_ready)
	local process = processes[connection.id]
	if process then
		if process.ready then
			return on_ready(true, nil)
		end
		table.insert(process.on_ready, on_ready)
		return
	end
	spawn(connection, password, on_ready)
end

--- Send one request and get its answer.
--- @param arguments string[] already base64 encoded where needed
--- @param callback fun(response: table)
function M.request(connection, operation, arguments, callback)
	local process = processes[connection.id]
	if not process or not process.ready then
		return callback({ ok = false, message = "not connected" })
	end
	sequence = sequence + 1
	local id = sequence
	process.pending[id] = callback
	local fields = { tostring(id), operation }
	vim.list_extend(fields, arguments or {})
	local ok = pcall(function()
		process.handle:write(table.concat(fields, "\t") .. "\n")
	end)
	if not ok then
		process.pending[id] = nil
		callback({ ok = false, message = "could not write to the database process" })
	end
	return id
end

function M.encode(value)
	return vim.base64.encode(value or "")
end

function M.is_connected(connection_id)
	local process = processes[connection_id]
	return process ~= nil and process.ready == true
end

function M.info(connection_id)
	local process = processes[connection_id]
	if not process then
		return nil
	end
	return {
		product = process.product,
		driver = process.driver_name,
		stderr = process.stderr,
		pid = process.handle and process.handle.pid or nil,
	}
end

--- Stop the process for a connection, or all of them.
function M.stop(connection_id)
	local function close(id, process)
		processes[id] = nil
		pcall(function()
			process.handle:write("0\tclose\n")
		end)
		-- Give it a moment to close the connection cleanly, then make sure.
		vim.defer_fn(function()
			pcall(function()
				process.handle:kill("sigterm")
			end)
		end, 500)
	end

	if connection_id then
		local process = processes[connection_id]
		if process then
			close(connection_id, process)
		end
		return
	end
	-- The keys are copied, not the table: a process holds a libuv handle,
	-- which deepcopy cannot touch.
	local ids = vim.tbl_keys(processes)
	for _, id in ipairs(ids) do
		local process = processes[id]
		if process then
			close(id, process)
		end
	end
end

function M.active()
	return vim.tbl_keys(processes)
end

return M
