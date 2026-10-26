-- Where a password comes from, and nowhere it goes.
--
-- Four sources: the OS keyring, an environment variable, the output of a command
-- (op / pass / vault), or a prompt whose answer is kept in memory for the
-- session only. Nothing is ever written to a plain file by this module.
local db = require("db")
local platform = require("core.platform")

local M = {}

-- Answers to prompts, for this session only. Cleared on exit and by :DbForget.
local session = {}
-- One prompt at a time: two concurrent vim.fn.inputsecret calls would fight
-- over the command line and the second would be swallowed.
local prompt_queue = {}
local prompting = false

local function keyring()
	local os_name = platform.detect()
	if os_name == "mac" then
		return require("db.keyring.macos")
	elseif os_name == "windows" then
		return require("db.keyring.windows")
	end
	return require("db.keyring.linux")
end

M.keyring = keyring

local function run_next_prompt()
	if prompting or #prompt_queue == 0 then
		return
	end
	prompting = true
	local job = table.remove(prompt_queue, 1)
	vim.schedule(function()
		local ok, answer = pcall(vim.fn.inputsecret, ("Password for %s: "):format(job.label))
		-- inputsecret leaves the cursor on the message line.
		vim.cmd("redraw")
		prompting = false
		if ok and answer and answer ~= "" then
			session[job.id] = answer
			job.callback(answer, nil)
		else
			job.callback(nil, "no password entered")
		end
		run_next_prompt()
	end)
end

local function ask(connection, callback)
	prompt_queue[#prompt_queue + 1] = {
		id = connection.id,
		label = connection.name,
		callback = callback,
	}
	run_next_prompt()
end

--- @param connection table
--- @param callback fun(password: string|nil, err: string|nil)
function M.resolve(connection, callback)
	local source = connection.password_source or { kind = "none" }

	if source.kind == "none" then
		return callback(nil, nil)
	end

	if session[connection.id] then
		return callback(session[connection.id], nil)
	end

	if source.kind == "env" then
		local value = vim.env[source.var]
		if value and value ~= "" then
			return callback(value, nil)
		end
		return callback(nil, ("$%s is not set"):format(source.var))
	end

	if source.kind == "command" then
		return vim.system(
			source.argv,
			{ text = true },
			vim.schedule_wrap(function(result)
				if result.code ~= 0 then
					return callback(
						nil,
						("%s failed: %s"):format(source.argv[1], (result.stderr or ""):gsub("\n$", ""))
					)
				end
				local secret = (result.stdout or ""):gsub("\n$", "")
				if secret == "" then
					return callback(nil, ("%s returned nothing"):format(source.argv[1]))
				end
				-- Worth caching: these commands can need a touch or a device prompt.
				session[connection.id] = secret
				callback(secret, nil)
			end)
		)
	end

	if source.kind == "prompt" then
		return ask(connection, callback)
	end

	if source.kind == "keyring" then
		local store = keyring()
		if not store.available() then
			db.notify("no OS keyring available; asking for the password instead", vim.log.levels.WARN)
			return ask(connection, callback)
		end
		return store.get(source.account or connection.id, function(secret, err)
			if err then
				return callback(nil, err)
			end
			if secret and secret ~= "" then
				return callback(secret, nil)
			end
			-- Nothing stored yet: ask, and offer to remember it.
			ask(connection, function(answer, ask_err)
				if not answer then
					return callback(nil, ask_err)
				end
				callback(answer, nil)
				vim.schedule(function()
					local keep = vim.fn.confirm(
						("Store the password for %s in the keyring?"):format(connection.name),
						"&Yes\n&No",
						2
					)
					if keep == 1 then
						M.store(connection, answer, function() end)
					end
				end)
			end)
		end)
	end

	callback(nil, ("unknown password source %q"):format(tostring(source.kind)))
end

--- @param secret string|nil nil asks for it
function M.store(connection, secret, callback)
	local store = keyring()
	if not store.available() then
		return callback(false, "no OS keyring available on this machine")
	end
	local account = (connection.password_source or {}).account or connection.id

	local function write(value)
		store.set(account, value, function(ok, err)
			if ok then
				session[connection.id] = value
				db.notify(("password for %s stored in the keyring"):format(connection.name))
			end
			callback(ok, err)
		end)
	end

	if secret then
		return write(secret)
	end
	ask(connection, function(answer, err)
		if not answer then
			return callback(false, err)
		end
		write(answer)
	end)
end

function M.delete(connection, callback)
	session[connection.id] = nil
	keyring().delete((connection.password_source or {}).account or connection.id, callback)
end

function M.forget(id)
	if id then
		session[id] = nil
	else
		session = {}
	end
end

return M
