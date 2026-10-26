-- Blocking waits for nvim-dap configuration callbacks. Those run inside a
-- coroutine, so yielding here keeps nvim responsive while a dev server boots.
local M = {}

local RETRY_MS = 250

--- Wait until a local TCP port accepts connections. Returns false on timeout.
function M.for_port(port, timeout_ms)
	local co = coroutine.running()
	local deadline = vim.uv.now() + timeout_ms
	local function attempt()
		local tcp = vim.uv.new_tcp()
		tcp:connect("127.0.0.1", port, function(err)
			tcp:close()
			if not err then
				return vim.schedule(function()
					coroutine.resume(co, true)
				end)
			end
			if vim.uv.now() > deadline then
				return vim.schedule(function()
					coroutine.resume(co, false)
				end)
			end
			vim.defer_fn(attempt, RETRY_MS)
		end)
	end
	attempt()
	return coroutine.yield()
end

return M
