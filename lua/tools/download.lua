-- Download and extract a release archive with curl + tar. Both ship with
-- macOS, Linux and Windows 10+; the macOS and Windows tar also open .zip files.
local tools = require("tools")

local M = {}

local in_flight = {}

--- @param name string label for notifications and in-flight deduplication
--- @param url string
--- @param destination string directory to extract into
--- @param strip_components integer leading path components to drop
--- @param on_done fun(ok: boolean)
--- @param members string[]|nil only extract these archive members (paths inside the archive)
function M.archive(name, url, destination, strip_components, on_done, members)
	if in_flight[name] then
		table.insert(in_flight[name], on_done)
		return
	end
	in_flight[name] = { on_done }

	local function finish(ok)
		local callbacks = in_flight[name]
		in_flight[name] = nil
		for _, callback in ipairs(callbacks) do
			callback(ok)
		end
	end

	local temp_dir = tools.tools_dir .. "/.download-" .. name
	vim.fn.delete(temp_dir, "rf")
	vim.fn.mkdir(temp_dir, "p")
	local archive = temp_dir .. "/" .. url:match("[^/]+$")

	tools.notify("downloading " .. name .. "...")
	vim.system(
		{ "curl", "-fsSL", "-o", archive, url },
		{},
		vim.schedule_wrap(function(download)
			if download.code ~= 0 then
				tools.notify(
					"failed to download " .. name .. ": " .. (download.stderr or ""),
					vim.log.levels.ERROR
				)
				return finish(false)
			end

			local tar = { "tar", "-xf", archive, "-C", destination }
			if strip_components > 0 then
				table.insert(tar, "--strip-components=" .. strip_components)
			end
			vim.fn.mkdir(destination, "p")

			vim.system(
				tar,
				{},
				vim.schedule_wrap(function(extract)
					vim.fn.delete(temp_dir, "rf")
					vim.fn.delete(destination .. "/__MACOSX", "rf")
					if extract.code ~= 0 then
						tools.notify(
							"failed to extract " .. name .. ": " .. (extract.stderr or ""),
							vim.log.levels.ERROR
						)
						return finish(false)
					end
					tools.notify(name .. " ready")
					finish(true)
				end)
			)
		end)
	)
end

return M
