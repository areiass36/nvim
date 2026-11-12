-- Shared scaffolding for the database explorer's tests. Same harness shape as
-- tests/db/support.lua and tests/runner/support.lua.
--
-- The explorer is drawn over the installed neogrip plugin, so the suites load
-- that plugin rather than a fake of it: a fake would be this config's idea of
-- what the plugin answers, which is the one thing worth checking. What they do
-- replace is the database. A swept catalog is a document on disk, so a fixture
-- snapshot written into a temporary state directory answers every level of the
-- walk -- schemas, tables, columns, keys, indexes -- with no server, no JVM and
-- nothing on the network. The real state directory is never touched.
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
			("FAIL %s / %s\n  got:  %s\n  want: %s\n"):format(current, name, vim.inspect(got), vim.inspect(want))
		)
	else
		io.write(("ok   %s\n"):format(name))
	end
	return ok
end

--- A check that only asks whether the line is in there, for a pane whose exact
--- wording is neogrip's and not this config's.
function M.has(name, lines, needle)
	M.checks = M.checks + 1
	for _, line in ipairs(lines or {}) do
		if type(line) == "string" and line:find(needle, 1, true) then
			io.write(("ok   %s\n"):format(name))
			return true
		end
	end
	M.failures = M.failures + 1
	io.write(("FAIL %s / %s\n  no line contains %q in:\n%s\n"):format(
		current,
		name,
		needle,
		table.concat(lines or {}, "\n")
	))
	return false
end

function M.lacks(name, lines, needle)
	M.checks = M.checks + 1
	for _, line in ipairs(lines or {}) do
		if type(line) == "string" and line:find(needle, 1, true) then
			M.failures = M.failures + 1
			io.write(("FAIL %s / %s\n  %q should not be there: %s\n"):format(current, name, needle, line))
			return false
		end
	end
	io.write(("ok   %s\n"):format(name))
	return true
end

function M.fail(name, detail)
	M.checks = M.checks + 1
	M.failures = M.failures + 1
	io.write(("FAIL %s / %s\n  %s\n"):format(current, name, detail))
end

function M.note(text)
	io.write(("     %s\n"):format(text))
end

function M.wait(fn, timeout)
	return vim.wait(timeout or 5000, fn, 10)
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

-- ---------------------------------------------------------- the plugin
M.plugin_dir = vim.fs.normalize(vim.fn.stdpath("data") .. "/lazy/neogrip.nvim")

--- Is the plugin installed? The suites skip rather than fail without it: this
--- config carries no copy of it, so a fresh checkout has nothing to test
--- against until lazy has cloned it.
function M.available()
	return vim.uv.fs_stat(M.plugin_dir .. "/lua/neogrip/tree.lua") ~= nil
end

--- Put the plugin on the runtimepath and move its state somewhere disposable.
function M.setup()
	vim.opt.rtp:prepend(M.plugin_dir)
	local neogrip = require("neogrip")
	M.state_dir = vim.fs.normalize(vim.fn.tempname() .. "-grip")
	neogrip.state_dir = M.state_dir
	vim.fn.mkdir(M.state_dir, "p")
	-- A pane that samples rows is a pane that opens a database connection, and
	-- these suites reach nothing. The cases that care set it back themselves.
	require("grip.preview").options.sample_automatically = false
	return neogrip
end

-- ------------------------------------------------------------- telescope
local telescope_ready = nil

--- Telescope on the runtimepath and set up with the editor's own defaults.
---
--- Captured from lua/plugins/editor/telescope.lua rather than copied: the
--- picker fills the screen because that file says every picker does, and a copy
--- of its layout here would keep passing after the real one changed. Only the
--- defaults are taken -- the extensions and the keymaps in that spec need half
--- the plugin list loaded and none of them are what the explorer is built on.
--- @return boolean
function M.telescope()
	if telescope_ready ~= nil then
		return telescope_ready
	end
	telescope_ready = false
	local data = vim.fs.normalize(vim.fn.stdpath("data") .. "/lazy")
	for _, plugin in ipairs({ "plenary.nvim", "telescope-zf-native.nvim", "telescope.nvim" }) do
		if vim.uv.fs_stat(data .. "/" .. plugin) then
			vim.opt.rtp:prepend(data .. "/" .. plugin)
		end
	end
	local ok, telescope = pcall(require, "telescope")
	if not ok then
		return false
	end

	local spec_path = vim.fn.stdpath("config") .. "/lua/plugins/editor/telescope.lua"
	local captured = nil
	local real_setup = telescope.setup
	telescope.setup = function(opts)
		captured = opts
	end
	-- The rest of that config function loads extensions and sets keymaps, which
	-- is where it will stop without them; by then the defaults are in hand.
	pcall(function()
		dofile(spec_path).config()
	end)
	telescope.setup = real_setup

	local defaults = captured and captured.defaults or {}
	telescope.setup({ defaults = defaults })
	telescope_ready = true
	return true
end

function M.teardown()
	if M.state_dir then
		pcall(vim.fn.delete, M.state_dir, "rf")
	end
end

-- ------------------------------------------------------- the fake database
local sequence = 0

--- A connection the registry can answer for, without a file anywhere.
function M.connection(overrides)
	sequence = sequence + 1
	local connection = vim.tbl_extend("force", {
		id = ("test-%d"):format(sequence),
		name = ("Test %d"):format(sequence),
		driver = "postgres",
		host = "db.example.test",
		port = 5432,
		database = "shop",
		auth = { type = "password", user = "tester" },
		options = {},
		readonly = false,
		production = false,
	}, overrides or {})
	return require("neogrip.connections").register(connection)
end

