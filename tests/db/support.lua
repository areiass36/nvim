-- Shared scaffolding for the database tests.
local M = {}

M.failures = 0
M.checks = 0
local current = "?"

function M.describe(name)
	current = name
	io.write(("\n== %s\n"):format(name))
end

function M.check(name, got, want)
	M.checks = M.checks + 1
	local ok = vim.deep_equal(got, want)
	if not ok then
		M.failures = M.failures + 1
		io.write(
			("FAIL %s / %s\n  got:  %s\n  want: %s\n"):format(
				current,
				name,
				vim.inspect(got),
				vim.inspect(want)
			)
		)
	else
		io.write(("ok   %s\n"):format(name))
	end
	return ok
end

function M.fail(name, detail)
	M.checks = M.checks + 1
	M.failures = M.failures + 1
	io.write(("FAIL %s / %s\n  %s\n"):format(current, name, detail))
end

function M.note(text)
	io.write(("     %s\n"):format(text))
end

--- Block until `fn` is true, the way a test has to when the module under test
--- is callback-based.
function M.wait(fn, timeout)
	return vim.wait(timeout or 60000, fn, 50)
end

--- Run a callback-based function to completion.
--- @return any... whatever the callback was given
function M.sync(starter, timeout)
	local done, captured = false, nil
	starter(function(...)
		captured = { ... }
		done = true
	end)
	if not M.wait(function()
		return done
	end, timeout) then
		return nil, "timed out"
	end
	return unpack(captured or {})
end

M.PASSWORD = "p@ss:w/rd#1"
M.MSSQL_PASSWORD = "Str0ng:P/ss#1"

--- The connections the live tests use. Ports match tests/db/containers.sh.
function M.connections()
	return {
		postgres = {
			id = "test-pg",
			name = "test pg",
			driver = "postgres",
			host = "127.0.0.1",
			port = 15432,
			database = "testdb",
			user = "testuser",
			password_source = { kind = "env", var = "NVIM_DB_TEST_PW" },
			options = {},
			client = "auto",
		},
		mysql = {
			id = "test-my",
			name = "test mysql",
			driver = "mysql",
			host = "127.0.0.1",
			port = 13306,
			database = "testdb",
			user = "root",
			password_source = { kind = "env", var = "NVIM_DB_TEST_PW" },
			options = {},
			client = "auto",
		},
		mssql = {
			id = "test-ms",
			name = "test mssql",
			driver = "mssql",
			host = "127.0.0.1",
			port = 11433,
			database = "master",
			user = "sa",
			password_source = { kind = "env", var = "NVIM_DB_TEST_MSSQL_PW" },
			options = {},
			client = "auto",
			default_schema = "dbo",
		},
		sqlite = {
			id = "test-lite",
			name = "test sqlite",
			driver = "sqlite",
			file = "/tmp/nvdbtest.sqlite",
			password_source = { kind = "none" },
			options = {},
			client = "auto",
		},
		duckdb = {
			id = "test-duck",
			name = "test duckdb",
			driver = "duckdb",
			file = "/tmp/nvdbtest.duckdb",
			password_source = { kind = "none" },
			options = {},
			client = "auto",
		},
		mongodb = {
			id = "test-mongo",
			name = "test mongo",
			driver = "mongodb",
			host = "127.0.0.1",
			port = 17017,
			database = "shop",
			user = "root",
			password_source = { kind = "env", var = "NVIM_DB_TEST_PW" },
			options = {},
			client = "auto",
		},
	}
end

--- Is this server answering? The live tests skip rather than fail when the
--- containers are not up, so the unit tests still run anywhere.
function M.reachable(connection)
	if connection.file then
		return vim.fn.filereadable(connection.file) == 1
	end
	local socket = vim.uv.new_tcp()
	local connected = false
	socket:connect(connection.host, connection.port, function(err)
		connected = err == nil
		socket:close()
	end)
	vim.wait(2000, function()
		return socket:is_closing()
	end, 20)
	return connected
end

function M.run(connection, sql, opts)
	opts = opts or {}
	local request = vim.tbl_extend("force", {
		connection = connection,
		sql = sql,
		mode = "rows",
		limit = opts.limit or 0,
	}, opts)
	return M.sync(function(done)
		require("db.runner").run(request, function(result, err)
			done(result, err)
		end)
	end, opts.timeout)
end

--- First cell of the first row, as a number when it looks like one.
function M.scalar(connection, sql)
	local result, err = M.run(connection, sql)
	if err then
		return nil, err.message
	end
	local value = result.rows[1] and result.rows[1][1]
	return tonumber(value) or value
end

return M
