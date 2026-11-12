-- The vocabulary the database explorer and its preview pane share.
--
-- neogrip answers the catalog as data and draws nothing: a node is
-- { id, level, kind, name, ref, expandable, source, facts } and none of it is
-- formatted for a human -- facts.columns is a number, not "12 columns", and no
-- icon is chosen for you (its ADR-0036 and ADR-0037). Turning a node into
-- something you can read is the client's job, and this is where this client
-- does it, in one place, so the list and the pane beside it can never disagree
-- about what a thing is or what it is called.
--
-- The six levels, and what each one is in SQL:
--
--   server      a configured connection
--   instance    one of its databases, or a Trino catalog
--   namespace   a schema
--   set         a table, a view, or a MongoDB collection
--   object      a row -- data, so the pane samples it and the list never lists it
--   attribute   a column
local icons = require("core.icons")

local M = {}

-- One icon per level, in the order you walk them: a connection is a server,
-- one of its databases is a database, a schema is a stack of layers, a table is
-- a sheet of rows, a column is a sheet of columns.
M.LEVEL_ICON = {
	server = icons.server,
	instance = icons.database,
	namespace = icons.schema,
	set = icons.set,
	object = icons.set,
	attribute = icons.column,
}

-- Where what a thing *is* says more than which level it sits at. The set level
-- holds tables, views and -- on MongoDB -- collections, and neogrip collapses
-- every other reported kind into those three, so three entries is the whole
-- mapping and no unknown kind can arrive.
M.KIND_ICON = {
	view = icons.view,
	collection = icons.collection,
}

--- "1 table", not "1 tables". A count in a hint is read, not parsed.
function M.counted(amount, noun)
	return ("%d %s%s"):format(amount, noun, amount == 1 and "" or "s")
end

--- A reported string on one line, or nil when there is nothing in it.
---
--- Flattened because a table remark runs over several lines and a buffer line
--- cannot hold one; truncated because a hint shares its line with a name.
function M.said(value, width)
	if value == nil or value == vim.NIL then
		return nil
	end
	local text = vim.trim((tostring(value):gsub("%s+", " ")))
	if text == "" or text == "nil" then
		return nil
	end
	if width and #text > width then
		return text:sub(1, width - 1) .. "…"
	end
	return text
end

--- What a failure says, whichever of the two shapes it arrives in: neogrip
--- answers errors as { message }, and a guard in this config may answer with a
--- plain string.
function M.message_of(err)
	if type(err) == "table" then
		return tostring(err.message or vim.inspect(err))
	end
	return tostring(err)
end

--- Where a connection points, short enough to sit in a hint.
function M.where_of(connection)
	if not connection then
		return nil
	end
	if connection.file then
		return vim.fn.fnamemodify(connection.file, ":t")
	end
	if connection.host and connection.host ~= "" then
		if connection.port then
			return ("%s:%s"):format(connection.host, connection.port)
		end
		return connection.host
	end
	return nil
end

--- How long ago, in the roundest unit that still says something.
function M.ago(seconds)
	seconds = math.max(math.floor(tonumber(seconds) or 0), 0)
	if seconds < 90 then
		return "just now"
	end
	for _, step in ipairs({ { 3600, 60, "minute" }, { 86400, 3600, "hour" }, { math.huge, 86400, "day" } }) do
		if seconds < step[1] then
			return M.counted(math.floor(seconds / step[2]), step[3]) .. " ago"
		end
	end
	return "a while ago"
end

--- How this engine wants a ref's two qualifiers passed to the schema layer.
---
--- The one piece of engine knowledge neogrip keeps to itself: its tree.lua has
--- this same mapping privately, because every public call it makes on a ref
--- goes through it. The cache predicates (schemas_known, tables_known,
--- details_ready) are public and take the two qualifiers, not a ref, so asking
--- "is this already on disk?" -- which is what decides whether the pane draws
--- now or waits for the cursor to rest -- needs the mapping here too.
---
--- MySQL, MariaDB and MongoDB report their databases as catalogs and have no
--- schema layer, so the database goes where every other engine puts its schema.
--- @return string|nil catalog, string|nil namespace
function M.qualifiers(connection, ref)
	ref = ref or {}
	local driver = connection.driver
	if driver == "mysql" or driver == "mariadb" or driver == "mongodb" then
		local database = connection.database
		return nil, ref.instance or (database ~= nil and database ~= "" and database or nil)
	end
	return ref.instance or require("neogrip.catalog").catalog_of(connection), ref.namespace
end

--- The icon for a node: what it is, falling back to the level it sits at.
function M.icon_of(node)
	if node.parent then
		return icons.up
	end
	local facts = node.facts or {}
	if node.level == "attribute" and facts.is_pk then
		-- The one column of a table worth finding at a glance.
		return icons.key
	end
	return M.KIND_ICON[node.kind] or M.LEVEL_ICON[node.level] or icons.file
end

--- The row as it reads in the list: an icon and a name.
function M.display(node)
	if node.parent then
		return ("%s %s"):format(icons.up, node.text)
	end
	return ("%s %s"):format(M.icon_of(node), node.name)
end

--- Whatever is worth knowing about a node that its name does not already say.
---
--- Free, every one of them: a hint is read off the node neogrip already
--- answered with, never fetched. Anything that would cost a round trip belongs
--- in the pane, where the cursor has to rest before it is asked for.
function M.hint_of(node)
	if node.parent then
		return ""
	end
	local facts = node.facts or {}
	local parts = {}

	local function add(value)
		local text = M.said(value, 44)
		if text then
			parts[#parts + 1] = text
		end
	end

	if node.level == "server" then
		-- The kind of a server is its driver, which is the first thing you want
		-- to know about a connection you are about to walk into.
		add(node.kind)
		add(M.where_of(require("neogrip.connections").get(node.ref.server)))
		if facts.production then
			add("production")
		end
		if facts.readonly then
			add("read-only")
		end
		if facts.connected then
			add("connected")
		end
	elseif node.level == "set" then
		if node.kind ~= "table" then
			add(node.kind)
		end
		if facts.columns then
			add(M.counted(facts.columns, "column"))
		end
		add(facts.remarks)
	elseif node.level == "attribute" then
		add(facts.type)
		if facts.is_pk then
			add("PK")
		end
		if facts.nullable == false or facts.nullable == 0 then
			add("NOT NULL")
		end
		if facts.count then
			-- A sampled collection field: how many of the documents carried it.
			add(M.counted(facts.count, "doc"))
		end
		add(facts.remarks)
	end

	return table.concat(parts, "  ")
end

--- How this engine names the level, for a title: "Schemas" on PostgreSQL,
--- "Collections" on MongoDB, "Catalogs" for Trino's instances.
function M.label_of(connection, level)
	if not connection or not level then
		return "Connections"
	end
	for _, entry in ipairs(require("neogrip.catalog.tree").shape(connection).levels) do
		if entry.level == level then
			return entry.label
		end
	end
	return level
end

--- The walk so far, spelled out for the picker's title.
function M.path_of(ref)
	if not ref or not ref.server then
		return ""
	end
	local connection = require("neogrip.connections").get(ref.server)
	local path = connection and (connection.name or connection.id) or ref.server
	for _, key in ipairs({ "instance", "namespace" }) do
		if ref[key] then
			path = ("%s/%s"):format(path, ref[key])
		end
	end
	if ref.set then
		path = ("%s.%s"):format(path, ref.set)
	end
	return path
end

return M
