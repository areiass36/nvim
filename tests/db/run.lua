-- Run the database tests:
--
--   nvim --headless -u tests/minimal.lua -l tests/db/run.lua          (everything)
--   nvim --headless -u tests/minimal.lua -l tests/db/run.lua unit     (no servers)
--
-- The live tests skip themselves when nothing is listening, so the unit tests
-- run anywhere. tests/db/containers.sh up starts the servers.
local support = require("tests.db.support")

local UNIT = {
	"tests.db.unit_codecs",
	"tests.db.unit_sql",
	"tests.db.unit_grid",
	"tests.db.unit_errors",
	"tests.db.unit_connections",
	"tests.db.unit_dsn",
	"tests.db.unit_dialect",
	"tests.db.unit_detail",
	"tests.db.unit_scratch",
	"tests.db.unit_store",
	"tests.db.unit_preview",
	"tests.db.unit_explorer",
	"tests.db.unit_completion",
	"tests.db.unit_identifier",
	"tests.db.unit_lsp",
}

local LIVE = {
	"tests.db.live_jdbc",
	"tests.db.live_flow",
	"tests.db.live_schema",
	"tests.db.live_introspect",
	"tests.db.live_explorer",
	"tests.db.live_diagnostics",
	"tests.db.live_safety",
}

local which = (vim.v.argv[#vim.v.argv] or ""):match("^unit$") and "unit" or "all"
for _, argument in ipairs(vim.v.argv) do
	if argument == "unit" then
		which = "unit"
	end
end

local suites = vim.deepcopy(UNIT)
if which ~= "unit" then
	vim.list_extend(suites, LIVE)
end

require("db.runner").setup()

for _, suite in ipairs(suites) do
	local ok, err = pcall(require, suite)
	if not ok then
		support.fail(suite, tostring(err))
	end
end

io.write(("\n%d checks, %d failures\n"):format(support.checks, support.failures))
os.exit(support.failures == 0 and 0 or 1)
