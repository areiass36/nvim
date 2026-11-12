-- Shared scaffolding for the runner tests. Same shape as tests/db/support.lua
-- on purpose: this copy travels with the module when it becomes a plugin.
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

function M.wait(fn, timeout)
	return vim.wait(timeout or 60000, fn, 50)
end

--- Run a callback-based function to completion.
--- @return any... whatever the callback was given
function M.sync(starter, timeout)
	local done, captured = false, nil
	starter(function(...)
		captured = { ... }
		done = true
	end)
	if not M.wait(function()
		return done
	end, timeout) then
		return nil, "timed out"
	end
	return unpack(captured or {})
end

-- -------------------------------------------------------- runner helpers
M.root = vim.fs.normalize(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h"))

function M.fixture_path(name)
	return ("%s/fixtures/%s.json"):format(M.root, name)
end

--- Decoded fixture, through the real reader (comments, luanil and all).
function M.fixture(name)
	local doc, err = require("runner.load").read(M.fixture_path(name))
	if not doc then
		error(("fixture %s: %s"):format(name, err))
	end
	return doc
end

--- A minimal valid document, as a Lua table the cases can bend one field at a time.
function M.doc(overrides)
	local base = {
		version = 1,
		workspace = "demo",
		project = {
			{
				name = "api",
				path = "apps/api",
				runner = { { label = "main", command = { "npm", "run", "dev" } } },
			},
		},
	}
	return vim.tbl_deep_extend("force", base, overrides or {})
end

--- Every error path a document produces, sorted so the comparison is stable.
function M.paths(doc)
	local _, errors = require("runner.schema").validate(doc)
	local paths = {}
	for _, entry in ipairs(errors) do
		paths[#paths + 1] = entry.path
	end
	table.sort(paths)
	return paths
end

--- The message reported at `path`, or nil.
function M.message(doc, path)
	local _, errors = require("runner.schema").validate(doc)
	for _, entry in ipairs(errors) do
		if entry.path == path then
			return entry.message
		end
	end
	return nil
end

return M
