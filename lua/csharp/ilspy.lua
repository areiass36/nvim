-- Decompile whole implementation assemblies with ILSpy into a project
-- (.csproj + one .cs per type), cached per runtime version.
local tools = require("tools")
local dotnet = require("tools.dotnet")

local M = {}

M.source_root = tools.tools_dir .. "/ilspy-src"

local generating = {}

--- @param info csharp.MetadataInfo
--- @param dll string implementation assembly path
function M.project_dir(info, dll)
	return ("%s/%s/%s/%s"):format(M.source_root, info.pack, info.version, vim.fn.fnamemodify(dll, ":t:r"))
end

--- ILSpy writes one folder per namespace, using the dotted name (System.Collections.Generic/).
--- @param info csharp.MetadataInfo
function M.type_file(project_dir, info)
	local folder = info.namespace ~= "" and (info.namespace .. "/") or ""
	return project_dir .. "/" .. folder .. info.type_name .. ".cs"
end

local function notify(message, level)
	vim.notify("[C#] " .. message, level or vim.log.levels.INFO)
end

--- Generate the project for `dll` if needed, then call `on_done(project_dir)`.
--- @param info csharp.MetadataInfo
function M.ensure_project(info, dll, on_done)
	local dir = M.project_dir(info, dll)
	if vim.fn.filereadable(dir .. "/.ilspy-done") == 1 then
		return on_done(dir)
	end
	if generating[dir] then
		table.insert(generating[dir], on_done)
		return
	end
	generating[dir] = { on_done }

	vim.fn.delete(dir, "rf")
	vim.fn.mkdir(dir, "p")
	local name = vim.fn.fnamemodify(dll, ":t")
	notify(("decompiling all of %s with ILSpy (once per runtime version, may take a minute)..."):format(name))
	local started = vim.uv.now()

	vim.system(
		{ dotnet.ilspy, "-p", "-o", dir, dll },
		{ text = true },
		vim.schedule_wrap(function(result)
			local callbacks = generating[dir]
			generating[dir] = nil
			if result.code ~= 0 or vim.fn.glob(dir .. "/*.csproj") == "" then
				notify(
					("ILSpy failed on %s: %s"):format(name, (result.stderr or ""):sub(1, 200)),
					vim.log.levels.ERROR
				)
				return
			end
			vim.fn.writefile({ dll }, dir .. "/.ilspy-done")
			notify(("%s decompiled in %ds"):format(name, math.floor((vim.uv.now() - started) / 1000)))
			for _, callback in ipairs(callbacks) do
				callback(dir)
			end
		end)
	)
end

--- Find which runtime assembly actually defines the type. Reference assemblies
--- such as System.Runtime are facades that forward to System.Private.CoreLib.
--- @param info csharp.MetadataInfo
--- @param on_found fun(dll: string)
function M.find_implementation(info, on_found)
	local candidates =
		{ info.shared_dir .. "/System.Private.CoreLib.dll", info.shared_dir .. "/" .. info.dll }
	for _, file in ipairs(vim.fn.glob(info.shared_dir .. "/*.dll", true, true)) do
		if file ~= candidates[1] and file ~= candidates[2] then
			candidates[#candidates + 1] = file
		end
	end

	-- Already generated projects answer instantly: the type file either exists or not.
	for _, dll in ipairs(candidates) do
		if vim.fn.filereadable(M.type_file(M.project_dir(info, dll), info)) == 1 then
			return on_found(dll)
		end
	end

	local function try(index)
		local dll = candidates[index]
		if not dll then
			return notify(
				("could not find the implementation of %s in %s"):format(info.full_type, info.shared_dir),
				vim.log.levels.ERROR
			)
		end
		vim.system(
			{ dotnet.ilspy, "-t", info.full_type, dll },
			{ text = true },
			vim.schedule_wrap(function(result)
				local output = result.stdout or ""
				if result.code == 0 and #output > 200 and output:find(info.type_name, 1, true) then
					return on_found(dll)
				end
				try(index + 1)
			end)
		)
	end
	try(1)
end

return M
