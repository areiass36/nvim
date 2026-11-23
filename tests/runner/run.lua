-- Run the runner tests:
--
--   nvim --headless -u tests/minimal.lua -l tests/runner/run.lua          (everything)
--   nvim --headless -u tests/minimal.lua -l tests/runner/run.lua unit     (no processes)
--
-- The unit suites are pure: no filesystem beyond tests/runner/fixtures, no
-- jobs, no nvim-dap. The live suites spawn real processes and skip themselves
-- when the tool they need is missing.
local support = require("tests.runner.support")

local UNIT = {
	"tests.runner.unit_schema",
	"tests.runner.unit_address",
	"tests.runner.unit_interp",
	"tests.runner.unit_resolve",
	"tests.runner.unit_link",
	"tests.runner.unit_dap",
	"tests.runner.unit_exclude",
}

local LIVE = {}

local which = "all"
for _, argument in ipairs(vim.v.argv) do
	if argument == "unit" then
		which = "unit"
	end
end

local suites = vim.deepcopy(UNIT)
if which ~= "unit" then
	vim.list_extend(suites, LIVE)
end

for _, suite in ipairs(suites) do
	local ok, err = pcall(require, suite)
	if not ok then
		support.fail(suite, tostring(err))
	end
end

io.write(("\n%d checks, %d failures\n"):format(support.checks, support.failures))
os.exit(support.failures == 0 and 0 or 1)
