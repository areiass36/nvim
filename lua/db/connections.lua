-- Connections come from two files and never contain a password.
--
--   global:  stdpath("state")/db/connections.json
--   project: <git root>/.nvim/databases.json, which also maps folders and
--            globs to a connection and names the project default
--
-- A project entry wins over a global one with the same id. The password lives
-- in the OS keyring, in an environment variable or behind a command; see
-- db/secrets.lua.
local db = require("db")

local M = {}

local DRIVERS = {
	postgres = true,
	mysql = true,
	mariadb = true,
	mssql = true,
	sqlite = true,
	duckdb = true,
	mongodb = true,
}

-- Driver spellings people reasonably write, mapped to the canonical one.
local DRIVER_ALIASES = {
	postgresql = "postgres",
	pg = "postgres",
	pgsql = "postgres",
	sqlserver = "mssql",
	tsql = "mssql",
	sqlite3 = "sqlite",
	mongo = "mongodb",
}

local cache = nil
local warned = {}
-- Connections that exist only for this session, such as the DuckDB scratch a
-- materialised result is queried through. They are not in any file, but a
-- buffer still has to be able to resolve one by id.
local ephemeral = {}

local function warn_once(key, message)
	if not warned[key] then
		warned[key] = true
		db.notify(message, vim.log.levels.WARN)
	end
end

function M.project_root()
	local cwd = vim.fn.getcwd()
	return vim.fs.root(cwd, ".git") or cwd
end

function M.global_file()
	return db.state_dir .. "/connections.json"
end

function M.project_file()
	return M.project_root() .. "/.nvim/databases.json"
end

local function read_json(path)
	if vim.fn.filereadable(path) == 0 then
		return nil
	end
	local ok, lines = pcall(vim.fn.readfile, path)
	if not ok then
		return nil, "could not read " .. path
	end
	local decoded, data = pcall(vim.json.decode, table.concat(lines, "\n"))
	if not decoded or type(data) ~= "table" then
		return nil, ("%s is not valid JSON"):format(path)
	end
	return data
end

--- Expand a path the way a shell would, and resolve a relative one against the
--- project root so a project file can say "file": "db/app.sqlite".
local function resolve_file(path)
	if not path or path == "" then
		return nil
	end
	local expanded = vim.fn.expand(path)
	if
		vim.fn.fnamemodify(expanded, ":p") == expanded
		or expanded:match("^[/~]")
		or expanded:match("^%a:[/\\]")
	then
		return vim.fs.normalize(expanded)
	end
	return vim.fs.normalize(M.project_root() .. "/" .. expanded)
end

--- A password_source is a tagged union, because "where does the password come
--- from" has genuinely different shapes and guessing between them silently is
--- how credentials end up in the wrong place.
local function normalize_password_source(entry)
	if entry.password ~= nil then
		return nil,
			("connection %q has a literal password: put it in the keyring with :DbSetPassword, or use password_env"):format(
				entry.id or "?"
			)
	end
	if type(entry.password_env) == "string" then
		return { kind = "env", var = entry.password_env }
	end
	if type(entry.password_command) == "table" then
		return { kind = "command", argv = entry.password_command }
	end
	local source = entry.password_source
	if type(source) == "string" then
		source = { kind = source }
	end
	if type(source) ~= "table" or source.kind == nil then
		-- A connection with a user but no stated source is the common case:
		-- look it up in the keyring under its own id.
		return entry.user and { kind = "keyring", account = entry.id } or { kind = "none" }
	end
	if source.kind == "env" and type(source.var) ~= "string" then
		return nil, ("connection %q: password_source.env needs a var name"):format(entry.id)
	end
	if source.kind == "command" and type(source.argv) ~= "table" then
		return nil, ("connection %q: password_source.command needs argv"):format(entry.id)
	end
	if source.kind == "keyring" then
		source.account = source.account or entry.id
	end
	return source
end

