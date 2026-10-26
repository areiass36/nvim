-- Measuring and drawing cells.
local support = require("tests.db.support")
local check = support.check
local db = require("db")
local layout = require("db.grid.layout")

support.describe("grid/layout: making a value printable")
check("newline", layout.sanitize("li\nnha"), "li↵nha")
check("terminal escapes removed", layout.sanitize("\27[31mred\27[0m"), "red")
check("control bytes", layout.sanitize("a\1b"), "a·b")
check("tab", layout.sanitize("a\tb"), "a b")
check("null", layout.sanitize(db.NULL, "NULL"), "NULL")
check("number", layout.sanitize(42), "42")
check("boolean", layout.sanitize(true), "true")
check("a big integer is not rendered in exponent form", layout.sanitize(1234567890123), "1234567890123")

support.describe("grid/layout: truncating by display width")
check("ascii", layout.truncate("abcdefghij", 5), "abcd…")
check("exact fit", layout.truncate("abcde", 5), "abcde")
check("cjk", layout.truncate("日本語テキスト", 7), "日本語…")
check("cjk width", vim.fn.strdisplaywidth(layout.truncate("日本語テキスト", 7)), 7)
check(
	"emoji stays within the width",
	vim.fn.strdisplaywidth(layout.truncate("🚀🔥🚀🔥", 5)) <= 5,
	true
)
local huge = string.rep("x", 200000)
local started = vim.uv.hrtime()
layout.truncate(huge, 40)
check("a huge cell truncates quickly", (vim.uv.hrtime() - started) / 1e6 < 50, true)

support.describe("grid/layout: widths and rendering")
local columns = { "id", "cjk", "txt" }
local rows = { { 1, "日本語", "a" }, { 2, "ab", db.NULL } }
local computed = layout.compute(columns, rows, {})
check("a cjk column counts double", computed.widths[2], 6)
local lines, spans = layout.render(computed, columns, rows, {})
local widths = vim.tbl_map(vim.fn.strdisplaywidth, lines)
check("every line is the same width on screen", #vim.fn.uniq(vim.deepcopy(widths)), 1)
check("the header is there", lines[1]:find("cjk") ~= nil, true)
check("NULL is shown", lines[4]:find("NULL") ~= nil, true)
check("the span lands on a cjk cell", vim.trim(lines[3]:sub(spans[3][2][1] + 1, spans[3][2][2])), "日本語")
check("and on an ascii cell", vim.trim(lines[4]:sub(spans[4][2][1] + 1, spans[4][2][2])), "ab")
check("and on the header", vim.trim(lines[1]:sub(spans[1][2][1] + 1, spans[1][2][2])), "cjk")

local capped = layout.compute({ "x" }, { { string.rep("y", 500) } }, { max_width = 20 })
check("width is capped", capped.widths[1], 20)
check("and marked as truncated", capped.truncated[1], true)

support.describe("grid/layout: bytes that are not text")
check("a replacement character", layout.looks_binary("\1\2\239\191\189"), true)
check("plain text is not binary", layout.looks_binary("日本語"), false)
check("a number is not binary", layout.looks_binary(42), false)
