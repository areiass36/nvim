-- Shared scaffolding for the debugger tests. Same shape as tests/runner/support.lua
-- and tests/db/support.lua on purpose: one way of writing a check in this config.
local M = {}

M.failures = 0
M.checks = 0
local current = "?"

function M.describe(name)
	current = name
	io.write(("\n== %s\n"):format(name))
end

function M.check(name, got, want)
	M.checks = M.checks + 1
	local ok = vim.deep_equal(got, want)
	if not ok then
		M.failures = M.failures + 1
		io.write(
			("FAIL %s / %s\n  got:  %s\n  want: %s\n"):format(
				current,
				name,
				vim.inspect(got),
				vim.inspect(want)
			)
		)
	else
		io.write(("ok   %s\n"):format(name))
	end
	return ok
end

function M.fail(name, detail)
	M.checks = M.checks + 1
	M.failures = M.failures + 1
	io.write(("FAIL %s / %s\n  %s\n"):format(current, name, detail))
end

function M.note(text)
	io.write(("     %s\n"):format(text))
end

return M
