-- The catalog, asked of the driver.
--
-- This used to be six files of hand-written SQL - pg_catalog, information_
-- schema, sys.objects, sqlite_master, duckdb_tables() and a Mongo aggregation
-- - each with its own quirks. JDBC's DatabaseMetaData answers all of it, so
-- the Java side does the asking and this is only a cache in front of it.
local config = require("db.config")
local db = require("db")
local jvm = require("db.jvm")
local runner = require("db.runner")

local M = {}

local QUOTE = {
	mysql = "`",
	mariadb = "`",
	mssql = "[",
	mongodb = "",
}

local memory = {}

--- Quote an identifier the way this engine expects.
function M.quote(driver, name)
	local style = QUOTE[driver]
	if style == "" then
		return tostring(name)
	end
	if style == "[" then
		return "[" .. tostring(name):gsub("%]", "]]") .. "]"
	end
	if style == "`" then
		return "`" .. tostring(name):gsub("`", "``") .. "`"
	end
	return '"' .. tostring(name):gsub('"', '""') .. '"'
end

--- schema.table, quoted, for a generated statement.
function M.qualify(connection, schema, table_name)
	if connection.driver == "mongodb" then
		return tostring(table_name)
	end
	if schema and schema ~= "" and connection.driver ~= "sqlite" then
		return M.quote(connection.driver, schema) .. "." .. M.quote(connection.driver, table_name)
	end
	return M.quote(connection.driver, table_name)
end

local function cache_path(connection)
	local dir = db.state_dir .. "/cache"
	vim.fn.mkdir(dir, "p")
	return ("%s/%s.json"):format(dir, vim.fn.sha256(connection.id))
end

local function cache_get(connection, key)
	local store = memory[connection.id]
	if not store then
		store = {}
		local path = cache_path(connection)
		if vim.fn.filereadable(path) == 1 then
			local ok, lines = pcall(vim.fn.readfile, path)
			if ok then
				local decoded, data = pcall(vim.json.decode, table.concat(lines, "\n"))
				if decoded and type(data) == "table" then
					store = data
				end
			end
		end
		memory[connection.id] = store
	end
	local entry = store[key]
	if not entry or (os.time() - (entry.at or 0)) > config.get().schema_ttl_seconds then
		return nil
	end
	return entry.value
end

local function cache_put(connection, key, value)
	memory[connection.id] = memory[connection.id] or {}
	memory[connection.id][key] = { at = os.time(), value = value }
	pcall(vim.fn.writefile, { vim.json.encode(memory[connection.id]) }, cache_path(connection))
end

function M.invalidate(connection)
	if connection then
		memory[connection.id] = nil
		pcall(vim.fn.delete, cache_path(connection))
	else
		memory = {}
		pcall(vim.fn.delete, db.state_dir .. "/cache", "rf")
	end
end

--- Ask the runner a catalog question, going through the normal queue so a
--- schema refresh never overtakes the user's own query.
local function ask(connection, operation, arguments, key, callback)
	if key then
		local cached = cache_get(connection, key)
		if cached then
			return callback(cached, nil)
		end
	end

	local function send()
		jvm.request(connection, operation, arguments, function(response)
			vim.schedule(function()
				if not response.ok then
					return callback(nil, response.message or "catalog lookup failed")
				end
				local rows = {}
				for _, row in ipairs(response.rows or {}) do
					rows[#rows + 1] = row
				end
				if key then
					cache_put(connection, key, rows)
				end
				callback(rows, nil)
			end)
		end)
	end

	if jvm.is_connected(connection.id) then
		return send()
	end
	-- Nothing is connected yet: a trivial query opens the process, and the
	-- catalog question follows.
	runner.run({
		connection = connection,
		sql = connection.driver == "mongodb" and "db.getCollectionNames()" or "select 1",
		mode = "query",
		limit = 1,
		background = true,
	}, function(_, err)
		if err and not jvm.is_connected(connection.id) then
			return callback(nil, err.message)
		end
		send()
	end)
end

local function encode(value)
	return jvm.encode(value or "")
end

function M.databases(connection, callback)
	ask(connection, "catalogs", {}, "catalogs", callback)
end

function M.schemas(connection, catalog, callback)
	if type(catalog) == "function" then
		catalog, callback = nil, catalog
	end
	ask(connection, "schemas", { encode(catalog) }, "schemas:" .. tostring(catalog), callback)
end

function M.tables(connection, schema, pattern, callback, catalog)
	local key = (pattern == nil or pattern == "")
			and ("tables:%s.%s"):format(tostring(catalog), tostring(schema))
		or nil
	ask(connection, "tables", { encode(catalog), encode(schema), encode(pattern) }, key, callback)
end

function M.columns(connection, schema, table_name, callback, catalog)
	ask(
		connection,
		"columns",
		{ encode(catalog), encode(schema), encode(table_name) },
		("columns:%s.%s.%s"):format(tostring(catalog), tostring(schema), tostring(table_name)),
		callback
	)
end

function M.ddl(connection, schema, table_name, callback, catalog)
	ask(connection, "ddl", { encode(catalog), encode(schema), encode(table_name) }, nil, callback)
end

--- The SELECT the explorer opens for a table.
---
--- No column rewriting any more: the Java side renders a binary column as hex
--- because JDBC tells it the column is binary, so "select *" is safe.
function M.select_statement(connection, schema, table_name, _columns)
	if connection.driver == "mongodb" then
		return ("db.%s.find({})"):format(table_name)
	end
	return ("SELECT * FROM %s"):format(M.qualify(connection, schema, table_name))
end

--- A few rows for the previewer.
function M.sample(connection, schema, table_name, count, callback)
	local sql
	if connection.driver == "mongodb" then
		sql = ("db.%s.find({})"):format(table_name)
	else
		-- The row cap is applied by the driver (setMaxRows), so no dialect
		-- needs a LIMIT spelled out here.
		sql = ("SELECT * FROM %s"):format(M.qualify(connection, schema, table_name))
	end
	runner.run({
		connection = connection,
		sql = sql,
		mode = "query",
		limit = count,
		background = true,
		timeout_ms = 15000,
	}, function(result, err)
		if err then
			return callback(nil, err.message)
		end
		callback(result, nil)
	end)
end

return M
