-- Defaults for the database client. Anything here can be overridden from
-- init.lua with vim.g.db_config = { ... } before the plugin spec runs.
local M = {}

M.defaults = {
	-- Rows fetched per page. One extra row is always requested to learn whether
	-- another page exists without paying for a count(*).
	limit = 200,
	timeout_ms = 30000,
	-- Columns wider than this are truncated with an ellipsis in the grid; the
	-- yanked and exported value is always the untruncated one.
	max_column_width = 60,
	min_column_width = 3,
	-- Rows scanned when measuring column widths.
	width_sample = 1000,
	null_text = "NULL",
	-- Results materialised as CSV are kept this many days, for the case where
	-- nvim was killed before it could clean up after itself.
	result_retention_days = 2,
	-- Catalog queries are cached per connection for this long.
	schema_ttl_seconds = 3600,
	-- Validate the statement under the cursor on save. The server parses it
	-- and never runs it, so this is safe for every kind of statement.
	validate_on_save = true,
	-- Stop a connection's Java process after this long with nothing to do.
	-- Zero keeps it alive for the whole session.
	idle_timeout_seconds = 1800,
}

local resolved = nil

function M.get()
	if not resolved then
		resolved = vim.tbl_deep_extend("force", M.defaults, vim.g.db_config or {})
	end
	return resolved
end

function M.reload()
	resolved = nil
	return M.get()
end

return M
