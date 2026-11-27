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

-- Everything below builds its own directories, because what it checks is what
-- happens outside this repository: with no git to list the files, and with no
-- project at all.
local function write(path, lines)
	vim.fn.mkdir(vim.fs.dirname(path), "p")
	vim.fn.writefile(lines, path)
end

local function settle()
	support.wait(function()
		return not context.stats().building
	end, 30000)
end

local home = vim.uv.cwd()
local scratch = vim.uv.fs_realpath(vim.fn.fnamemodify(vim.fn.tempname(), ":h"))

support.describe("ai/context: the walk, for a project git cannot list")

local project = scratch .. "/ai-context-walk"
vim.fn.delete(project, "rf")
write(project .. "/lazy-lock.json", { "{}" })
write(project .. "/src/kept.lua", { "local function kept() end" })
write(project .. "/node_modules/top.lua", { "local function vendored_top() end" })
write(project .. "/packages/web/node_modules/nested.lua", { "local function vendored_nested() end" })
write(project .. "/packages/web/dist/bundle.lua", { "local function bundled() end" })
write(project .. "/a/b/c/d/e/f/too_deep.lua", { "local function too_deep() end" })

vim.cmd.edit(project .. "/src/kept.lua")
settle()
context.rebuild()
settle()

local walked = context.digest()
support.check("the root is the marker's directory", context.stats().root, project)
support.check("a project file is indexed", walked:find("-- src/kept.lua", 1, true) ~= nil, true)
support.check("a skipped directory at the root is left out", walked:find("vendored_top", 1, true), nil)
support.check("a skipped directory further down is left out", walked:find("vendored_nested", 1, true), nil)
support.check("so is one with another name", walked:find("bundled", 1, true), nil)
support.check("the walk stops at its depth", walked:find("too_deep", 1, true), nil)

-- This is the case that froze the editor: a file with no project around it,
-- opened from a directory that is not one either. The root used to fall back
-- to the working directory, and from a shell in the home directory that meant
-- walking and reading all of it.
support.describe("ai/context: no project")

local loose = scratch .. "/ai-context-loose"
vim.fn.delete(loose, "rf")
write(loose .. "/notes.lua", { "local function loose() end" })
write(loose .. "/other.lua", { "local function never_read() end" })

vim.cmd.edit(loose .. "/notes.lua")
vim.cmd.cd(loose)
settle()
context.rebuild()

local none = context.stats()
support.check("there is no root", none.root, nil)
support.check("nothing is being built", none.building, false)
support.check("and nothing is indexed", none.files, 0)

local bare = context.digest()
support.check("the digest carries no index", bare:find("declarations of every file", 1, true), nil)
support.check("nor a file that was never opened", bare:find("never_read", 1, true), nil)
support.check("the neighbours are still sent", bare:find("most recently open", 1, true) ~= nil, true)
support.check("and it is stable", context.digest() == bare, true)

-- A session that starts outside a project picks one up when it gets there.
vim.cmd.cd(home)
vim.cmd.buffer("lua/core/icons.lua")
context.digest()
settle()
support.check("a project is picked up again", context.stats().root, vim.fs.normalize(home))
support.check("with its index", context.stats().files > 50, true)

vim.fn.delete(project, "rf")
vim.fn.delete(loose, "rf")
