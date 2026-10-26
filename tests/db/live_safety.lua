-- The things that must not happen: a password in the process table, a
-- validation that changes data, a write on a read-only connection.
local support = require("tests.db.support")
local check, note = support.check, support.note

local connections = support.connections()
local pg = connections.postgres
local ms = connections.mssql

support.describe("live/safety: the password never reaches the process table")
if not support.reachable(pg) then
	note("skipped: nothing listening (tests/db/containers.sh up)")
else
	local runner = require("db.runner")
	local jvm = require("db.jvm")
	local finished = false
	runner.run({ connection = pg, sql = "select pg_sleep(3), 1 as a", mode = "query", limit = 1 }, function()
		finished = true
	end)
	-- Look at the process table while the query is actually running.
	vim.wait(1500, function()
		return false
	end, 100)

	local pid = (jvm.info(pg.id) or {}).pid
	check("the database process is running", pid ~= nil, true)

	-- By pid, not by pattern: this must look at exactly the process we
	-- started, and nothing else that happens to mention it.
	local password = vim.env.NVIM_DB_TEST_PW or support.PASSWORD
	local command_line = pid and vim.fn.system({ "ps", "-o", "command=", "-p", tostring(pid) }) or ""
	note(("argv: %s"):format(vim.trim(command_line):sub(1, 90)))
	check("its command line holds no password", command_line:find(password, 1, true), nil)
	check("nor the url-encoded form", command_line:find(require("db.dsn").encode(password), 1, true), nil)
	check("and it really is the runner", command_line:find("nvimdb.Runner", 1, true) ~= nil, true)

	support.wait(function()
		return finished
	end)
end

support.describe("live/safety: the password is not even in the URL")
local dsn = require("db.dsn")
local url = dsn.build(pg)
-- The JDBC URL is built without it: the Java process reads the password from
-- the first line of its stdin, so there is no string to leak in the first
-- place. Redaction stays as a guard for whatever a server echoes back.
check("the url has no password", url:find(vim.env.NVIM_DB_TEST_PW or support.PASSWORD, 1, true), nil)
check(
	"redacting a password that appears in a message",
	dsn.redact("failed: pw=hunter2", "hunter2"):find("hunter2", 1, true),
	nil
)
check(
	"redacting without knowing it",
	dsn.redact("postgres://user:whatever@host:5432/db"),
	"postgres://user:***@host:5432/db"
)

support.describe("live/safety: the keyring round trip")
local keyring = require("db.secrets").keyring()
if not keyring.available() then
	note("skipped: no OS keyring here")
else
	local secret = 's3cr3t:with/specials#1 and "quotes" and \\backslash'
	local stored, set_err = support.sync(function(done)
		keyring.set("nvim-db-selftest", secret, function(ok, err)
			done(ok, err)
		end)
	end)
	check("stored", stored, true)
	if set_err then
		note(tostring(set_err))
	end

	local read = support.sync(function(done)
		keyring.get("nvim-db-selftest", function(value, err)
			done(value, err)
		end)
	end)
	check("read back exactly", read, secret)

	support.sync(function(done)
		keyring.delete("nvim-db-selftest", function(ok)
			done(ok)
		end)
	end)
	local gone, gone_err = support.sync(function(done)
		keyring.get("nvim-db-selftest", function(value, err)
			done(value, err)
		end)
	end)
	check("a missing secret is absent", gone, nil)
	check("and not an error", gone_err, nil)
end

support.describe("live/safety: validating must not change anything")
if not support.reachable(pg) then
	note("skipped")
