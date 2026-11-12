-- Run the database explorer tests:
--
--   nvim --headless -u tests/minimal.lua -l tests/grip/run.lua
--
-- Nothing here reaches a database. The explorer is exercised over a fixture
-- snapshot written into a temporary state directory, which is where a swept
-- catalog lives, so every level of the walk and every pane beside it is
-- answered from disk -- no server, no JVM, no network. The suites skip
-- themselves when neogrip is not installed yet, since this config carries no
-- copy of the plugin it draws.
local support = require("tests.grip.support")

local UNIT = {
	"tests.grip.unit_explorer",
	"tests.grip.unit_preview",
	-- Last: it opens a real Telescope window, and the suites before it are
	-- better off without one on screen.
	"tests.grip.unit_picker",
}

if not support.available() then
	io.write(("\nskipped: neogrip is not installed in %s\n"):format(support.plugin_dir))
	os.exit(0)
end

support.setup()

for _, suite in ipairs(UNIT) do
	local ok, err = pcall(require, suite)
	if not ok then
		support.fail(suite, tostring(err))
	end
end

support.teardown()

io.write(("\n%d checks, %d failures\n"):format(support.checks, support.failures))
os.exit(support.failures == 0 and 0 or 1)
