-- The path a keypress takes: statement under the cursor, grid, CSV, DuckDB.
local support = require("tests.db.support")
local check, note = support.check, support.note
local db = require("db")

local connections = support.connections()
local pg = connections.postgres

support.describe("live/flow")
if not support.reachable(pg) then
	note("skipped: nothing listening (tests/db/containers.sh up)")
	return
end

local execute = require("db.execute")
local grid = require("db.grid")
local resolve = require("db.resolve")
local connections_module = require("db.connections")

-- Make the test connection resolvable by id, the way a project file would.
local saved_get = connections_module.get
connections_module.get = function(id)
	if id == pg.id then
		return pg
	end
	return saved_get(id)
end

local bufnr = vim.api.nvim_create_buf(false, true)
vim.bo[bufnr].filetype = "sql"
vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
	"-- a comment with a ; in it",
	"select id, s_comma, s_null, cjk from torture order by id;",
	"",
	"select count(*) as n from torture;",
})
vim.api.nvim_set_current_buf(bufnr)
resolve.bind(bufnr, pg.id)

vim.api.nvim_win_set_cursor(0, { 2, 0 })
local ran = support.sync(function(done)
	execute.run({ bufnr = bufnr, on_done = done })
end)
check("the first statement ran", ran ~= nil, true)

