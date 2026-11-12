-- Run the debugger tests:
--
--   nvim --headless -u tests/minimal.lua -l tests/debugger/run.lua
--
-- Unlike the runner suites these need the real nvim-dap, nvim-dap-ui and nio:
-- the windows are the thing under test. tests/minimal.lua ships no plugin
-- manager, so they are taken from where lazy.nvim downloads them and the suite
-- skips itself when they are not there.
local support = require("tests.debugger.support")

local PLUGINS = { "nvim-dap", "nvim-dap-ui", "nvim-nio" }
local lazy = vim.fn.stdpath("data") .. "/lazy/"

local missing = {}
for _, plugin in ipairs(PLUGINS) do
	if vim.fn.isdirectory(lazy .. plugin) == 1 then
		vim.opt.rtp:append(lazy .. plugin)
	else
		missing[#missing + 1] = plugin
	end
end

if #missing > 0 then
	support.note(("skipped: %s not installed"):format(table.concat(missing, ", ")))
	os.exit(0)
end

local ok, err = pcall(require, "tests.debugger.unit_floats")
if not ok then
	support.fail("tests.debugger.unit_floats", tostring(err))
end

io.write(("\n%d checks, %d failures\n"):format(support.checks, support.failures))
os.exit(support.failures == 0 and 0 or 1)
