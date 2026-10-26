-- How a value is written out.
--
-- Converting types is the Java side's job now - it has the column type from
-- JDBC, so a decimal arrives as exact text and a binary column as hex. What
-- is left here is turning whatever arrived into the string a cell, a CSV
-- field or the clipboard should hold.
local db = require("db")

local M = {}

function M.display(value, null_text)
	if value == db.NULL or value == nil or value == vim.NIL then
		return null_text or "NULL"
	end
	if type(value) == "boolean" then
		return value and "true" or "false"
	end
	if type(value) == "number" then
		-- An integer prints as an integer: 1, not 1.0.
		if value == math.floor(value) and math.abs(value) < 2 ^ 53 then
			return ("%d"):format(value)
		end
		return ("%.14g"):format(value)
	end
	if type(value) == "string" then
		return value
	end
	local ok, encoded = pcall(vim.json.encode, value)
	return ok and encoded or tostring(value)
end

return M
