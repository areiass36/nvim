-- API keys for the AI plugins, read from kvstore instead of the environment.
--
-- An environment variable has to exist before Neovim starts, so the secret
-- lives in a shell profile in plaintext and is inherited by every child process
-- this editor spawns -- the language servers, the JDBC processes, the curl that
-- carries a completion request. kvstore keeps one encrypted file whose master
-- key is held by DPAPI on this machine, and hands the value only to the Lua
-- caller that asks for it.
--
-- Store one with:
--   :KVStore --global anthropic-api-key
--
-- Then remove ANTHROPIC_API_KEY from the shell profile -- while it is still set
-- the plaintext is still there, and the fallback below will keep using it.
--
-- Residual exposure, unchanged by this: minuet passes the key to curl as a
-- -H argument, so it is visible in that process's command line to anything
-- running as this user for as long as the request lasts.

local M = {}

-- Memoised per session on purpose. The vault is decrypted in pure Lua and a
-- completion request fires on every typing pause, so reading through to it on
-- each request would cost real time for no gain.
local cache = {}
local warned = {}

---Builds the function minuet calls to resolve a key. Returning a function
---rather than a value is what keeps the secret out of the plugin spec: it is
---fetched at request time, not at configuration time.
---@param name string the kvstore key name
---@param env string the environment variable to fall back to
---@return fun(): string|nil
function M.reader(name, env)
	return function()
		if cache[name] then
			return cache[name]
		end

		local ok, kvstore = pcall(require, "kvstore")
		if ok then
			local value = kvstore.get(name, { global = true })
			if type(value) == "string" and value ~= "" then
				cache[name] = value
				return value
			end
		end

		local fallback = vim.env[env]
		if type(fallback) == "string" and fallback ~= "" then
			if not warned[name] then
				warned[name] = true
				vim.schedule(function()
					vim.notify(
						("ai.keys: %q is not in kvstore, falling back to $%s.\nStore it with :KVStore --global %s")
							:format(name, env, name),
						vim.log.levels.WARN
					)
				end)
			end
			cache[name] = fallback
			return fallback
		end

		return nil
	end
end

function M.setup()
	vim.api.nvim_create_user_command("AiKeyReload", function()
		cache = {}
		warned = {}
		vim.notify("ai.keys: keys will be read again on the next request")
	end, { desc = "Forget the memoised API keys, so a newly stored one is picked up" })
end

return M
