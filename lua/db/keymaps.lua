-- ,q is the database prefix: ,d belongs to the debugger and ,b/,B to its
-- breakpoints.
local M = {}

function M.setup()
	local map = function(mode, lhs, rhs, desc)
		vim.keymap.set(mode, lhs, rhs, { noremap = true, silent = true, desc = desc })
	end

	map("n", "<leader>qe", function()
		require("db.explorer").open({})
	end, "DB: explore schema")
	map("n", "<leader>qc", function()
		require("db.resolve").pick()
	end, "DB: pick the connection for this buffer")
	map("n", "<leader>qx", function()
		require("db.execute").cancel()
	end, "DB: cancel the running query")
	map("n", "<leader>qn", function()
		local connection = require("db.resolve").for_buf(0)
		if connection then
			require("db.buffer").new_query(connection, "")
		else
			require("db.resolve").pick(0, function(choice)
				require("db.buffer").new_query(choice, "")
			end)
		end
	end, "DB: new query buffer")
	map("n", "<leader>qd", function()
		require("db.jvm").stop(nil)
		require("db").notify("disconnected from every database")
	end, "DB: disconnect every database")
	map("n", "<leader>qr", function()
		local grid = require("db.grid")
		local bufnr = grid.current_buf()
		if bufnr then
			require("db.grid.duckdb_view").materialise(bufnr)
		end
	end, "DB: query the last result with SQL (DuckDB)")
end

--- Keymaps that only make sense in a buffer holding a query.
function M.attach_query_buffer(bufnr)
	local function map(mode, lhs, rhs, desc)
		vim.keymap.set(mode, lhs, rhs, { buffer = bufnr, noremap = true, silent = true, desc = desc })
	end

	map("n", "<leader>qq", function()
		require("db.execute").run({ bufnr = bufnr })
	end, "DB: run the statement under the cursor")
	map("v", "<leader>qq", function()
		-- Leave visual mode first so the '< '> marks are set.
		vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "nx", false)
		require("db.execute").run({ bufnr = bufnr, visual = true })
	end, "DB: run the selection")
	map("n", "<leader>qv", function()
		require("db.diagnostics").validate({ bufnr = bufnr, notify = true })
	end, "DB: check the statement on the server without running it")
	map("n", "<leader>qw", function()
		local grid = require("db.grid")
		local result = grid.current_buf()
		if result then
			require("db.grid.export").pick(result)
		end
	end, "DB: export the result")
end

return M
