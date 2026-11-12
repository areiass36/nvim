-- A database client in the editor: pick which database a file or folder runs
-- against, run the statement under the cursor, read the result in a grid, and
-- turn that result into a CSV you can query again with SQL.
--
-- The pieces, in the order setup() wires them:
--
--   connections  the three config levels (global, project, per file)
--   secrets      passwords, from the OS keyring or the environment
--   jvm          one Java process per connection, kept alive
--   runner       statements queued per connection, cancelled on the server
--   grid         the result buffer
--   explorer     the Telescope schema picker
--   document     db:// buffers: a table's definition, a schema's contents
--   lsp          go to definition, hover and symbols, from the swept catalog
--   diagnostics  validates a statement on the server without running it
local M = {}

M.state_dir = vim.fn.stdpath("state") .. "/db"

-- SQL NULL. A unique table rather than nil (which would leave a hole in a row
-- array) and rather than "" (which is a different value, and saying otherwise
-- turns a correct "where x is null" into a wrong one).
M.NULL = setmetatable({}, {
	__tostring = function()
		return "NULL"
	end,
})

--- Every message the module shows the user. Scheduled because most callers are
--- vim.system callbacks, where vim.notify is not allowed to run directly.
function M.notify(message, level)
	vim.schedule(function()
		vim.notify("[db] " .. message, level or vim.log.levels.INFO)
	end)
end

function M.setup()
	vim.fn.mkdir(M.state_dir, "p")
	require("db.connections").setup()
	require("db.resolve").setup()
	require("db.runner").setup()
	require("db.grid.duckdb_view").setup()
	require("db.dialect").setup()
	-- Before buffer, which attaches to the sql buffers already open: the
	-- language server starts from there, and db:// documents have to be
	-- readable before anything can jump to one.
	require("db.document").setup()
	require("db.lsp").setup()
	require("db.buffer").setup()
	require("db.diagnostics").setup()
	require("db.completion").setup()
	require("db.commands").setup()
	require("db.keymaps").setup()
end

return M
