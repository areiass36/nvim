-- macOS Keychain, through /usr/bin/security.
--
-- Writing goes through `security -i`, which reads whole commands from stdin, so
-- the secret never appears in argv where ps would show it. Passing it as "-w
-- <secret>" would leak it, and passing a bare -w to be prompted only works on a
-- terminal -- from a background process it stores an empty string, which is
-- worse than failing.
local SERVICE = "nvim-db"

local M = {}

function M.available()
	return vim.fn.executable("security") == 1
end

function M.get(account, callback)
	vim.system(
		{ "security", "find-generic-password", "-s", SERVICE, "-a", account, "-w" },
		{ text = true },
		vim.schedule_wrap(function(result)
			if result.code == 0 then
				-- The secret is printed with a trailing newline.
				return callback((result.stdout or ""):gsub("\n$", ""), nil)
			end
			-- 44 is errSecItemNotFound: nothing stored yet, which is not a failure.
			if result.code == 44 then
				return callback(nil, nil)
			end
			callback(nil, (result.stderr or "keychain lookup failed"):gsub("\n$", ""))
		end)
	)
end

--- security -i parses its input like a shell line, so the secret is wrapped in
--- double quotes with backslashes and quotes escaped.
local function quote(value)
	return '"' .. value:gsub("\\", "\\\\"):gsub('"', '\\"') .. '"'
end

function M.set(account, secret, callback)
	local command = ("add-generic-password -U -s %s -a %s -l %s -w %s\n"):format(
		quote(SERVICE),
		quote(account),
		quote(SERVICE .. ": " .. account),
		quote(secret)
	)
	vim.system(
		{ "security", "-i" },
		{ stdin = command, text = true },
		vim.schedule_wrap(function(result)
			if result.code == 0 then
				return callback(true, nil)
			end
			callback(false, (result.stderr or "could not write to the keychain"):gsub("\n$", ""))
		end)
	)
end

function M.delete(account, callback)
	vim.system(
		{ "security", "delete-generic-password", "-s", SERVICE, "-a", account },
		{ text = true },
		vim.schedule_wrap(function(result)
			callback(result.code == 0 or result.code == 44, nil)
		end)
	)
end

return M
