-- The list half of the explorer: what a row reads as, what the keys would act
-- on, and the walk itself, driven over a swept catalog on disk rather than a
-- keyboard. No picker is opened: everything here is a node in and a string out,
-- which is the whole reason the row, the hint and the title live in functions.
local support = require("tests.grip.support")
local check = support.check

local explorer = require("grip.explorer")
local grip = require("grip")
local icons = require("core.icons")
local tree = require("neogrip.tree")

support.describe("rows")

local shop = support.swept_connection({ name = "Shop", database = "shop" })
local server = support.server_node(shop)
local public = support.child(server, "public")
local customers = support.child(public, "customers")
local view = support.child(public, "active_customers")
local id = support.child(customers, "id")
local email = support.child(customers, "email")

check("a connection draws the server icon", grip.icon_of(server), icons.server)
check("a schema draws the layer icon", grip.icon_of(public), icons.schema)
check("a table draws the rows icon", grip.icon_of(customers), icons.set)
check("a view says it is one", grip.icon_of(view), icons.view)
check("a column draws the columns icon", grip.icon_of(email), icons.column)
check("a primary key column draws a key", grip.icon_of(id), icons.key)
check("an instance draws a database", grip.icon_of({ level = "instance", kind = "database" }), icons.database)
check("a collection draws braces", grip.icon_of({ level = "set", kind = "collection" }), icons.collection)
check("the way back draws an arrow", grip.icon_of({ parent = true }), icons.up)

check("a name is drawn after its icon", grip.display(customers), ("%s customers"):format(icons.set))
check("a connection hints at the driver and where it points", grip.hint_of(server), "postgres  db.example.test:5432")
check("a table hints at what is in it", grip.hint_of(customers), "3 columns  People who buy things")
check("a view hints that it is one", grip.hint_of(view), "view  1 column")
check("a column hints at its type and its flags", grip.hint_of(id), "bigint  PK  NOT NULL")
check("a schema has nothing to add", grip.hint_of(public), "")
check("a hintless row is just the name", explorer.row(public), ("%s public"):format(icons.schema))
check(
	"a hinted row is padded to a column",
	explorer.row(customers),
	("%-40s %s"):format(("%s customers"):format(icons.set), "3 columns  People who buy things")
)

support.describe("the glyphs it draws")

-- The font is built from assets/icons/map.json and lua/core/icons.lua has to
-- mirror it (scripts/icon-font/README.md): a name in one and not the other
-- renders as a missing-glyph box in every row of this picker, which is the kind
-- of mistake nobody notices until the explorer is open.
local map = {}
for _, entry in ipairs(vim.json.decode(table.concat(vim.fn.readfile(
	vim.fn.stdpath("config") .. "/assets/icons/map.json"
), "\n"))) do
	map[entry.name] = entry.codepoint
