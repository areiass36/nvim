-- Running one statement, through the Java process that owns the connection.
--
-- The process is started on first use and kept (lua/db/jvm.lua), so this layer
-- only has to queue requests, apply timeouts and translate the answer. The
-- heavy lifting that used to live here -- paging by rewriting SQL, converting
-- types, telling NULL from an empty string -- is done on the Java side now,
-- where JDBC reports the type of every column.
local db = require("db")
local errors = require("db.errors")
local jvm = require("db.jvm")
local config = require("db.config")
local secrets = require("db.secrets")

local M = {}

local queues = {}
local running = {}
local sequence = 0

local function finish(handle, result, err)
	if handle.done then
		return
	end
	handle.done = true
	running[handle.id] = nil
	local queue = queues[handle.connection_id]
	if queue then
		queue.active = false
		M._pump(handle.connection_id)
	end
	handle.callback(result, err)
end

--- Turn the runner's JSON answer into what the rest of the module expects.
local function translate(handle, response)
	local request = handle.request
	if not response.ok then
		return finish(handle, nil, errors.from_response(response, { password = request.password }))
	end

	local columns, types = {}, {}
	for index, column in ipairs(response.columns or {}) do
		columns[index] = column.name
		types[index] = column.type
	end

	local rows = {}
	for _, source in ipairs(response.rows or {}) do
		local row = {}
		for index = 1, #columns do
			local value = source[index]
			-- vim.json.decode turns JSON null into vim.NIL; the grid wants the
			-- sentinel, which is distinct from the empty string.
			row[index] = (value == nil or value == vim.NIL) and db.NULL or value
		end
		rows[#rows + 1] = row
	end

	finish(handle, {
		columns = columns,
		column_types = types,
		rows = rows,
		has_more = response.hasMore == true,
		elapsed_ms = response.elapsedMs,
		update_count = response.updateCount,
		connection = request.connection,
		sql = request.sql,
		limit = request.limit,
		offset = request.offset or 0,
	}, nil)
end

local function dispatch(handle)
	local request = handle.request
	local connection = request.connection
	local timeout_seconds = math.ceil((request.timeout_ms or config.get().timeout_ms) / 1000)

	local operation, arguments
	if request.mode == "validate" then
		operation, arguments = "validate", { jvm.encode(request.sql) }
	elseif request.mode == "exec" then
		operation, arguments = "exec", { jvm.encode(request.sql) }
	elseif request.mode == "export" then
		operation = "export"
		arguments =
			{ jvm.encode(request.sql), jvm.encode(request.out_file), jvm.encode(request.null_marker or "") }
	else
		operation = "query"
		arguments = {
			jvm.encode(request.sql),
			tostring(request.limit or 0),
			tostring(request.offset or 0),
			tostring(timeout_seconds),
		}
	end

	handle.request_id = jvm.request(connection, operation, arguments, function(response)
		vim.schedule(function()
			if handle.cancelled then
				return finish(handle, nil, { message = "cancelled", cancelled = true })
			end
			translate(handle, response)
		end)
	end)

	-- The server-side timeout is the real one; this only catches a process
	-- that stopped answering.
	handle.timer = vim.defer_fn(function()
		if not handle.done then
			db.notify("the database process stopped answering; restarting it", vim.log.levels.WARN)
			jvm.stop(connection.id)
			finish(handle, nil, { message = "timed out waiting for the database process" })
		end
	end, (request.timeout_ms or config.get().timeout_ms) + 10000)
end

function M._pump(connection_id)
	local queue = queues[connection_id]
	if not queue or queue.active then
		return
	end
	local handle = table.remove(queue.waiting, 1)
	if not handle then
		return
	end
	queue.active = true
	dispatch(handle)
end

local function enqueue(handle)
	local id = handle.connection_id
	queues[id] = queues[id] or { waiting = {}, active = false }
	-- A catalog lookup waits behind the user's own query.
	if handle.request.background then
		table.insert(queues[id].waiting, handle)
	else
		local index = 1
		for position, waiting in ipairs(queues[id].waiting) do
			if waiting.request.background then
				break
			end
			index = position + 1
		end
		table.insert(queues[id].waiting, index, handle)
	end
	M._pump(id)
end

--- @param request table { connection, sql, mode, limit, offset, timeout_ms, background, out_file }
--- @param callback fun(result: table|nil, err: table|nil)
--- @return table handle
function M.run(request, callback)
	sequence = sequence + 1
	local handle = {
		id = sequence,
		connection_id = request.connection.id,
		request = request,
		callback = callback,
	}
	running[handle.id] = handle

	local connection = request.connection
	request.timeout_ms = request.timeout_ms or connection.timeout_ms or config.get().timeout_ms

	if jvm.is_connected(connection.id) then
		enqueue(handle)
		return handle
	end

	jvm.ensure(connection.driver, function(ready, err)
		if not ready then
			return finish(handle, nil, { message = err })
		end
		secrets.resolve(connection, function(password, secret_err)
			if secret_err then
				return finish(handle, nil, { message = secret_err })
			end
			request.password = password
			jvm.connect(connection, password, function(connected, connect_err)
				if not connected then
					return finish(handle, nil, errors.from_message(connect_err, { password = password }))
				end
				enqueue(handle)
			end)
		end)
	end)

	return handle
end

--- Ask the server to stop. Unlike killing a client process, this reaches the
--- database: JDBC's Statement.cancel sends a real cancellation request.
function M.cancel(handle)
	if not handle or handle.done then
		return false
	end
	handle.cancelled = true
	local connection = handle.request.connection
	if jvm.is_connected(connection.id) then
		jvm.request(connection, "cancel", {}, function() end)
	end
	finish(handle, nil, { message = "cancelled", cancelled = true })
	return true
end

function M.cancel_all()
	-- Copy the keys rather than the table: a handle holds a timer.
	local ids = vim.tbl_keys(running)
	for _, id in ipairs(ids) do
		local handle = running[id]
		if handle then
			M.cancel(handle)
		end
	end
end

--- @return table[] handles running or queued
function M.active()
	local list = {}
	for _, handle in pairs(running) do
		list[#list + 1] = handle
	end
	return list
end

function M.setup()
	vim.api.nvim_create_autocmd("VimLeavePre", {
		group = vim.api.nvim_create_augroup("DbRunner", { clear = true }),
		callback = function()
			M.cancel_all()
			jvm.stop()
		end,
	})
end

return M
