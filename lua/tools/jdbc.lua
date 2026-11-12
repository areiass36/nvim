-- JDBC drivers, one jar per database, downloaded when that database is first
-- used.
--
-- Each connection runs with only its own driver on the classpath. That is not
-- tidiness: the MongoDB driver bundles a GraalVM JavaScript engine, and having
-- it on the classpath of a PostgreSQL connection prints warnings and slows the
-- start of every query.
local tools = require("tools")
local download = require("tools.download")

local MAVEN = "https://repo1.maven.org/maven2"

--- @class db.Driver
--- @field jar string file name under tools_dir/jdbc
--- @field url string
--- @field class string|nil driver class, when DriverManager cannot find it alone
local DRIVERS = {
	postgres = {
		jar = "postgresql-42.7.7.jar",
		url = MAVEN .. "/org/postgresql/postgresql/42.7.7/postgresql-42.7.7.jar",
	},
	mysql = {
		jar = "mysql-connector-j-9.3.0.jar",
		url = MAVEN .. "/com/mysql/mysql-connector-j/9.3.0/mysql-connector-j-9.3.0.jar",
	},
	mariadb = {
		jar = "mariadb-java-client-3.5.3.jar",
		url = MAVEN .. "/org/mariadb/jdbc/mariadb-java-client/3.5.3/mariadb-java-client-3.5.3.jar",
	},
	mssql = {
		jar = "mssql-jdbc-12.10.0.jre11.jar",
		url = MAVEN .. "/com/microsoft/sqlserver/mssql-jdbc/12.10.0.jre11/mssql-jdbc-12.10.0.jre11.jar",
	},
	sqlite = {
		jar = "sqlite-jdbc-3.49.1.0.jar",
		url = MAVEN .. "/org/xerial/sqlite-jdbc/3.49.1.0/sqlite-jdbc-3.49.1.0.jar",
	},
	duckdb = {
		jar = "duckdb_jdbc-1.3.1.0.jar",
		url = MAVEN .. "/org/duckdb/duckdb_jdbc/1.3.1.0/duckdb_jdbc-1.3.1.0.jar",
	},
	-- Trino is a query engine in front of other stores rather than a store, so
	-- this jar speaks its HTTP protocol instead of a database wire protocol.
	-- Catalogs are the level above schemas; the explorer already walks them.
	trino = {
		jar = "trino-jdbc-484.jar",
		url = MAVEN .. "/io/trino/trino-jdbc/484/trino-jdbc-484.jar",
	},
	-- JetBrains', the one DataGrip itself uses: Apache-2.0, and the only
	-- JDBC driver that talks to a plain mongod. MongoDB's own driver needs
	-- the Atlas SQL interface, which a local server does not have.
	mongodb = {
		jar = "mongo-jdbc-standalone-1.21.jar",
		url = "https://github.com/DataGrip/mongo-jdbc-driver/releases/download/v1.21/mongo-jdbc-standalone-1.21.jar",
	},
}

local M = {}

M.dir = tools.tools_dir .. "/jdbc"

--- @return string|nil path to the jar for this driver
function M.jar(driver)
	local spec = DRIVERS[driver]
	if not spec then
		return nil
	end
	local path = ("%s/%s"):format(M.dir, spec.jar)
	return vim.fn.filereadable(path) == 1 and path or nil
end

function M.expected_jar(driver)
	local spec = DRIVERS[driver]
	return spec and ("%s/%s"):format(M.dir, spec.jar) or nil
end

function M.drivers()
	return vim.tbl_keys(DRIVERS)
end

--- @param on_done fun(path: string|nil, err: string|nil)
function M.ensure(driver, on_done)
	local spec = DRIVERS[driver]
	if not spec then
		return on_done(nil, ("no JDBC driver known for %q"):format(tostring(driver)))
	end

	local existing = M.jar(driver)
	if existing then
		return on_done(existing, nil)
	end

	vim.fn.mkdir(M.dir, "p")
	local path = ("%s/%s"):format(M.dir, spec.jar)
	tools.notify(("downloading the %s JDBC driver..."):format(driver))
	-- A jar is not an archive to unpack: it is the artifact, so curl writes it
	-- straight to its destination.
	download.file(spec.jar, spec.url, path, function(ok)
		if not ok then
			return on_done(nil, ("could not download the %s driver"):format(driver))
		end
		on_done(path, nil)
	end)
end

return M