end
local missing = {}
for _, name in ipairs({ "server", "database", "schema", "set", "view", "collection", "column", "key", "up" }) do
	local glyph = icons[name]
	if not glyph or map[name] ~= vim.fn.char2nr(glyph) then
		missing[#missing + 1] = name
	end
end
check("every level's icon is in the font's source map", missing, {})

support.describe("the walk")

check("a connection holds its schemas", vim.tbl_map(function(node)
	return node.name
end, support.children(server)), { "public", "audit" })
check("the level is the engine's", support.children(server)[1].level, "namespace")
check("a schema holds its tables", vim.tbl_map(function(node)
	return node.name
end, support.children(public)), { "customers", "orders", "active_customers" })
check("and says what each one is", vim.tbl_map(function(node)
	return node.kind
end, support.children(public)), { "table", "table", "view" })
check("a table holds its columns", vim.tbl_map(function(node)
	return node.name
end, support.children(customers)), { "id", "email", "created_at" })
check("a column is the end of the walk", support.children(id), {})
check("everything came off the disk", support.children(public)[1].source, "cache")

support.describe("the way back")

local root = { node = nil, level = "server", label = "Connections" }
local level = { node = server, level = "namespace", label = "Schemas" }

check("the first level has no way out", explorer.with_parent({ public }, {}), { public })
local with_parent = explorer.with_parent({ public }, { root })
check("a level below it does", with_parent[1].text, ".. Connections")
check("and keeps its own rows after it", with_parent[2], public)
check("the row says where it goes", explorer.with_parent({ public }, { level })[1].text, ".. Schemas")

support.describe("titles")

check("the root is the connection list", explorer.title(root), "Connections")
check("a level names itself and the walk", explorer.title(level), "Schemas  Shop")
check("deeper still, the whole path", explorer.title({ node = public, label = "Tables" }), "Tables  Shop/public")
check("a table hangs off its schema with a dot", grip.path_of(customers.ref), "Shop/public.customers")

support.describe("names, as SQL")

check("a table is qualified and quoted", explorer.name_of(customers), '"public"."customers"')
check("a column is only quoted", explorer.name_of(email), '"email"')
check("a schema is its own name", explorer.name_of(public), "public")
check("the way back is nothing", explorer.name_of({ parent = true }), "")

support.describe("labels, per engine")

local mongo = support.connection({ driver = "mongodb", database = "shop" })
-- An empty database, not a nil one: nil is absent from a Lua table, so it would
-- leave the default in place. "" is how a connection file says "not chosen"
-- anyway, and it is what neogrip reads everywhere.
local trino = support.connection({ driver = "trino", database = "" })
check("postgres calls them schemas", grip.label_of(shop, "namespace"), "Schemas")
check("postgres calls them tables", grip.label_of(shop, "set"), "Tables")
check("mongodb calls them collections", grip.label_of(mongo, "set"), "Collections")
check("mongodb calls them fields", grip.label_of(mongo, "attribute"), "Fields")
check("trino calls its instances catalogs", grip.label_of(trino, "instance"), "Catalogs")
check("nothing above a connection", grip.label_of(nil, nil), "Connections")

support.describe("the two qualifiers")

local catalog, namespace = grip.qualifiers(shop, { server = shop.id, namespace = "public" })
check("postgres: the database is the catalog", { catalog, namespace }, { "shop", "public" })
catalog, namespace = grip.qualifiers(shop, { server = shop.id, instance = "other", namespace = "public" })
check("and a chosen one wins", { catalog, namespace }, { "other", "public" })
local mysql = support.connection({ driver = "mysql", database = "shop" })
catalog, namespace = grip.qualifiers(mysql, { server = mysql.id })
check("mysql: the database stands in for the schema", { catalog, namespace }, { nil, "shop" })
catalog, namespace = grip.qualifiers(mysql, { server = mysql.id, instance = "warehouse" })
check("and a chosen database with it", { catalog, namespace }, { nil, "warehouse" })

support.describe("walking into a database")

local instance = {
	level = "instance",
	kind = "database",
	name = "warehouse",
	ref = { server = shop.id, instance = "warehouse" },
	facts = { reconnects = true },
}
local walked = explorer.walk_into(instance)
check("postgres reopens the connection", walked.level, "server")
check("under an id of its own", walked.ref.server, shop.id .. "/warehouse")
local derived = require("neogrip.connections").get(walked.ref.server)
check("pointed at the chosen database", derived and derived.database, "warehouse")
check("keeping how to reach it", derived and derived.host, shop.host)
check("and how to log in", derived and derived.auth and derived.auth.user, "tester")
check("the name says both", derived and derived.name, "Shop · warehouse")
check("asked twice, it is the same connection", explorer.walk_into(instance).ref.server, walked.ref.server)

local same = vim.tbl_extend("force", instance, { name = "shop", ref = { server = shop.id, instance = "shop" } })
check("the database it is already on is walked into directly", explorer.walk_into(same).level, "instance")

local catalog_node = {
	level = "instance",
	kind = "catalog",
	name = "minio",
	ref = { server = trino.id, instance = "minio" },
	facts = {},
}
check("trino walks in without reopening anything", explorer.walk_into(catalog_node).level, "instance")
check("a table is never a reconnect", explorer.walk_into(customers).level, "set")

support.describe("what a sweep would cover")

check("a connection that names its database: the whole of it", explorer.sweep_target(shop, server).server, shop.id)
check(
	"a connection that does not: nothing yet",
	explorer.sweep_target(trino, support.server_node(trino)),
	nil
)
check(
	"once a catalog is chosen: that catalog",
	explorer.sweep_target(trino, catalog_node).instance,
	"minio"
)
check("a collection catalog cannot be swept at all", explorer.sweep_target(mongo, support.server_node(mongo)), nil)
check("and neither can a schema", explorer.sweep_target(shop, public), nil)

support.describe("statements")

local text = support.sync(function(done)
	tree.statement(customers.ref, "select", done)
end)
check("a SELECT names the table the engine's way", text, 'SELECT * FROM "public"."customers"')
text = support.sync(function(done)
	tree.statement(customers.ref, "delete", done)
end)
check("a DELETE comes with its WHERE written", text:find('WHERE "id" = :id', 1, true) ~= nil, true)

return support
