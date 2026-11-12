-- lua/ai/context.lua -- the project context the AI completion sends.
--
-- The checks that matter here are the stability ones. A digest that changes
-- when it should not does not fail: it quietly stops hitting the prompt cache,
-- and the only symptom is a larger bill. Nothing else in the system notices.
local support = require("tests.ai.support")
local context = require("ai.context")

support.describe("ai/context: the index")

local function build()
	context.rebuild()
	support.wait(function()
		local stats = context.stats()
		return not stats.building and stats.chars > 0
	end, 30000)
	return context.stats()
end

-- Two files open, so the current buffer is excluded and one neighbour remains.
vim.cmd.edit("lua/db/execute.lua")
vim.cmd.edit("lua/core/icons.lua")

local stats = build()
support.check("the index found files", stats.files > 50, true)
support.check("the index is not empty", stats.chars > 1000, true)
support.check("the index fits its budget", stats.chars < context.index_budget, true)
support.note(("%d files, %d chars"):format(stats.files, stats.chars))

local digest = context.digest()
support.check("the index section is rendered", digest:find("declarations of every file", 1, true) ~= nil, true)
support.check("the neighbour section is rendered", digest:find("most recently open", 1, true) ~= nil, true)

-- Truncation used to drop whole directories without saying so, because the
-- files were taken in path order until the budget ran out.
support.describe("ai/context: coverage")
for _, directory in ipairs({
	"java/",
	"lua/db/",
	"lua/grip/",
	"lua/plugins/",
	"lua/runner/",
	"lua/servers/",
	"lua/tools/",
	"tests/",
}) do
	support.check(directory .. " is in the index", digest:find("-- " .. directory, 1, true) ~= nil, true)
end

-- A plugin spec declares nothing, so it only appears through the head-of-file
-- fallback. Without that, a third of this repository is missing.
support.check(
	"files that declare nothing still appear",
	digest:find("milanglacier/minuet-ai.nvim", 1, true) ~= nil,
	true
)

support.describe("ai/context: byte stability, which is what the cache needs")

support.check("two calls agree", context.digest() == digest, true)

vim.api.nvim_buf_set_lines(0, 0, 0, false, { "-- an edit in the buffer being completed" })
support.check("typing in the current buffer does not move it", context.digest() == digest, true)

vim.api.nvim_buf_set_lines(0, 0, 1, false, {})

-- Changing which files are open is the one thing that should move it: the
-- neighbours are part of the prefix. One cache write per switch is the price,
-- and it is why the selected set is rendered in path order rather than in
-- recency order -- otherwise returning to a file would rewrite it too.
vim.cmd.buffer("lua/db/execute.lua")
local switched = context.digest()
support.check("switching buffers moves it", switched ~= digest, true)
support.check("and it is stable again after the switch", context.digest() == switched, true)

vim.cmd.buffer("lua/core/icons.lua")
support.check("switching back returns the earlier digest", context.digest() == digest, true)

support.describe("ai/context: the neighbours")

local rendered = {}
for path in digest:gmatch('<file path="([^"]+)">') do
	rendered[#rendered + 1] = path
end
support.check("one neighbour, the file that is not current", #rendered, 1)
support.check("and it is not the current buffer", rendered[1], "lua/db/execute.lua")