--- @return table|nil connection, string|nil error
local function normalize(entry, scope)
	if type(entry) ~= "table" then
		return nil, "connection entry is not an object"
	end
	if type(entry.id) ~= "string" or entry.id == "" then
		return nil, "connection without an id"
	end
	local driver = DRIVER_ALIASES[entry.driver] or entry.driver
	if not DRIVERS[driver] then
		return nil, ("connection %q has an unknown driver %q"):format(entry.id, tostring(entry.driver))
	end

	local password_source, err = normalize_password_source(entry)
	if not password_source then
		return nil, err
	end

	local file = resolve_file(entry.file)
	if (driver == "sqlite" or driver == "duckdb") and not file then
		return nil, ("connection %q (%s) needs a file"):format(entry.id, driver)
	end

	return {
		id = entry.id,
		name = entry.name or entry.id,
		driver = driver,
		host = entry.host,
		port = entry.port,
		database = entry.database,
		file = file,
		user = entry.user,
		password_source = password_source,
		options = entry.options or {},
		default_schema = entry.default_schema,
		readonly = entry.readonly == true,
		production = entry.production == true,
		limit = entry.limit,
		timeout_ms = entry.timeout_ms,
		client = entry.client or "auto",
		color = entry.color,
		scope = scope,
	}
end

local function load_file(path, scope, into, order)
	local data, err = read_json(path)
	if err then
		warn_once("read:" .. path, err)
		return nil
	end
	if not data then
		return nil
	end
	for _, entry in ipairs(data.connections or {}) do
		local connection, entry_err = normalize(entry, scope)
		if connection then
			if into[connection.id] and into[connection.id].scope ~= scope then
				warn_once(
					"dup:" .. connection.id,
					("connection %q is defined twice; the project file wins"):format(connection.id)
				)
			elseif not into[connection.id] then
				order[#order + 1] = connection.id
			end
			into[connection.id] = connection
		else
			warn_once("entry:" .. path .. tostring(entry.id), entry_err)
		end
	end
	return data
end

--- Warn when the project file is not ignored by git. It holds hosts, user names
--- and the names of the environment variables that hold the passwords: useful
--- to a reader, and not something to push by accident.
local function check_ignored(path)
	if vim.fn.filereadable(path) == 0 then
		return
	end
	vim.system(
		{ "git", "check-ignore", "-q", path },
		{ cwd = M.project_root() },
		vim.schedule_wrap(function(result)
			if result.code ~= 0 then
				warn_once("gitignore", ".nvim/databases.json is not gitignored; add '.nvim/' to .gitignore")
			end
		end)
	)
end

local function load()
	local by_id, order = {}, {}
	load_file(M.global_file(), "global", by_id, order)
	local project_path = M.project_file()
	local project = load_file(project_path, "project", by_id, order)
	check_ignored(project_path)

	local list = {}
	for _, id in ipairs(order) do
		list[#list + 1] = by_id[id]
	end
	-- Project connections first: they are the ones you want in a picker.
	table.sort(list, function(a, b)
		if a.scope ~= b.scope then
			return a.scope == "project"
		end
		return a.name < b.name
	end)

	cache = {
		by_id = by_id,
		list = list,
		default = project and project.default or nil,
		bindings = project and project.bindings or {},
	}
	return cache
end

function M.state()
	return cache or load()
end

--- @return table[] every connection, project ones first
function M.all()
	return M.state().list
end

--- @return table|nil
function M.get(id)
	if not id then
		return nil
	end
	return M.state().by_id[id] or ephemeral[id]
end

--- Make a connection resolvable by id without writing it to a file.
function M.register(connection)
	ephemeral[connection.id] = connection
	return connection
end

function M.project_default()
	return M.state().default
end

function M.project_bindings()
	return M.state().bindings
end

function M.reload()
	cache = nil
	warned = {}
	-- Buffers memoize the connection they resolved to; that answer may have changed.
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		pcall(function()
			vim.b[bufnr].db_connection_resolved = nil
		end)
	end
	return M.state()
end

--- Write a connection into the global file, replacing one with the same id.
function M.save_global(connection)
	local data = read_json(M.global_file()) or { version = 1, connections = {} }
	data.connections = data.connections or {}
	local replaced = false
	for index, entry in ipairs(data.connections) do
		if entry.id == connection.id then
			data.connections[index] = connection
			replaced = true
			break
		end
	end
	if not replaced then
		table.insert(data.connections, connection)
	end
	vim.fn.mkdir(db.state_dir, "p")
	local ok = pcall(vim.fn.writefile, vim.split(vim.json.encode(data), "\n"), M.global_file())
	if ok then
		M.reload()
	end
	return ok
end

function M.setup()
	load()
	vim.api.nvim_create_autocmd("DirChanged", {
		group = vim.api.nvim_create_augroup("DbConnections", { clear = true }),
		callback = function()
			M.reload()
		end,
	})
end

return M