else
	local before = support.scalar(pg, "select count(*) from torture")
	check("rows before", before, 2)

	-- Each of these is sent to the server exactly as written. Preparing it
	-- parses and resolves it; none of it runs.
	for _, sql in ipairs({
		"delete from torture",
		"drop table torture",
		"insert into torture(id) values (99)",
		"update torture set s_comma = 'x'",
		"truncate torture",
	}) do
		local _, err = support.run(pg, sql, { mode = "validate" })
		note(("%-40s -> %s"):format(sql, err and err.message:sub(1, 40) or "accepted"))
	end

	check(
		"rows after validating five destructive statements",
		support.scalar(pg, "select count(*) from torture"),
		before
	)
	check(
		"the table is still there",
		support.scalar(pg, "select count(*) from information_schema.tables where table_name = 'torture'"),
		1
	)
	check(
		"and its values are untouched",
		support.scalar(pg, "select count(*) from torture where s_comma = 'a,b'"),
		1
	)
end

support.describe("live/safety: sql server too, with no special case")
local ms_reachable = support.reachable(ms)
if ms_reachable then
	local before = support.scalar(ms, "select count(*) from dbo.torture")
	for _, sql in ipairs({ "delete from dbo.torture", "drop table dbo.torture" }) do
		local _, err = support.run(ms, sql, { mode = "validate" })
		note(("%-30s -> %s"):format(sql, err and err.message:sub(1, 40) or "accepted"))
	end
	-- The old path had to run SQL Server writes inside a rolled-back
	-- transaction, because SET NOEXEC did not survive to the next statement
	-- and a "validated" insert went through for real. Preparing has no such
	-- problem, so there is no opt-in flag any more.
	check("the rows are still there", support.scalar(ms, "select count(*) from dbo.torture"), before)
else
	note("sql server skipped")
end

support.describe("live/safety: a read-only connection refuses a write")
if not support.reachable(pg) then
	note("skipped")
else
	local readonly = vim.tbl_extend("force", pg, { id = "test-pg-ro", name = "read only", readonly = true })
	local connections_module = require("db.connections")
	local saved_get = connections_module.get
	connections_module.get = function(id)
		if id == readonly.id then
			return readonly
		end
		return saved_get(id)
	end

	local bufnr = vim.api.nvim_create_buf(false, true)
	vim.bo[bufnr].filetype = "sql"
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "delete from torture where id = 1;" })
	vim.api.nvim_set_current_buf(bufnr)
	require("db.resolve").bind(bufnr, readonly.id)

	local messages = {}
	local original = vim.notify
	vim.notify = function(message)
		messages[#messages + 1] = message
	end
	require("db.execute").run({ bufnr = bufnr })
	vim.wait(1500, function()
		return #messages > 0
	end, 50)
	vim.notify = original

	local refused = false
	for _, message in ipairs(messages) do
		if message:find("read%-only") then
			refused = true
		end
	end
	check("it says no", refused, true)
	check("and nothing was deleted", support.scalar(pg, "select count(*) from torture"), 2)
	connections_module.get = saved_get
end

support.describe("live/safety: an unguarded write asks for the connection name")
if support.reachable(pg) then
	local bufnr = vim.api.nvim_create_buf(false, true)
	vim.bo[bufnr].filetype = "sql"
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "delete from torture;" })
	vim.api.nvim_set_current_buf(bufnr)
	local writable = vim.tbl_extend("force", pg, { id = "test-pg-rw", name = "writable" })
	local connections_module = require("db.connections")
	local saved_get = connections_module.get
	connections_module.get = function(id)
		return id == writable.id and writable or saved_get(id)
	end
	require("db.resolve").bind(bufnr, writable.id)

	local prompt = nil
	local original_input = vim.ui.input
	vim.ui.input = function(opts, on_confirm)
		prompt = opts.prompt
		-- Answer wrongly: the statement must not run.
		on_confirm("not the name")
	end
	require("db.execute").run({ bufnr = bufnr })
	vim.wait(1500, function()
		return prompt ~= nil
	end, 50)
	vim.ui.input = original_input

	check("it asks", prompt ~= nil and prompt:find("Type the connection name") ~= nil, true)
	check("a wrong answer runs nothing", support.scalar(pg, "select count(*) from torture"), 2)
	connections_module.get = saved_get
else
	note("skipped")
end
