-- Walking the schema explorer, level by level, and the three actions on an
-- entry. The levels are driven directly rather than through keystrokes: what is
-- worth testing is the tree and what each action produces, not Telescope.
local support = require("tests.db.support")
local check, note = support.check, support.note
local explorer = require("db.explorer")

local connections = support.connections()
local pg = connections.postgres

support.describe("explorer: the tree")
if not support.reachable(pg) then
	note("skipped: nothing listening (tests/db/containers.sh up)")
	return
end

local connections_module = require("db.connections")
local saved_all, saved_get = connections_module.all, connections_module.get
connections_module.all = function()
	return { pg, connections.duckdb, connections.mongodb }
end
connections_module.get = function(id)
	for _, connection in pairs(connections) do
		if connection.id == id then
			return connection
		end
	end
	return saved_get(id)
end

local function load(level, context)
	local entries, err = support.sync(function(done)
		explorer.levels[level].load(context, function(list, error_)
			done(list, error_)
		end)
	end)
	return entries, err
end

local function entry_named(entries, name)
	for _, entry in ipairs(entries or {}) do
		if tostring(entry.value) == name or (type(entry.value) == "table" and entry.value.id == name) then
			return entry
		end
	end
	return nil
end

-- connections
local level, context = "connections", {}
local entries, err = load(level, context)
check("connections are listed", err, nil)
check("three of them", #entries, 3)
local entry = entry_named(entries, pg.id)
check("the test connection is there", entry ~= nil, true)
check("with its driver as a hint", entry.hint:find("postgres") ~= nil, true)

-- connections -> databases
local child = explorer.levels[level].child(context, entry)
check("a server connection leads to databases", child.level, "databases")
level, context = child.level, child.context
entries, err = load(level, context)
check("databases load", err, nil)
check("testdb is listed", entry_named(entries, "testdb") ~= nil, true)

-- databases -> schemas
entry = entry_named(entries, "testdb")
child = explorer.levels[level].child(context, entry)
check("postgres has a schema level", child.level, "schemas")
check("and the database is carried into it", child.context.connection.database, "testdb")
level, context = child.level, child.context
entries, err = load(level, context)
check("schemas load", err, nil)
check("public is listed", entry_named(entries, "public") ~= nil, true)

-- schemas -> tables
entry = entry_named(entries, "public")
child = explorer.levels[level].child(context, entry)
check("then tables", child.level, "tables")
level, context = child.level, child.context
entries, err = load(level, context)
check("tables load", err, nil)
entry = entry_named(entries, "torture")
check("torture is listed", entry ~= nil, true)
check("its kind is known", entry.kind, "table")

-- tables -> columns
child = explorer.levels[level].child(context, entry)
check("then columns", child.level, "columns")
check("the table is carried into it", child.context.table, "torture")
local table_context, table_entry = context, entry
local column_entries = load(child.level, child.context)
check("columns load", #column_entries > 0, true)
local id_column = entry_named(column_entries, "id")
check("the primary key is flagged in the hint", id_column.hint:find("PK") ~= nil, true)
local numeric_column = entry_named(column_entries, "n")
check("the type is in the hint", numeric_column.hint:find("numeric") ~= nil, true)
check("columns are the deepest level", explorer.levels.columns.child(child.context, id_column), nil)

support.describe("explorer: sqlite and mongo skip the levels they do not have")
local sqlite_entry = { value = connections.sqlite }
check("sqlite goes straight to tables", explorer.levels.connections.child({}, sqlite_entry).level, "tables")
local mongo_entry = { value = connections.mongodb }
check("mongo starts at databases", explorer.levels.connections.child({}, mongo_entry).level, "databases")
check(
	"and a mongo database leads to collections",
	explorer.levels.databases.child({ connection = connections.mongodb }, { value = "shop" }).level,
	"tables"
)

support.describe("explorer: the name an entry contributes")
check(
	"a table is schema-qualified and quoted",
	explorer.qualified_name("tables", table_context, table_entry),
	'"public"."torture"'
)
check("a column is just quoted", explorer.qualified_name("columns", child.context, id_column), '"id"')
check(
	"sql server uses brackets",
	explorer.qualified_name(
		"tables",
		{ connection = connections.mssql, schema = "dbo" },
		{ value = "torture" }
	),
	"[dbo].[torture]"
)
check(
	"mysql uses backticks",
	explorer.qualified_name(
		"tables",
		{ connection = connections.mysql, schema = "testdb" },
		{ value = "torture" }
	),
	"`testdb`.`torture`"
)

support.describe("explorer: <C-s> opens a runnable select")
local query_buf, query_text = support.sync(function(done)
	explorer.open_select(table_context, table_entry, function(bufnr, text)
		done(bufnr, text)
	end)
end)
check("a buffer was opened", query_buf ~= nil, true)
check("it is a sql buffer", vim.bo[query_buf].filetype, "sql")
check("bound to the right connection", require("db.resolve").for_buf(query_buf).id, pg.id)
note("select: " .. tostring(query_text))
check("the statement is limited", query_text:find("LIMIT") ~= nil, true)
check("and selects every column", query_text:find("SELECT %*") ~= nil, true)
local result, run_err = support.run(pg, (query_text:gsub(";%s*$", "")), { limit = 10 })
check("and it runs", run_err, nil)
check("returning rows", #result.rows, 2)

support.describe("explorer: <C-y> writes into the buffer it was opened from")
local origin = vim.api.nvim_create_buf(false, true)
vim.bo[origin].filetype = "sql"
vim.api.nvim_buf_set_lines(origin, 0, -1, false, { "select * from " })
vim.api.nvim_set_current_buf(origin)
local origin_win = vim.api.nvim_get_current_win()
vim.api.nvim_win_set_cursor(origin_win, { 1, 14 })
explorer.insert_name(origin_win, origin, '"public"."torture"')
check(
	"the name lands in the original buffer",
	vim.api.nvim_buf_get_lines(origin, 0, 1, false)[1],
	'select * from "public"."torture"'
)

-- And when that window is showing something else by then, the buffer still gets
-- the text and the other buffer stays untouched.
local other = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(other)
explorer.insert_name(origin_win, origin, " x")
check(
	"still the original buffer",
	vim.api.nvim_buf_get_lines(origin, 0, 1, false)[1]:find(" x$") ~= nil,
	true
)
check("and the other buffer is untouched", vim.api.nvim_buf_get_lines(other, 0, -1, false), { "" })

support.describe("explorer: <C-d> shows a definition")
local ddl_lines = support.sync(function(done)
	explorer.show_ddl(table_context, table_entry, function(lines)
		done(lines)
	end)
end)
check("something was rendered", #ddl_lines > 0, true)
local joined = table.concat(ddl_lines, "\n")
check("naming the columns", joined:find("s_comma") ~= nil, true)
check("and the primary key", joined:find("PRIMARY KEY") ~= nil, true)
note("ddl first line: " .. tostring(ddl_lines[1]))
vim.cmd("close")

support.describe("explorer: the previewer's contents")
local preview = require("db.explorer.preview")
local preview_buf = vim.api.nvim_create_buf(false, true)

local connection_lines = support.sync(function(done)
	preview.render("connections", {}, { value = pg }, preview_buf, done)
end)
local connection_text = table.concat(connection_lines, "\n")
check("a connection shows where it points", connection_text:find("127.0.0.1") ~= nil, true)
check("and which driver will run it", connection_text:find("driver") ~= nil, true)
check("and how its password is found", connection_text:find("env") ~= nil, true)
check(
	"but never the password itself",
	connection_text:find(vim.env.NVIM_DB_TEST_PW or support.PASSWORD, 1, true),
	nil
)

local table_lines = support.sync(function(done)
	preview.render("tables", table_context, table_entry, preview_buf, done)
end, 30000)
local table_text = table.concat(table_lines, "\n")
check("a table shows its columns", table_text:find("s_comma") ~= nil, true)
check("with types", table_text:find("numeric") ~= nil, true)
check("the primary key marked", table_text:find("PK") ~= nil, true)
check("and a sample of rows", table_text:find("sample") ~= nil, true)
check("with real values in it", table_text:find("a,b", 1, true) ~= nil, true)
note("preview tail: " .. tostring(table_lines[#table_lines]))

local column_lines = support.sync(function(done)
	preview.render("columns", child.context, numeric_column, preview_buf, done)
end)
check("a column shows its type", table.concat(column_lines, "\n"):find("numeric%(10,2%)") ~= nil, true)

connections_module.all, connections_module.get = saved_all, saved_get
