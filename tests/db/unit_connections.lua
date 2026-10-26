-- Reading the connection files and deciding which one a buffer uses. Needs no
-- server: it writes a throwaway project in a temp directory.
local support = require("tests.db.support")
local check = support.check

local root = vim.fn.tempname()
vim.fn.mkdir(root .. "/.nvim", "p")
vim.fn.mkdir(root .. "/reports", "p")
vim.fn.mkdir(root .. "/db/migrations", "p")
vim.fn.system({ "git", "init", "-q", root })
vim.fn.writefile({ ".nvim/" }, root .. "/.gitignore")
vim.fn.writefile({
	vim.json.encode({
		version = 1,
		default = "local-pg",
		connections = {
			{
				id = "local-pg",
				name = "Local PG",
				driver = "postgresql",
				host = "127.0.0.1",
				port = 15432,
				database = "testdb",
				user = "testuser",
				password_env = "PGPASSWORD_TEST",
			},
			{
				id = "warehouse",
				name = "Warehouse",
				driver = "sqlserver",
				host = "sql.example.com",
				database = "DW",
				user = "svc",
				readonly = true,
			},
			{ id = "analytics", name = "Analytics", driver = "duckdb", file = "data/analytics.duckdb" },
		},
		bindings = {
			{ glob = "reports/**/*.sql", connection = "warehouse" },
			{ dir = "db/migrations", connection = "local-pg" },
			{ glob = "**/*.sql", connection = "analytics" },
		},
	}),
}, root .. "/.nvim/databases.json")
vim.fn.writefile({ "select 1;" }, root .. "/reports/mrr.sql")
vim.fn.writefile({ "select 1;" }, root .. "/db/migrations/001.sql")
vim.fn.writefile({ "select 1;" }, root .. "/other.sql")

vim.cmd(("cd %s"):format(vim.fn.fnameescape(root)))
local connections = require("db.connections")
local resolve = require("db.resolve")
connections.reload()

support.describe("connections: reading the project file")
check("three connections", #connections.all(), 3)
check("driver aliases are canonical", connections.get("local-pg").driver, "postgres")
check("sqlserver too", connections.get("warehouse").driver, "mssql")
check(
	"password_env becomes a source",
	connections.get("local-pg").password_source,
	{ kind = "env", var = "PGPASSWORD_TEST" }
)
check(
	"a user with no source means the keyring",
	connections.get("warehouse").password_source,
	{ kind = "keyring", account = "warehouse" }
)
-- getcwd resolves symlinks (/var is /private/var on macOS), so compare against
-- the project root the module itself reports.
check(
	"a relative file resolves against the project",
	connections.get("analytics").file,
	vim.fs.normalize(connections.project_root() .. "/data/analytics.duckdb")
)
check("readonly is kept", connections.get("warehouse").readonly, true)
check("scope", connections.get("local-pg").scope, "project")
check("the project default", connections.project_default(), "local-pg")

support.describe("connections: a literal password is refused")
local original = vim.fn.readfile(root .. "/.nvim/databases.json")
vim.fn.writefile({
	vim.json.encode({
		version = 1,
		connections = { { id = "bad", driver = "postgres", host = "h", password = "hunter2" } },
	}),
}, root .. "/.nvim/databases.json")
connections.reload()
check("the connection is dropped, not loaded with the password", connections.get("bad"), nil)
vim.fn.writefile(original, root .. "/.nvim/databases.json")
connections.reload()
check("and the good file still loads", #connections.all(), 3)

support.describe("connections: a bad driver is refused")
vim.fn.writefile({
	vim.json.encode({ version = 1, connections = { { id = "weird", driver = "oracle-ish", host = "h" } } }),
}, root .. "/.nvim/databases.json")
connections.reload()
check("dropped", connections.get("weird"), nil)
vim.fn.writefile(original, root .. "/.nvim/databases.json")
connections.reload()

support.describe("resolve: which connection a file uses")
local function resolved(path)
	local bufnr = vim.fn.bufadd(path)
	vim.fn.bufload(bufnr)
	vim.b[bufnr].db_connection_resolved = nil
	local connection, reason = resolve.for_buf(bufnr)
	return connection and connection.id or nil, reason
end

local id, reason = resolved(root .. "/reports/mrr.sql")
check(
	"the most specific glob wins",
	{ id, reason },
	{ "warehouse", "matched a binding in .nvim/databases.json" }
)
id = resolved(root .. "/db/migrations/001.sql")
check("a dir binding", id, "local-pg")
id = resolved(root .. "/other.sql")
check("a catch-all glob still beats the default", id, "analytics")

support.describe("resolve: an explicit choice wins and is remembered")
local bufnr = vim.fn.bufadd(root .. "/reports/mrr.sql")
vim.fn.bufload(bufnr)
resolve.bind(bufnr, "analytics")
vim.b[bufnr].db_connection_resolved = nil
local connection
connection, reason = resolve.for_buf(bufnr)
check("chosen connection", { connection.id, reason }, { "analytics", "saved for this file" })

-- A buffer with no file on disk can only rely on the in-session choice.
local scratch = vim.api.nvim_create_buf(false, true)
resolve.bind(scratch, "warehouse")
connection, reason = resolve.for_buf(scratch)
check(
	"a scratch buffer keeps its choice",
	{ connection.id, reason },
	{ "warehouse", "chosen for this buffer" }
)

support.describe("resolve: nothing configured")
vim.fn.delete(root .. "/.nvim/databases.json")
connections.reload()
local empty = vim.fn.bufadd(root .. "/unknown.sql")
vim.fn.bufload(empty)
vim.b[empty].db_connection_resolved = nil
check("no connection, and no error", resolve.for_buf(empty), nil)

support.describe("connections: a session-only connection")
local scratch_connection = {
	id = "__test_scratch__",
	name = "scratch",
	driver = "duckdb",
	file = "/tmp/whatever.duckdb",
	password_source = { kind = "none" },
	options = {},
}
local listed_before = #connections.all()
connections.register(scratch_connection)
check("resolvable by id", connections.get("__test_scratch__").name, "scratch")
check("but not in the list of configured ones", #connections.all(), listed_before)
connections.reload()
check("and it survives a reload", connections.get("__test_scratch__") ~= nil, true)

local scratch_buf = vim.api.nvim_create_buf(false, true)
resolve.bind(scratch_buf, "__test_scratch__")
check("a buffer can resolve to it", resolve.for_buf(scratch_buf).id, "__test_scratch__")
