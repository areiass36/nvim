-- The database client is now the published neogrip.nvim plus kvstore.nvim for
-- its secrets, in place of the in-config lua/db module. neogrip ships no
-- keymaps on purpose (its ADR-0017), so the whole hotkey layout this config
-- had in lua/db/keymaps.lua and lua/db/grid/navigate.lua is reproduced here,
-- lhs for lhs, pointing at neogrip's public API.
--
-- ,q is the database prefix: ,d belongs to the debugger and ,b/,B to its
-- breakpoints.
return {
	{
		"areiass36/neogrip.nvim",
		lazy = false,
		dependencies = {
			"areiass36/kvstore.nvim",
			-- neogrip requires neither: cmp is a completion source it offers,
			-- and telescope is what lua/grip draws the explorer with.
			"nvim-telescope/telescope.nvim",
			"hrsh7th/nvim-cmp",
		},
		config = function()
			require("kvstore").setup({})
			require("neogrip").setup({})

			local function map(mode, lhs, rhs, desc, bufnr)
				vim.keymap.set(mode, lhs, rhs, {
					noremap = true,
					silent = true,
					desc = desc,
					buffer = bufnr,
				})
			end

			-- Global maps, the same ,q namespace as before.
			--
			-- neogrip ships no explorer (its ADR-0037): it answers the catalog
			-- as data and the client draws it. The one this config draws is
			-- lua/grip/, a Telescope picker you walk into with a pane beside it
			-- -- the file browser's shape, because a database is a tree you
			-- browse and this editor already has a way of browsing trees.
			map("n", "<leader>qe", function()
				require("grip.explorer").open({})
			end, "DB: explore schema")
			map("n", "<leader>qi", function()
				vim.cmd("NGripIntrospect")
			end, "DB: introspect the whole database")
			map("n", "<leader>qc", function()
				require("neogrip.connections.resolve").pick()
			end, "DB: pick the connection for this buffer")
			map("n", "<leader>qx", function()
				require("neogrip.execute").cancel()
			end, "DB: cancel the running query")
			map("n", "<leader>qn", function()
				local resolve = require("neogrip.connections.resolve")
				local connection = resolve.for_buf(0)
				if connection then
					require("neogrip.ui.buffer").new_query(connection, "")
				else
					resolve.pick(0, function(choice)
						require("neogrip.ui.buffer").new_query(choice, "")
					end)
				end
			end, "DB: new query buffer")
			map("n", "<leader>qd", function()
				vim.cmd("NGripDisconnect!")
			end, "DB: disconnect every database")
			map("n", "<leader>qr", function()
				local grid = require("neogrip.grid")
				local bufnr = grid.current_buf()
				if bufnr then
					require("neogrip.grid.requery").materialise(bufnr)
				end
			end, "DB: query the last result with SQL (DuckDB)")

			-- Query-buffer maps. The in-config module attached these on its own
			-- FileType hook; neogrip leaves it to the user, so this is that hook.
			vim.api.nvim_create_autocmd("FileType", {
				group = vim.api.nvim_create_augroup("NeogripQueryMaps", { clear = true }),
				pattern = { "sql", "mysql", "plsql", "mongodb" },
				callback = function(event)
					local buf = event.buf
					map("n", "<leader>qq", function()
						require("neogrip.execute").run({ bufnr = buf })
					end, "DB: run the statement under the cursor", buf)
					map("v", "<leader>qq", function()
						-- Leave visual mode first so '< '> are set.
						vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "nx", false)
						require("neogrip.execute").run({ bufnr = buf, visual = true })
					end, "DB: run the selection", buf)
					map("n", "<leader>qv", function()
						require("neogrip.diagnostics").validate({ bufnr = buf, notify = true })
					end, "DB: check the statement on the server without running it", buf)
					map("n", "<leader>qw", function()
						local grid = require("neogrip.grid")
						local result = grid.current_buf()
						if result then
							require("neogrip.grid.export").pick(result)
						end
					end, "DB: export the result", buf)
				end,
			})

			-- Result-grid maps, reproducing lua/db/grid/navigate.lua against the
			-- public neogrip.grid.actions API on neogrip's own grid filetype.
			vim.api.nvim_create_autocmd("FileType", {
				group = vim.api.nvim_create_augroup("NeogripGridMaps", { clear = true }),
				pattern = "neogrip-grid",
				callback = function(event)
					local buf = event.buf
					local a = require("neogrip.grid.actions")
					local grid_maps = {
						{ "<Tab>", a.next_column, "Grid: next column" },
						{ "<S-Tab>", a.prev_column, "Grid: previous column" },
						{ "l", a.next_column, "Grid: next column" },
						{ "h", a.prev_column, "Grid: previous column" },
						{ "j", a.down, "Grid: next row" },
						{ "k", a.up, "Grid: previous row" },
						{ "0", a.first_column, "Grid: first column" },
						{ "$", a.last_column, "Grid: last column" },
						{ "gg", a.first_row, "Grid: first row" },
						{ "G", a.last_row, "Grid: last row" },
						{ "y", a.yank_cell, "Grid: yank cell" },
						{ "Y", a.yank_row, "Grid: yank row" },
						{ "<leader>qC", a.yank_column, "Grid: yank column" },
						{ "s", a.sort_asc, "Grid: sort by this column" },
						{ "S", a.sort_desc, "Grid: sort by this column, descending" },
						-- The grid loads the next batch on its own as the cursor
						-- nears the last row, so these two are for going by hand:
						-- rows accumulate and a batch is what the server handed over.
						{ "]p", a.page_next, "Grid: load a batch" },
						{ "[p", a.page_prev, "Grid: back a batch" },
						-- Every query now gets its own tab in the one result
						-- window, so a second statement no longer destroys the
						-- rows you were reading. These walk between them; the
						-- strip in the result window's winbar names each tab
						-- by its SQL and marks the one on screen.
						{ "]t", a.next_tab, "Grid: next result tab" },
						{ "[t", a.prev_tab, "Grid: previous result tab" },
						{ "gf", a.follow_fk, "Grid: follow this foreign key" },
						{ "<CR>", a.show_document, "Grid: show the whole document (Mongo)" },
						{ "q", a.close, "Grid: close" },
						{ "<Esc>", a.close, "Grid: close" },
						{ "e", a.export, "Grid: export" },
						{ "d", a.materialise, "Grid: query this result with SQL (DuckDB)" },
					}
					for _, entry in ipairs(grid_maps) do
						map("n", entry[1], entry[2], entry[3], buf)
					end
				end,
			})
		end,
	},
}
