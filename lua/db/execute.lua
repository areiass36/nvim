-- From a keypress to a result: pick the statement, resolve the connection,
-- refuse what must be refused, page it, run it, show it.
local classify = require("db.sql.classify")
local config = require("db.config")
local db = require("db")
local diagnostics = require("db.diagnostics")
local grid = require("db.grid")
local resolve = require("db.resolve")
local runner = require("db.runner")
local split = require("db.sql.split")

local M = {}

local in_flight = {}

--- Flash the statement that is about to run. Seeing the range is the cheapest
--- protection against a splitter mistake sending more than you meant.
local function flash(bufnr, statement)
	if not statement.start_line then
		return
	end
	pcall(
		vim.hl.range,
		bufnr,
		vim.api.nvim_create_namespace("db_flash"),
		"IncSearch",
		{ statement.start_line - 1, 0 },
		{ statement.end_line - 1, -1 },
		{ timeout = 150 }
	)
end

--- Say something only if the query is still running two seconds in. Tied to
--- the handle, not to "is anything running": another connection's query
--- finishing is not news about this one.
local function start_progress(connection, handle)
	vim.defer_fn(function()
		if not handle.done then
			db.notify(("running on %s... (,qx cancels)"):format(connection.name))
		end
	end, 2000)
end

--- A write against a connection that says it is read-only, or production, is a
--- question rather than a command.
--- @return boolean allowed
local function guard(connection, sql, proceed)
	local kind = classify.kind(sql)
	local writes = kind == "dml" or kind == "ddl" or kind == "call"

	if writes and connection.readonly then
		db.notify(
			("%s is read-only; this %s was not run"):format(connection.name, kind),
			vim.log.levels.ERROR
		)
		return
	end

	if writes and classify.unguarded_write(sql) then
		-- No WHERE on an UPDATE or DELETE: ask for the connection name, so a
		-- reflexive Enter cannot do it.
		vim.ui.input({
			prompt = ("This rewrites every row in %s. Type the connection name to run it: "):format(
				connection.name
			),
		}, function(answer)
			if answer == connection.name or answer == connection.id then
				proceed()
			else
				db.notify("cancelled", vim.log.levels.WARN)
			end
		end)
		return
	end

	if writes and connection.production then
		vim.ui.select({ "Run it", "Cancel" }, {
			prompt = ("%s is marked production. Run this %s?"):format(connection.name, kind),
		}, function(choice)
			if choice == "Run it" then
				proceed()
			end
		end)
		return
	end

	proceed()
end

--- @param opts table|nil { bufnr, statement, visual, limit, offset, order_by, descending, on_done }
function M.run(opts)
	opts = opts or {}
	local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
	local statement = opts.statement or (opts.visual and split.selection(bufnr)) or split.at_cursor(bufnr)

	if not statement or vim.trim(statement.text) == "" then
		db.notify("no statement under the cursor", vim.log.levels.WARN)
		return
	end

	local connection, _ = resolve.for_buf(bufnr)
	if not connection then
		return resolve.pick(bufnr, function()
			M.run(opts)
		end)
	end

	flash(bufnr, statement)

	guard(connection, statement.text, function()
		local settings = config.get()
		local limit = opts.limit or connection.limit or settings.limit
		local offset = opts.offset or 0
		-- No driver wants the terminator, and Trino refuses a statement that
		-- carries one. A statement from the splitter never has it; one typed at
		-- :DbRun can.
		local sql = vim.trim((statement.text:gsub(";%s*$", "")))
		-- The statement as the user wrote it, kept aside before anything is
		-- wrapped around it below. `rerun` sends this back through here with
		-- the sort it is re-applying, so it has to be the unwrapped text: a
		-- statement that arrived already wrapped would be wrapped again on
		-- every page step and every change of sort, each layer reusing the
		-- same alias.
		local base_sql = sql

		if opts.order_by then
			-- Sorting is the server's job so it covers every page, not just
			-- the rows already fetched.
			local quoted = require("db.schema").quote(connection.driver, opts.order_by)
			sql = ("SELECT * FROM (%s) AS _nvim_s ORDER BY %s %s"):format(
				sql,
				quoted,
				opts.descending and "DESC" or "ASC"
			)
		end

		-- No LIMIT is spliced into the statement any more: the driver caps the
		-- rows (setMaxRows) and the runner skips the offset, which works the
		-- same whatever the dialect spells it.
		local handle
		handle = runner.run({
			connection = connection,
			sql = sql,
			mode = "query",
			limit = limit,
			offset = offset,
		}, function(result, err)
			in_flight[bufnr] = nil
			if err then
				if err.cancelled then
					return db.notify("cancelled")
				end
				db.notify(err.message, vim.log.levels.ERROR)
				diagnostics.from_error(bufnr, statement, err)
				return
			end
			diagnostics.clear(bufnr)
			result.base_sql = base_sql
			result.order_by = opts.order_by
			result.descending = opts.descending
			grid.show(result, { origin_buf = bufnr, statement = statement, focus = opts.focus })
			if opts.on_done then
				opts.on_done(result)
			end
		end)
		in_flight[bufnr] = handle
		start_progress(connection, handle)
	end)
end

function M.cancel(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local handle = in_flight[bufnr]
	if handle then
		runner.cancel(handle)
		return
	end
	local active = runner.active()
	if #active == 0 then
		db.notify("nothing is running")
		return
	end
	for _, running in ipairs(active) do
		runner.cancel(running)
	end
end

--- Re-run the grid's statement with a different page or order.
local function rerun(state, changes)
	local result = state.result
	M.run(vim.tbl_extend("force", {
		bufnr = state.origin_buf or vim.api.nvim_get_current_buf(),
		statement = { text = result.base_sql or result.sql, start_line = nil },
		limit = result.limit,
		offset = result.offset or 0,
		order_by = result.order_by,
		descending = result.descending,
		focus = false,
	}, changes))
end

function M.page(state, delta)
	local result = state.result
	local limit = result.limit or config.get().limit
	local offset = (result.offset or 0) + delta * limit
	if offset < 0 then
		return db.notify("already on the first page")
	end
	if delta > 0 and not result.has_more then
		return db.notify("no further rows")
	end
	rerun(state, { offset = offset })
end

function M.sort(state, column, descending)
	rerun(state, { order_by = column, descending = descending, offset = 0 })
end

return M