--- A connection written where the registry reads them from.
---
--- Registering one makes it resolvable by id, which is all the walk needs from
--- the second level down; the connection list itself is answered from the
--- files, so a connection that has to appear there has to be in one. The file
--- is the temporary state directory's, never the real one.
function M.file_connection(overrides)
	sequence = sequence + 1
	local entry = vim.tbl_extend("force", {
		id = ("file-%d"):format(sequence),
		name = ("File %d"):format(sequence),
		driver = "postgres",
		host = "db.example.test",
		port = 5432,
		database = "shop",
	}, overrides or {})
	local connections = require("neogrip.connections")
	local path = connections.global_file()
	vim.fn.mkdir(vim.fs.dirname(path), "p")
	vim.fn.writefile(vim.split(vim.json.encode({ version = 2, connections = { entry } }), "\n"), path)
	connections.reload()
	return connections.get(entry.id)
end

--- The columns of the fixture's two tables, spelled out once.
local function columns_of(which)
	if which == "customers" then
		return {
			{
				name = "id",
				type = "bigint",
				nullable = false,
				is_pk = true,
				position = 1,
				auto_increment = true,
			},
			{ name = "email", type = "text", nullable = false, position = 2, remarks = "Login" },
			{ name = "created_at", type = "timestamptz", nullable = true, position = 3, default_expr = "now()" },
		}
	end
	if which == "orders" then
		return {
			{ name = "id", type = "bigint", nullable = false, is_pk = true, position = 1 },
			{ name = "customer_id", type = "bigint", nullable = false, position = 2 },
			{ name = "total", type = "numeric(12,2)", nullable = true, position = 3 },
		}
	end
	return { { name = "email", type = "text", nullable = true, position = 1 } }
end

--- A swept catalog: two schemas, three tables and a view, with keys, an index
--- and an inbound reference, which is everything a definition is rendered from.
function M.schemas()
	return {
		{
			name = "public",
			tables = {
				{
					name = "customers",
					kind = "table",
					details = true,
					remarks = "People who buy things",
					primary_key = { "id" },
					primary_key_name = "customers_pkey",
					indexes = {
						{ name = "customers_email_key", unique = true, columns = { "email" } },
						{ name = "customers_pkey", unique = true, columns = { "id" } },
					},
					foreign_keys = {},
					referenced_by = {
						{
							name = "orders_customer_id_fkey",
							schema = "public",
							table = "orders",
							columns = { "customer_id" },
							ref_columns = { "id" },
						},
					},
					columns = columns_of("customers"),
				},
				{
					name = "orders",
					kind = "table",
					details = true,
					primary_key = { "id" },
					primary_key_name = "orders_pkey",
					indexes = {},
					foreign_keys = {
						{
							name = "orders_customer_id_fkey",
							schema = "public",
							table = "customers",
							columns = { "customer_id" },
							ref_columns = { "id" },
							on_delete = "cascade",
						},
					},
					referenced_by = {},
					columns = columns_of("orders"),
				},
				{
					name = "active_customers",
					kind = "view",
					details = true,
					primary_key = {},
					indexes = {},
					foreign_keys = {},
					referenced_by = {},
					columns = columns_of("view"),
				},
			},
		},
		{
			name = "audit",
			tables = {
				{
					name = "events",
					kind = "table",
					details = true,
					primary_key = { "id" },
					indexes = {},
					foreign_keys = {},
					referenced_by = {},
					columns = { { name = "id", type = "bigint", nullable = false, is_pk = true, position = 1 } },
				},
			},
		},
	}
end

--- Write that catalog where the plugin reads a swept one from.
function M.sweep(connection, catalog, schemas)
	local store = require("neogrip.schema.store")
	local ok = store.save(connection, catalog, { schemas = schemas or M.schemas(), product = "PostgreSQL 16.2" })
	store.reload(connection, catalog)
	return ok
end

--- A connection with its catalog already swept, which is the state the
--- explorer spends almost all of its life in.
function M.swept_connection(overrides)
	local connection = M.connection(overrides)
	M.sweep(connection, require("neogrip.schema").catalog_of(connection))
	return connection
end

--- The node a walk starts from.
function M.server_node(connection)
	local ref = { server = connection.id }
	return {
		id = require("neogrip.tree").id(ref),
		level = "server",
		kind = connection.driver,
		name = connection.name,
		ref = ref,
		expandable = true,
		facts = {},
	}
end

--- One level of the walk, as the explorer asks for it.
function M.children(node)
	local nodes, err = M.sync(function(done)
		require("neogrip.tree").children(node, {}, done)
	end)
	if err then
		error(("children of %s: %s"):format(tostring(node and node.level), vim.inspect(err)))
	end
	return nodes or {}
end

--- The child called `name`, so a case can walk without counting rows.
function M.child(node, name)
	for _, child in ipairs(M.children(node)) do
		if child.name == name then
			return child
		end
	end
	error(("no child named %q under %s"):format(name, tostring(node and node.name)))
end

--- What the pane holds the moment render returns, with nothing waited for.
---
--- For a swept catalog that is everything it can draw without the server, so
--- it is how the cases about sampling -- which is the one thing here that would
--- need a real database -- check the decision without taking one.
function M.pane_now(node, opts)
	local bufnr = vim.api.nvim_create_buf(false, true)
	require("grip.preview").render(node, bufnr, opts or {})
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	vim.api.nvim_buf_delete(bufnr, { force = true })
	return lines
end

--- What the pane is left holding for a node, once it is done.
function M.pane(node, opts)
	local bufnr = vim.api.nvim_create_buf(false, true)
	local preview = require("grip.preview")
	local lines = M.sync(function(done)
		preview.render(node, bufnr, opts or {}, done)
	end)
	vim.api.nvim_buf_delete(bufnr, { force = true })
	return lines or {}
end

return M
