-- The display form of a reference, both ways.
local support = require("tests.runner.support")
local address = require("runner.address")

local check = support.check

local function parsed(text)
	local ref, err = address.parse(text)
	return ref or err
end

support.describe("formatting")
check("a runner reads as project:label", address.format({ project = "api", runner = "main" }), "api:main")
check("the owning project fills a bare runner", address.format({ runner = "main" }, "api"), "api:main")
check("a cluster carries a hash", address.format({ cluster = "local" }), "#local")
check(
	"a foreign runner carries the workspace",
	address.format({ workspace = "e2e", project = "playwright", runner = "audit" }),
	"e2e/playwright:audit"
)
check("a foreign cluster too", address.format({ workspace = "e2e", cluster = "audit" }), "e2e/#audit")

support.describe("parsing")
check("project:label", parsed("api:main"), { project = "api", runner = "main" })
check("#cluster", parsed("#local"), { cluster = "local" })
check("ws/project:label", parsed("e2e/playwright:audit"), {
	workspace = "e2e",
	project = "playwright",
	runner = "audit",
})
check("ws/#cluster", parsed("e2e/#audit"), { workspace = "e2e", cluster = "audit" })
check("dots and dashes are names", parsed("api:web.http-2"), { project = "api", runner = "web.http-2" })

support.describe("parsing what is not an address")
check(
	"a bare label is ambiguous",
	parsed("main"),
	'"main" is not an address: use project:label, #cluster, or ws/ before either'
)
check("an empty string", parsed(""), "expected an address like api:main or #local")
check("a nil", parsed(nil), "expected an address like api:main or #local")
check(
	"a trailing colon",
	parsed("api:"),
	'"api:" is not an address: use project:label, #cluster, or ws/ before either'
)

support.describe("round trip")
for _, text in ipairs({ "api:main", "#local", "e2e/playwright:audit", "e2e/#audit" }) do
	check(text, address.format(address.parse(text)), text)
end
