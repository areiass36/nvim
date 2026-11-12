-- The explorer's preview pane: what the thing under the cursor holds.
--
-- A connection shows what it is, where it points and what has been swept out
-- of it; a database and a schema show their contents; a table shows its
-- definition -- the same CREATE TABLE <CR> opens, rendered by neogrip's own
-- renderer so the pane and the buffer can never describe one table two ways --
-- and a column shows what the server said about it.
--
-- Two rules the whole file is written to.
--
-- Nothing is asked of the server until the cursor has rested, and nothing at
-- all is asked when the answer is already on disk. A list of fifty tables
-- scrolled through must not queue fifty round trips on the one worker a
-- connection has, which is also the worker your own query is waiting behind;
-- once a database has been swept (:NGripIntrospect, or the sweep the explorer
-- starts the first time it opens) every level of this pane is answered from the
-- snapshot and draws in the same frame as the keypress.
--
-- Every line is either runnable SQL or a SQL comment, because a table's pane is
-- SQL -- highlighted as such -- and one buffer is reused for every row the
-- cursor touches.
--
-- What it does not do is sample rows from a database the user marked
-- `production`: a sample is a real query against every table the cursor lands
-- on, and a replica that serves an application is the wrong place to spend a
-- query per keystroke. <C-l> asks for one by hand, anywhere.
local connections = require("neogrip.connections")
local grip = require("grip")
local schema = require("neogrip.catalog")
local tree = require("neogrip.catalog.tree")

local M = {}

M.options = {
	-- Rows drawn under a table's definition. Zero never samples.
	sample_rows = 10,
	-- Sample without being asked? Never on a production connection; see above.
	sample_automatically = true,
	-- How long the cursor has to rest before anything that costs a round trip
	-- is asked for.
	debounce_ms = 180,
	-- The pane is half a window wide, so a sampled column is narrow.
	sample_width = 24,
	-- How many children a listing spells out before it says "and N more".
	listed = 60,
}

-- What the pane is meant to be showing, as of the most recent M.render. The
-- cursor keeps moving while a fetch is out, and the answer to a question asked
-- about the row above describes the wrong thing by the time it lands, so every
-- write that is not immediate is checked against this first.
local showing = nil

-- Lines already rendered, keyed by the same token. Scrolling back up a list is
-- then free and flicker-free, and a forced sample stays on screen while you
-- look away and come back. Dropped by M.forget, which is what <C-r> calls.
local pane = {}

-- Tables whose rows were asked for by hand.
local forced = {}

