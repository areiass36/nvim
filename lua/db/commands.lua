-- Every :Db command in one place.
local connections = require("db.connections")
local db = require("db")
local resolve = require("db.resolve")

local M = {}

local function command(name, fn, opts)
	vim.api.nvim_create_user_command(name, fn, opts or {})
end

local function connection_names()
	return vim.tbl_map(function(connection)
		return connection.id
	end, connections.all())
end

local function current_connection()
	local connection = resolve.for_buf(0)
	if not connection then
		db.notify("no connection for this buffer", vim.log.levels.WARN)
	end
	return connection
end

function M.setup()
	command("DbConnections", function()
		local lines = {}
		for _, connection in ipairs(connections.all()) do
			local target = connection.file
				or ("%s:%s/%s"):format(
					connection.host or "?",
					connection.port or "?",
					connection.database or "-"
				)
			lines[#lines + 1] = ("%-18s %-10s %-8s %-40s %s"):format(
				connection.id,
				connection.driver,
				connection.scope,
				target,
				(connection.readonly and "read-only " or "") .. (connection.production and "production" or "")
			)
		end
		if #lines == 0 then
			lines = { "no connections; :DbInit writes a project file" }
		end
		db.notify(table.concat(lines, "\n"))
	end, { desc = "List the configured database connections" })

	command("DbWhich", function()
		local connection, reason = resolve.for_buf(0)
		if not connection then
			return db.notify("no connection resolves for this buffer", vim.log.levels.WARN)
		end
		db.notify(("%s [%s] — %s"):format(connection.name, connection.driver, reason))
	end, { desc = "Show which connection this buffer runs against, and why" })

	command("DbUse", function(args)
		local connection = connections.get(args.args)
		if not connection then
			return db.notify(("no connection %q"):format(args.args), vim.log.levels.ERROR)
		end
		resolve.bind(0, connection.id)
		require("db.dialect").attach(0, connection.driver)
		db.notify(("%s selected for this buffer"):format(connection.name))
	end, {
		nargs = 1,
		complete = connection_names,
		desc = "Use a connection in this buffer",
	})

	command("DbReload", function()
		connections.reload()
		db.notify("connections reloaded")
	end, { desc = "Re-read the connection files" })

	command("DbRun", function(args)
		require("db.execute").run({ bufnr = 0, statement = args.args ~= "" and { text = args.args } or nil })
	end, { nargs = "?", desc = "Run a statement (or the one under the cursor)" })

	command("DbValidate", function()
		require("db.diagnostics").validate({ bufnr = 0, notify = true })
	end, { desc = "Check the statement under the cursor on the server" })

	command("DbCancel", function()
		require("db.execute").cancel()
	end, { desc = "Cancel the running query" })

	command("DbExplore", function()
		require("db.explorer").open({})
	end, { desc = "Explore the schema" })

	command(
		"DbSetPassword",
		function(args)
			local connection = args.args ~= "" and connections.get(args.args) or current_connection()
			if not connection then
				return
			end
			require("db.secrets").store(connection, nil, function(ok, err)
				if not ok then
					db.notify(err or "could not store the password", vim.log.levels.ERROR)
				end
			end)
		end,
		{ nargs = "?", complete = connection_names, desc = "Store a connection's password in the OS keyring" }
	)

	command(
		"DbDeletePassword",
		function(args)
			local connection = args.args ~= "" and connections.get(args.args) or current_connection()
			if not connection then
				return
			end
			require("db.secrets").delete(connection, function(ok)
				db.notify(ok and "password removed" or "nothing to remove")
			end)
		end,
		{ nargs = "?", complete = connection_names, desc = "Remove a connection's password from the keyring" }
	)

	command("DbForget", function()
		require("db.secrets").forget()
		db.notify("passwords forgotten for this session")
	end, { desc = "Drop the passwords held in memory" })

	command("DbSchemaReload", function()
		require("db.schema").invalidate(resolve.for_buf(0))
		db.notify("schema cache cleared")
	end, { desc = "Clear the cached catalog" })

	command("DbNewQuery", function()
		local connection = current_connection()
		if connection then
			require("db.buffer").new_query(connection, "")
		end
	end, { desc = "Open a query buffer against this buffer's connection" })

	command("DbResults", function()
		local grid = require("db.grid")
		local bufnr = grid.current_buf()
		if not bufnr then
			return db.notify("no result yet")
		end
		require("db.grid.duckdb_view").materialise(bufnr)
	end, { desc = "Query the current result with SQL (DuckDB)" })

	command(
		"DbKeep",
		function(args)
			local grid = require("db.grid")
			local bufnr = grid.current_buf()
			local state = bufnr and grid.state(bufnr)
			if not state then
				return db.notify("no result to keep", vim.log.levels.WARN)
			end
			local export = require("db.grid.export")
			local path = args.args ~= "" and vim.fn.expand(args.args)
				or (vim.fn.getcwd() .. "/result-" .. os.date("%Y%m%d-%H%M%S") .. ".csv")
			export.page_to_csv(state, path)
			db.notify(("kept as %s"):format(path))
		end,
		{ nargs = "?", complete = "file", desc = "Write the current result where it will not be cleaned up" }
	)

	command("DbInit", function()
		M.init_project()
	end, { desc = "Create .nvim/databases.json for this project" })

	command("DbDoctor", function()
		require("db.doctor").show()
	end, { desc = "Check the database clients and connections" })
end

--- Write a starter project file, but only once .gitignore covers it: the file
--- holds hosts, user names and the names of the variables holding passwords.
function M.init_project()
	local root = connections.project_root()
	local path = connections.project_file()
	if vim.fn.filereadable(path) == 1 then
		return db.notify((".nvim/databases.json already exists at %s"):format(root))
	end

	vim.system(
		{ "git", "check-ignore", "-q", ".nvim/databases.json" },
		{ cwd = root },
		vim.schedule_wrap(function(result)
			if result.code ~= 0 then
				local answer = vim.fn.confirm(
					".nvim/databases.json is not gitignored. Add '.nvim/' to .gitignore?",
					"&Yes\n&No",
					1
				)
				if answer ~= 1 then
					return db.notify("not creating the file: it would be committed", vim.log.levels.WARN)
				end
				local gitignore = root .. "/.gitignore"
				local lines = vim.fn.filereadable(gitignore) == 1 and vim.fn.readfile(gitignore) or {}
				table.insert(lines, ".nvim/")
				vim.fn.writefile(lines, gitignore)
			end

			vim.fn.mkdir(root .. "/.nvim", "p")
			local template = {
				"{",
				'  "version": 1,',
				'  "default": "local",',
				'  "connections": [',
				"    {",
				'      "id": "local",',
				'      "name": "Local Postgres",',
				'      "driver": "postgres",',
				'      "host": "127.0.0.1",',
				'      "port": 5432,',
				'      "database": "app_dev",',
				'      "user": "postgres",',
				'      "password_source": { "kind": "keyring", "account": "local" }',
				"    }",
				"  ],",
				'  "bindings": [',
				'    { "glob": "db/migrations/**/*.sql", "connection": "local" }',
				"  ]",
				"}",
			}
			vim.fn.writefile(template, path)
			connections.reload()
			db.notify(("wrote %s — :DbSetPassword local stores the password"):format(path))
			vim.cmd(("edit %s"):format(vim.fn.fnameescape(path)))
		end)
	)
end

return M
