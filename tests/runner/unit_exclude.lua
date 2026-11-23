-- The `exclude` globs as the pickers use them: which absolute paths the file
-- browser hides, and what rg is told from a given cwd. No filesystem.
local support = require("tests.runner.support")
local exclude = require("runner.exclude")

local check = support.check
local ROOT = "/ws"

local function hides(globs, relative)
	return exclude.matcher(globs, ROOT)(ROOT .. "/" .. relative)
end

support.describe("exclude.matcher")
check("a bare name hides the folder", hides({ "dist" }, "dist"), true)
check("a bare name hides what is inside it", hides({ "dist" }, "dist/a.js"), true)
check("a bare name matches at any depth", hides({ "dist" }, "apps/web/dist/a.js"), true)
check("a bare name is the whole name", hides({ "dist" }, "distro/a.js"), false)
check("a wildcard matches a file anywhere", hides({ "*.min.js" }, "src/c.min.js"), true)
check("a wildcard spares the rest", hides({ "*.min.js" }, "src/c.js"), false)
check("an anchored glob matches from the root", hides({ "apps/legacy" }, "apps/legacy/x.js"), true)
check("an anchored glob does not float", hides({ "apps/legacy" }, "lib/apps/legacy/x.js"), false)
check("a leading slash is the same anchor", hides({ "/apps/legacy" }, "apps/legacy"), true)
check("a trailing slash is ignored", hides({ "dist/" }, "dist"), true)
check("a star stays inside one folder", hides({ "apps/*/dist" }, "apps/web/dist/a.js"), true)
check("a double star crosses folders", hides({ "**/*.snap" }, "a/b/c.snap"), true)
check("a double star matches at the root too", hides({ "**/*.snap" }, "c.snap"), true)
check("the root itself is never hidden", exclude.matcher({ "*" }, ROOT)(ROOT), false)
check("a path outside the root is never hidden", exclude.matcher({ "dist" }, ROOT)("/other/dist"), false)

support.describe("exclude.rg_args")
local globs = { "dist", "**/*.snap", "apps/legacy", "lib/old/**" }
check("from the root every glob goes through", exclude.rg_args(globs, ROOT, ROOT), {
	"--glob=!dist",
	"--glob=!**/*.snap",
	"--glob=!/apps/legacy",
	"--glob=!/lib/old/**",
})
check("from below, an anchored glob is rewritten or dropped", exclude.rg_args(globs, ROOT, ROOT .. "/lib"), {
	"--glob=!dist",
	"--glob=!**/*.snap",
	"--glob=!/old/**",
})
check("from outside, only the floating globs remain", exclude.rg_args(globs, ROOT, "/elsewhere"), {
	"--glob=!dist",
	"--glob=!**/*.snap",
})
