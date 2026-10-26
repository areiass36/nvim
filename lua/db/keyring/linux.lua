-- Linux: libsecret through secret-tool, falling back to pass.
local SERVICE = "nvim-db"

local M = {}

local function backend()
	if vim.fn.executable("secret-tool") == 1 then
		return "secret-tool"
	end
	if vim.fn.executable("pass") == 1 then
		return "pass"
	end
	return nil
end

function M.available()
	return backend() ~= nil
end

function M.get(account, callback)
	local which = backend()
	if not which then
		return callback(nil, nil)
	end
	local command = which == "secret-tool"
			and { "secret-tool", "lookup", "service", SERVICE, "account", account }
		or { "pass", "show", SERVICE .. "/" .. account }
	vim.system(
		command,
		{ text = true },
		vim.schedule_wrap(function(result)
			if result.code ~= 0 then
				-- Both tools exit non-zero for "no such secret"; treat it as absent.
				return callback(nil, nil)
			end
			callback((result.stdout or ""):gsub("\n$", ""), nil)
		end)
	)
end

function M.set(account, secret, callback)
	local which = backend()
	if not which then
		return callback(false, "no secret-tool or pass on PATH")
	end
	local command = which == "secret-tool"
			and {
				"secret-tool",
				"store",
				"--label=" .. SERVICE .. ": " .. account,
				"service",
				SERVICE,
				"account",
				account,
			}
		or { "pass", "insert", "--multiline", "--force", SERVICE .. "/" .. account }
	vim.system(
		command,
		{ stdin = secret .. "\n", text = true },
		vim.schedule_wrap(function(result)
			callback(result.code == 0, result.code ~= 0 and (result.stderr or "store failed") or nil)
		end)
	)
end

function M.delete(account, callback)
	local which = backend()
	if not which then
		return callback(false, nil)
	end
	local command = which == "secret-tool"
			and { "secret-tool", "clear", "service", SERVICE, "account", account }
		or { "pass", "rm", "--force", SERVICE .. "/" .. account }
	vim.system(
		command,
		{ text = true },
		vim.schedule_wrap(function(result)
			callback(result.code == 0, nil)
		end)
	)
end

return M