local result_buf = grid.current_buf()
check("a grid was opened", result_buf ~= nil, true)
local state = grid.state(result_buf)
check("columns", state.columns, { "id", "s_comma", "s_null", "cjk" })
check("rows", #state.rows, 2)
check("NULL is kept as NULL in the state", state.rows[1][3] == db.NULL, true)

local lines = vim.api.nvim_buf_get_lines(result_buf, 0, -1, false)
check("the header names a column", lines[1]:find("s_comma") ~= nil, true)
check("NULL is drawn", lines[3]:find("NULL") ~= nil, true)
check("the footer names the connection", lines[#lines]:find(pg.name, 1, true) ~= nil, true)
check("the result buffer is its own filetype", vim.bo[result_buf].filetype, "dbresult")
check("and not editable", vim.bo[result_buf].modifiable, false)

support.describe("live/flow: the cursor picks the statement")
vim.api.nvim_set_current_buf(bufnr)
vim.api.nvim_win_set_cursor(0, { 4, 0 })
support.sync(function(done)
	execute.run({ bufnr = bufnr, on_done = done })
end)
state = grid.state(grid.current_buf())
check("the second statement ran", state.columns, { "n" })
check("its value", state.rows[1][1], 2)

support.describe("live/flow: taking values out")
vim.api.nvim_set_current_buf(bufnr)
vim.api.nvim_win_set_cursor(0, { 2, 0 })
support.sync(function(done)
	execute.run({ bufnr = bufnr, on_done = done })
end)
result_buf = grid.current_buf()
state = grid.state(result_buf)
local navigate = require("db.grid.navigate")

state.row, state.column = 1, 2
navigate.yank_cell(result_buf)
check("a cell yanks its stored value", vim.fn.getreg('"'), "a,b")
state.column = 3
navigate.yank_cell(result_buf)
check("a NULL cell", vim.fn.getreg('"'), "NULL")
navigate.yank_row(result_buf)
check("a row yanks as csv", vim.fn.getreg('"'), '1,"a,b",,日本語テキスト')
state.column = 4
navigate.yank_column(result_buf)
check("a column yanks every value", vim.fn.getreg('"'), "日本語テキスト\n中文")

-- A truncated cell must still yank in full.
local long = string.rep("z", 300)
state.rows[1][2] = long
grid.refresh(result_buf)
state.row, state.column = 1, 2
navigate.yank_cell(result_buf)
check("a truncated cell yanks untruncated", vim.fn.getreg('"'), long)
state.rows[1][2] = "a,b"
grid.refresh(result_buf)

support.describe("live/flow: cell navigation")
state.row, state.column = 1, 1
navigate.move(result_buf, 0, 1)
check("moving right", state.column, 2)
navigate.move(result_buf, 1, 0)
check("moving down", state.row, 2)
navigate.move(result_buf, 5, 5)
check("stops at the last row", state.row, #state.rows)
check("and the last column", state.column, #state.columns)
navigate.move(result_buf, -10, -10)
check("and at the first", { state.row, state.column }, { 1, 1 })

support.describe("live/flow: the result becomes a queryable CSV")
local export = require("db.grid.export")
local duckdb_view = require("db.grid.duckdb_view")
local path = ("%s/test.csv"):format(export.results_dir())
export.page_to_csv(state, path)
check("a csv was written", vim.fn.filereadable(path), 1)
local csv_lines = vim.fn.readfile(path)
check("with a header", csv_lines[1], "id,s_comma,s_null,cjk")
check("and the null marker", csv_lines[2]:find("\\N", 1, true) ~= nil, true)

local view, register_err = support.sync(function(done)
	duckdb_view.register(path, { name = "testview" }, function(name, err)
		done(name, err)
	end)
end)
check("registered as a view", view, "testview")
if register_err then
	note(tostring(register_err))
end

local count = support.scalar(duckdb_view.connection(), "select count(*) from testview")
check("the view has the rows", count, 2)
local cjk = support.scalar(duckdb_view.connection(), "select max(cjk) from testview")
check("utf-8 survived the round trip", cjk, "日本語テキスト")
local nulls = support.scalar(duckdb_view.connection(), "select count(*) from testview where s_null is null")
check("and so did NULL, as NULL", nulls, 2)
local commas = support.scalar(duckdb_view.connection(), "select count(*) from testview where s_comma = 'a,b'")
check("a comma inside a value survived", commas, 1)

support.describe("live/flow: column names are made safe for SQL")
check(
	"mixed case and punctuation",
	export.safe_columns({ "Total $", "count(*)", "1st" }),
	{ "total__", "count___", "c_1st" }
)
check("duplicates are numbered", export.safe_columns({ "a", "a", "a" }), { "a", "a_2", "a_3" })

support.describe("live/flow: paging")
-- A table with more rows than one page.
support.run(pg, "drop table if exists paging")
support.run(pg, "create table paging as select generate_series(1, 25) as n", { mode = "exec" })

local paging_buf = vim.api.nvim_create_buf(false, true)
vim.bo[paging_buf].filetype = "sql"
vim.api.nvim_buf_set_lines(paging_buf, 0, -1, false, { "select n from paging order by n;" })
vim.api.nvim_set_current_buf(paging_buf)
resolve.bind(paging_buf, pg.id)

support.sync(function(done)
	execute.run({ bufnr = paging_buf, limit = 10, on_done = done })
end)
local page_buf = grid.current_buf()
state = grid.state(page_buf)
check("a full page", #state.rows, 10)
check("first row", state.rows[1][1], 1)
check("and there is more", state.result.has_more, true)
check(
	"the footer says which rows",
	vim.api
		.nvim_buf_get_lines(page_buf, 0, -1, false)[#vim.api.nvim_buf_get_lines(page_buf, 0, -1, false)]
		:find("1%-10") ~= nil,
	true
)

local before_rows = vim.deepcopy(state.rows)
execute.page(state, 1)
support.wait(function()
	local current = grid.state(grid.current_buf())
	return current and current.rows[1] and current.rows[1][1] ~= before_rows[1][1]
end, 20000)
state = grid.state(grid.current_buf())
check("the next page starts where the last ended", state.rows[1][1], 11)
check("and still has more", state.result.has_more, true)

execute.page(state, 1)
support.wait(function()
	local current = grid.state(grid.current_buf())
	return current and current.rows[1] and current.rows[1][1] == 21
end, 20000)
state = grid.state(grid.current_buf())
check("the last page is short", #state.rows, 5)
check("and says so", state.result.has_more, false)

execute.page(state, -1)
support.wait(function()
	local current = grid.state(grid.current_buf())
	return current and current.rows[1] and current.rows[1][1] == 11
end, 20000)
check("and going back works", grid.state(grid.current_buf()).rows[1][1], 11)

support.describe("live/flow: sorting is done by the server")
state = grid.state(grid.current_buf())
execute.sort(state, "n", true)
support.wait(function()
	local current = grid.state(grid.current_buf())
	return current and current.rows[1] and current.rows[1][1] == 25
end, 20000)
state = grid.state(grid.current_buf())
check("descending starts at the highest row of the whole table", state.rows[1][1], 25)
check("not just of the page", state.result.offset, 0)
support.run(pg, "drop table if exists paging", { mode = "exec" })

connections_module.get = saved_get

support.describe("live/flow: a materialised result is queried through its own connection")
local view_connection = duckdb_view.connection()
check("the scratch connection is registered", connections_module.get(view_connection.id) ~= nil, true)
local scratch_query = require("db.buffer").new_query(view_connection, "select 1 as a;")
check("a buffer opened on it resolves to it", resolve.for_buf(scratch_query).id, view_connection.id)
check("and not to the project's database", resolve.for_buf(scratch_query).driver, "duckdb")
