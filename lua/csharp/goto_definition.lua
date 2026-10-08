-- gd for C#. Roslyn resolves symbols from .NET/ASP.NET reference assemblies to
-- a "[from metadata]" stub (signatures only, no bodies). When that happens we
-- open the ILSpy-decompiled implementation instead, positioned on the member.
local metadata = require("csharp.metadata")
local ilspy = require("csharp.ilspy")
local decompiled = require("csharp.decompiled_sources")
local dotnet = require("tools.dotnet")

local M = {}

local DECLARATION_MODIFIERS =
	"(public|private|protected|internal|static|virtual|override|abstract|sealed|unsafe|readonly|async|extern|new|partial)"

local function notify(message, level)
	vim.notify("[C#] " .. message, level or vim.log.levels.INFO)
end

--- Score how well a declaration line matches the metadata signature.
local function score_declaration(line, signature)
	local score = 0
	if (line:find("%f[%w]static%f[%W]") ~= nil) == signature.static then
		score = score + 2
	end
	if signature.generic and line:find(signature.name .. "%s*" .. vim.pesc(signature.generic)) then
		score = score + 3
	end
	if signature.types then
		local types = metadata.parameter_types(metadata.strip_generics(line), signature.name)
		if types and #types == #signature.types then
			score = score + 2
			if vim.deep_equal(types, signature.types) then
				score = score + 4
			end
		end
	end
	if not line:find("%f[%w]override%f[%W]") then
		score = score + 1
	end
	return score
end

--- Move the cursor to the best matching member declaration, or to the type.
--- @param signature csharp.Signature|nil
local function jump_to(signature, type_name)
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	local best_line, best_score

	if signature then
		local pattern = ("\\v^\\s*(%s\\s+)+[^=;(){}]*<%s>\\s*[<({]"):format(
			DECLARATION_MODIFIERS,
			signature.name
		)
		local declaration = vim.regex(pattern)
		for index, line in ipairs(lines) do
			if declaration:match_str(line) then
				local score = score_declaration(line, signature)
				if not best_score or score > best_score then
					best_line, best_score = index, score
				end
			end
		end
		if not best_line then
			local position = vim.fn.searchpos("\\v<" .. signature.name .. ">", "cw")
			best_line = position[1] > 0 and position[1] or nil
		end
	end
	if not best_line and type_name then
		local position =
			vim.fn.searchpos("\\v<(class|struct|interface|enum|record)>\\s+<" .. type_name .. ">", "cw")
		best_line = position[1] > 0 and position[1] or nil
	end
	if best_line then
		vim.api.nvim_win_set_cursor(0, { best_line, 0 })
		vim.cmd("normal! ^zz")
	end
end

--- @param info csharp.MetadataInfo
--- @param signature csharp.Signature|nil
local function open_decompiled(info, signature)
	dotnet.ensure_ilspy(function(ok)
		if not ok then
			return
		end
		ilspy.find_implementation(info, function(dll)
			ilspy.ensure_project(info, dll, function(project_dir)
				local file = ilspy.type_file(project_dir, info)
				if vim.fn.filereadable(file) == 0 then
					return notify("ILSpy did not generate " .. file, vim.log.levels.ERROR)
				end
				decompiled.open_in_roslyn(project_dir)
				vim.cmd("edit " .. vim.fn.fnameescape(file))
				jump_to(signature, info.type_name)
			end)
		end)
	end)
end

local function open_location(item)
	vim.cmd("edit " .. vim.fn.fnameescape(item.filename))
	pcall(vim.api.nvim_win_set_cursor, 0, { item.lnum, math.max(0, (item.col or 1) - 1) })
	vim.cmd("normal! zz")
end

local function on_definitions(list)
	local items = list.items or {}
	if #items == 0 then
		return notify("definition not found")
	end
	if #items > 1 then
		return require("telescope.builtin").lsp_definitions()
	end

	local item = items[1]
	if vim.fs.normalize(item.filename):find("/MetadataAsSource/", 1, true) then
		local ok, lines = pcall(vim.fn.readfile, item.filename)
		local info = ok and metadata.parse(lines, item.filename)
		if info then
			return open_decompiled(info, metadata.signature(lines[item.lnum]))
		end
	end
	open_location(item)
end

function M.run()
	if #vim.lsp.get_clients({ bufnr = 0, name = "roslyn_ls" }) == 0 then
		return notify(
			"Roslyn has not attached to this file yet (wait for the solution to load).",
			vim.log.levels.WARN
		)
	end
	vim.lsp.buf.definition({ on_list = on_definitions })
end

return M