-- Approximate row counts, per namespace: one request answers for every table in
-- the schema (neogrip's ADR-0038), so it is asked once and read many times.
local counts = {}

-- One timer, because there is one cursor: a fetch for the row the cursor has
-- left is never worth making.
local timer = nil

local function debounce(callback)
	if timer then
		timer:stop()
	end
	timer = vim.defer_fn(function()
		timer = nil
		callback()
	end, M.options.debounce_ms)
end

local function write_lines(bufnr, lines)
	if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end
	vim.bo[bufnr].modifiable = true
	pcall(vim.api.nvim_buf_set_lines, bufnr, 0, -1, false, lines)
	vim.bo[bufnr].modifiable = false
end

--- Something the pane says in passing, as a SQL comment.
local function comment(text)
	return "-- " .. (tostring(text):gsub("%s+", " "))
end

local function field(name, value)
	return ("-- %-11s %s"):format(name, tostring(value))
end

--- Is this connection's process already up?
---
--- Peeked at rather than acted on: it is the difference between a pane that
--- fills in a row count and one that opens a database connection because the
--- cursor passed over a table. Guarded, since nothing public says it.
local function connected(connection)
	local ok, gripd = pcall(require, "neogrip.gripd")
	return ok and gripd.is_connected(connection.id) == true
end

--- Is everything below this node already on disk?
---
--- One boolean instead of a prediction of which level comes next: a swept
--- catalog answers for its schemas, its tables and their columns alike, and
--- that is exactly the case where neogrip's tree calls back without leaving the
--- process. Where it is false the fetch waits for the cursor to rest.
local function swept(node)
	local ok, stat = pcall(tree.swept, node.ref)
	return ok and stat ~= nil
end

--- The sweep, as a line: what is in it and how old it is.
local function sweep_line(node)
	local ok, stat = pcall(tree.swept, node.ref)
	if not ok or not stat then
		return field("swept", "never -- ,qi sweeps it in, and the explorer works meanwhile")
	end
	local text = ("%s in %s, %s"):format(
		grip.counted(stat.tables or 0, "table"),
		grip.counted(stat.schemas or 0, "schema"),
		grip.ago(stat.age_seconds)
	)
	if stat.partial then
		text = text .. "  (partial: the detail pass ran out of its budget)"
	end
	return field("swept", text)
end

-- ----------------------------------------------------------------- headers

local function server_header(connection, node)
	local facts = node.facts or {}
	local lines = { comment(connection.name or connection.id), "--" }
	lines[#lines + 1] = field("driver", connection.driver)
	if connection.file then
		lines[#lines + 1] = field("file", connection.file)
	end
	local where = grip.where_of(connection)
	if where and not connection.file then
		lines[#lines + 1] = field("host", where)
	end
	if connection.database and connection.database ~= "" then
		lines[#lines + 1] = field("database", connection.database)
	end
	if connection.catalog and connection.catalog ~= "" then
		lines[#lines + 1] = field("catalog", connection.catalog)
	end
	local user = connection.auth and connection.auth.user
	if user then
		lines[#lines + 1] = field("user", user)
	end
	local flags = {}
	if connection.readonly then
		flags[#flags + 1] = "read-only"
	end
	if connection.production then
		flags[#flags + 1] = "production"
	end
	if #flags > 0 then
		lines[#lines + 1] = field("flags", table.concat(flags, ", "))
	end
	lines[#lines + 1] = field("connected", facts.connected and "yes" or "no")
	lines[#lines + 1] = sweep_line(node)
	return lines
end

local function instance_header(connection, node)
	local facts = node.facts or {}
	local lines = { comment(grip.path_of(node.ref)), "--" }
	lines[#lines + 1] = field(node.kind == "catalog" and "catalog" or "database", node.name)
	lines[#lines + 1] = sweep_line(node)
	if facts.reconnects then
		-- PostgreSQL and SQL Server cannot query across databases, so walking in
		-- means a connection of its own (neogrip's ADR-0039). The explorer opens
		-- it for you; this is the pane saying so.
		lines[#lines + 1] = field("note", "walking in opens a connection of its own")
	end
	return lines
end

local function namespace_header(connection, node)
	return { comment(grip.path_of(node.ref)), "--" }
end

--- A column, as everything the server said about it.
local function attribute_lines(connection, node)
	local facts = node.facts or {}
	local lines = { comment(("%s.%s"):format(grip.path_of(node.ref), node.name)), "--" }
	lines[#lines + 1] = field("type", facts.type or "-")
	lines[#lines + 1] = field("nullable", facts.nullable == false and "no" or "yes")
	lines[#lines + 1] = field("primary key", facts.is_pk and "yes" or "no")
	if facts.position then
		lines[#lines + 1] = field("position", facts.position)
	end
	if facts.default_expr then
		lines[#lines + 1] = field("default", facts.default_expr)
	end
	if facts.auto_increment then
		lines[#lines + 1] = field("generated", "by the server, on insert")
	elseif facts.generated then
		lines[#lines + 1] = field("generated", "always")
	end
	if facts.count then
		-- Sampled rather than declared: a collection has no column list, so the
		-- fields come from reading documents (neogrip's ADR-0029).
		lines[#lines + 1] = field("documents", ("%s of %s sampled"):format(facts.count, facts.sample_size or "?"))
	end
	local remarks = grip.said(facts.remarks)
	if remarks then
		lines[#lines + 1] = field("remarks", remarks)
	end
	return lines
end

-- ---------------------------------------------------------------- listings

--- The children of a container, as a listing: how many of each kind, then one
--- line per child with the same icon and the same hint the list itself uses.
local function listing(nodes)
	local lines = {}
	local kinds, counted = {}, {}
	local width = 1
	for _, child in ipairs(nodes) do
		local kind = tostring(child.kind or child.level)
		if counted[kind] == nil then
			kinds[#kinds + 1] = kind
		end
		counted[kind] = (counted[kind] or 0) + 1
		width = math.max(width, #tostring(child.name or ""))
	end
	-- Capped, because one pathological name should not push every hint off the
	-- right of a pane half a window wide.
	width = math.min(width, 40)

	local summary = {}
	for _, kind in ipairs(kinds) do
		summary[#summary + 1] = grip.counted(counted[kind], kind)
	end
	lines[#lines + 1] = comment(table.concat(summary, ", "))
	lines[#lines + 1] = "--"

	for index, child in ipairs(nodes) do
		if index > M.options.listed then
			lines[#lines + 1] = "--"
			lines[#lines + 1] = comment(("%d more"):format(#nodes - M.options.listed))
			break
		end
		lines[#lines + 1] = (("--   %s %-" .. width .. "s  %s"):format(
			grip.icon_of(child),
			tostring(child.name or ""),
			grip.hint_of(child)
		):gsub("%s+$", ""))
	end
	return lines
end

-- ------------------------------------------------------------------ tables

--- The row estimate for this table, if one is already in hand.
---
--- Lazy by design: the first table previewed in a schema asks for the whole
--- schema's counts and draws without them, and every table after it has the
--- answer. Engines that keep no cheap estimate -- SQLite, DuckDB, Trino,
--- MongoDB -- answer nothing and nothing is shown, which is the point: a number
--- nobody can produce cheaply is not worth a count(*).
local function estimate(connection, node)
	local catalog, namespace = grip.qualifiers(connection, node.ref)
	local key = ("%s|%s|%s"):format(connection.id, tostring(catalog), tostring(namespace))
	local known = counts[key]
	if known then
		return known[node.name]
	end
	if not connected(connection) then
		return nil
	end
	-- Fire and forget, and only once per namespace: the answer is for the next
	-- table in this schema, not for this one.
	counts[key] = {}
	tree.counts(node.ref, function(map)
		counts[key] = type(map) == "table" and map or {}
	end)
	return nil
end

--- A thousands-separated estimate, as a comment under the definition.
local function estimate_line(amount)
	-- floor, because an engine's estimate is a float: PostgreSQL's reltuples is
	-- a running approximation, not a count.
	local text = ("%d"):format(math.floor(amount))
	local separated = text:reverse():gsub("(%d%d%d)", "%1."):reverse():gsub("^%.", "")
	return comment(("~%s rows (the engine's own estimate, not a count)"):format(separated))
end

-- ------------------------------------------------------------------ render

--- Fill `bufnr` with what is worth knowing about `node`.
---
--- `on_done` fires once, with the lines the pane is left holding. A pane can be
--- written more than once before that: a header goes up immediately so the pane
--- is never blank while the round trip under it is out.
--- @param node table a neogrip tree node, or the explorer's ".." row
--- @param opts table|nil { rows = true } to sample without being asked twice
--- @param on_done fun(lines: string[])|nil
function M.render(node, bufnr, opts, on_done)
	opts = opts or {}
	local wants_rows = opts.rows == true or forced[node.id or ""] == true
	local token = ("%s\t%s"):format(node.id or tostring(node.text), wants_rows and "rows" or "")
	showing = token

	local function write(lines)
		if showing ~= token then
			return
		end
		write_lines(bufnr, lines)
	end

	local function finish(lines)
		if showing == token then
			pane[token] = lines
		end
		write(lines)
		if on_done then
			on_done(lines)
		end
		return lines
	end

	-- Only a table's pane is SQL, and one buffer is reused for every row the
	-- cursor touches, so the highlighting the row before it asked for has to come
	-- off again. Through treesitter alone and never 'filetype', which would fire
	-- the FileType autocommand that hangs the query keymaps, the dialect layer
	-- and a language server off a buffer Telescope throws away.
	if node.level == "set" then
		pcall(vim.treesitter.start, bufnr, "sql")
	else
		pcall(vim.treesitter.stop, bufnr)
	end

	-- The row that walks back out is not a thing in the database: its own text
	-- says where it goes, which is all the file browser says for its own "..".
	-- Asking about it would send ".." to the server as a table name.
	if node.parent then
		return finish({ comment(node.text) })
	end

	local connection = connections.get(node.ref.server)
	if not connection then
		return finish({ comment(("no connection named %q is configured"):format(tostring(node.ref.server))) })
	end

	if pane[token] then
		return finish(pane[token])
	end

	if node.level == "attribute" then
		return finish(attribute_lines(connection, node))
	end

	if node.level == "object" then
		-- Rows are not a level the explorer lists; if one ever arrives here, its
		-- values are already on the node.
		local lines = {}
		for _, name in ipairs((node.facts or {}).columns or {}) do
			lines[#lines + 1] = field(name, tostring((node.facts.values or {})[name]))
		end
		return finish(lines)
	end

	if node.level == "set" then
		local catalog, namespace = grip.qualifiers(connection, node.ref)

		--- The definition, or a comment in its place. The same renderer <CR>
		--- opens, so the pane and the buffer cannot drift apart.
		local function definition(details)
			local ok, lines = pcall(require("neogrip.catalog.ddl").details, connection, namespace, node.name, details)
			if ok and type(lines) == "table" then
				return lines
			end
			return { comment(("%s: the definition could not be rendered"):format(node.name)), comment(lines) }
		end

		local function draw(details)
			local lines = definition(details)
			local rows = estimate(connection, node)
			if rows then
				lines[#lines + 1] = ""
				lines[#lines + 1] = estimate_line(rows)
			end

			local sampling = M.options.sample_rows > 0
				and (wants_rows or (M.options.sample_automatically and not connection.production))
			if not sampling then
				if not wants_rows and connection.production then
					lines[#lines + 1] = ""
					lines[#lines + 1] = comment("production: <C-l> samples rows")
				end
				return finish(lines)
			end

			-- Under the definition and behind a comment, so the pane still reads
			-- as the one SQL buffer it is highlighted as.
			lines[#lines + 1] = ""
			lines[#lines + 1] = ("-- Sample (%d rows)"):format(M.options.sample_rows)
			write(lines)

			debounce(function()
				if showing ~= token then
					return
				end
				tree.statement(node.ref, "select", function(text, statement_err)
					if showing ~= token then
						return
					end
					if statement_err or not text then
						lines[#lines + 1] = comment(grip.message_of(statement_err or "no statement"))
						return finish(lines)
					end
					-- background, so gripd names no result and holds no cursor for
					-- it: a sample is read once and never paged (its ADR-0031).
					require("neogrip.runner").run({
						connection = connection,
						sql = text,
						mode = "query",
						limit = M.options.sample_rows,
						background = true,
						timeout_ms = 15000,
					}, function(result, run_err)
						if showing ~= token then
							return
						end
						if run_err then
							lines[#lines + 1] = comment(grip.message_of(run_err))
							return finish(lines)
						end
						if not result or #(result.columns or {}) == 0 or #(result.rows or {}) == 0 then
							lines[#lines + 1] = comment("(no rows)")
							return finish(lines)
						end
						local layout = require("neogrip.grid.layout")
						local computed = layout.compute(result.columns, result.rows, {
							max_width = M.options.sample_width,
						})
						vim.list_extend(lines, (layout.render(computed, result.columns, result.rows, {})))
						finish(lines)
					end)
				end)
			end)
		end

		-- The normal case once a database has been swept: everything a definition
		-- is written from is on disk, so there is nothing to wait for and nothing
		-- to debounce. Scrolling a long list of tables has to feel like scrolling
		-- a list, not like asking the server fifty questions.
		local ready = schema.details_ready(connection, catalog, namespace, node.name)
		if ready then
			return draw(ready)
		end
		write({ comment(("reading %s..."):format(node.name)) })
		return debounce(function()
			if showing ~= token then
				return
			end
			tree.details(node.ref, function(details, err)
				if showing ~= token then
					return
				end
				if err or type(details) ~= "table" then
					return finish({ comment(grip.message_of(err or "the server said nothing about this table")) })
				end
				draw(details)
			end)
		end)
	end

	-- A container: a connection, a database or a schema. The header is free --
	-- it is the node and the connection, both already in hand -- so it goes up
	-- first and the listing of what is inside replaces it when it lands.
	local header = ({
		server = server_header,
		instance = instance_header,
		namespace = namespace_header,
	})[node.level] or namespace_header
	local head = header(connection, node)
	write(vim.list_extend(vim.deepcopy(head), { comment("(reading...)") }))

	local function fill()
		if showing ~= token then
			return
		end
		tree.children(node, {}, function(nodes, err)
			if showing ~= token then
				return
			end
			local lines = vim.deepcopy(head)
			if err then
				lines[#lines + 1] = comment(grip.message_of(err))
			elseif not nodes or #nodes == 0 then
				lines[#lines + 1] = comment("(empty)")
			else
				vim.list_extend(lines, listing(nodes))
			end
			finish(lines)
		end)
	end

	if swept(node) then
		return fill()
	end
	return debounce(fill)
end

--- Sample this table's rows from now on, however the options are set.
function M.force_rows(node)
	if node and node.id then
		forced[node.id] = true
	end
end

--- Drop everything drawn and everything remembered. What <C-r> calls, so that
--- "re-read this database" means the pane as well.
function M.forget()
	pane = {}
	counts = {}
	forced = {}
	showing = nil
end

--- The pane's own title: the walk, down to the thing being described.
function M.title_of(node)
	if not node or node.parent then
		return "Contents"
	end
	if node.level == "attribute" then
		return ("%s.%s"):format(grip.path_of(node.ref), node.name)
	end
	if node.level == "server" then
		return grip.path_of(node.ref)
	end
	return grip.path_of(node.ref)
end

--- The Telescope adapter. Thin on purpose: everything above is a node and a
--- buffer, so it can be exercised without a running picker.
function M.previewer()
	local ok, previewers = pcall(require, "telescope.previewers")
	if not ok then
		return nil
	end
	return previewers.new_buffer_previewer({
		title = "Contents",
		dyn_title = function(_, entry)
			return M.title_of(entry and entry.value)
		end,
		define_preview = function(self, entry)
			if entry and entry.value then
				M.render(entry.value, self.state.bufnr)
			end
		end,
	})
end

return M
