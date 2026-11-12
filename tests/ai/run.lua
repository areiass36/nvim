-- Run the AI context tests:
--
--   nvim --headless -u tests/minimal.lua -l tests/ai/run.lua
--
-- The suites are pure: they read this repository from disk and build the real
-- index, but they never reach the network and never need an API key. What they
-- cannot check is whether the prefix is actually cached, since only a response
-- from the API says that -- see the note in tests/ai/unit_context.lua.
local support = require("tests.ai.support")

local UNIT = {
	"tests.ai.unit_context",
}

for _, suite in ipairs(UNIT) do
	local ok, err = pcall(require, suite)
	if not ok then
		support.fail(suite, tostring(err))
	end
end

io.write(("\n%d checks, %d failures\n"):format(support.checks, support.failures))
os.exit(support.failures == 0 and 0 or 1)
