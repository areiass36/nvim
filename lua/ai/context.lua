-- The project context sent ahead of the cursor on every AI completion.
--
-- This reproduces what GitHub Copilot actually does for inline completion.
-- Copilot keeps no index of your repository: it assembles a prompt per request
-- from the files you have open -- what GitHub calls neighboring tabs -- plus
-- whatever it can match against the code around the cursor. The two halves
-- here are that same idea:
--
--   index       one line per top-level declaration across every tracked file,
--               so the model knows the module layout and the naming
--               conventions of this repository
--   neighbours  the head of the buffers you last visited, which is where the
--               patterns it should be imitating actually live
--
-- Both halves are deliberately independent of the current buffer's contents
-- and of the cursor, so the digest does not change while you type. That is the
-- whole point: the request marks it as a cacheable prefix (see the transform in
-- plugins/lsp/minuet.lua), a prefix is only reusable while its bytes stay
-- identical, and a cached prefix reads back at about a tenth of the input price
-- with every read renewing the entry. Typing pauses are seconds apart, so the
-- entry never expires while you are in a file.

local M = {}

-- Character budgets. These ride on every request, but inside the cached prefix,
-- so the ceiling is about prefill latency on a cold request rather than about
-- the per-request bill. A field rather than a constant so it can be measured
-- and tuned without editing this file.
M.index_budget = 60000
local NEIGHBOUR_BUDGET = 2000
local NEIGHBOUR_COUNT = 5

-- Lines read per file while indexing. A declaration below line 400 of a file is
-- not what a layout summary is for.
local SCAN_LINES = 400
-- Declaration lines kept per file, so one large module cannot eat the budget.
local MAX_DECLARATIONS = 30
-- Files per event-loop tick while indexing, so a cold scan never blocks input.
local SCAN_CHUNK = 25
-- Files larger than this are skipped: a generated or vendored blob tells the
-- model nothing about how this project is written.
local MAX_FILE_BYTES = 200 * 1024

-- A line is kept when it looks like a top-level declaration. Matching whole
-- lines instead of parsing out names is deliberate -- the signature is more
-- useful to the model than a bare identifier, and it needs no parser per
-- language.
local LUA = {
	"^function%s",
	"^local%s+function%s",
	"^local%s+[%w_]+%s*=%s*function",
	"^[%w_]+[%.:][%w_]+%s*=%s*function",
	"^---@class%s",
	"^---@alias%s",
}
local CURLY = {
	"^%s*export%s",
	"^%s*function%s",
	"^%s*class%s",
	"^%s*interface%s",
	"^%s*type%s+[%w_]+%s*=",
	"^%s*const%s+[%w_]+%s*=%s*%(",
	"^%s*async%s+function%s",
}
local JVM = {
	"^%s*public%s",
	"^%s*protected%s",
	"^%s*class%s",
	"^%s*interface%s",
	"^%s*record%s",
	"^%s*enum%s",
}
local PYTHON = { "^def%s", "^class%s", "^async%s+def%s", "^%s%s%s%sdef%s" }
local GO = { "^func%s", "^type%s" }
local RUST = { "^pub%s", "^fn%s", "^struct%s", "^enum%s", "^impl%s", "^trait%s" }
local SQL = { "^%s*create%s", "^%s*CREATE%s" }
local FALLBACK = { "^%S.*[%(%{]" }

local BY_EXTENSION = {
	lua = LUA,
	java = JVM,
	kt = JVM,
	cs = JVM,
	ts = CURLY,
	tsx = CURLY,
	js = CURLY,
	jsx = CURLY,
	mjs = CURLY,
	py = PYTHON,
	go = GO,
	rs = RUST,
	sql = SQL,
	ps1 = { "^function%s", "^%s*param%s*%(" },
	sh = { "^%s*[%w_]+%s*%(%)%s*{", "^function%s" },
}

-- Directories never worth indexing, whichever discovery path found them.
local SKIP_DIRECTORIES = {
	[".git"] = true,
	["node_modules"] = true,
	[".tests"] = true,
	["target"] = true,
	["build"] = true,
	["dist"] = true,
	["__pycache__"] = true,
}

local state = {
	root = nil,
	-- The rendered index, or nil until the first scan finishes.
	index = nil,
	indexed_files = nil,
	building = false,
	-- Bumped whenever the index is replaced, so the digest memo knows to drop.
	generation = 0,
	memo_key = nil,
	memo_value = nil,
	refresh_timer = nil,
}

local function project_root()
	return vim.fs.root(0, { ".git", "lazy-lock.json" }) or vim.uv.cwd()
end

local function relative(root, path)
	local normal_root = vim.fs.normalize(root)
	local normal_path = vim.fs.normalize(path)
	if normal_path:sub(1, #normal_root + 1) == normal_root .. "/" then
		return normal_path:sub(#normal_root + 2)
	end
	return normal_path
end

local function patterns_for(path)
	local extension = path:match("%.([%w_]+)$")
	return extension and BY_EXTENSION[extension:lower()] or nil
end

-- One file's contribution to the index: its path, then the declaration lines.
local function declarations(root, path)
	local stat = vim.uv.fs_stat(path)
	if not stat or stat.type ~= "file" or stat.size > MAX_FILE_BYTES then
		return nil
	end

	local patterns = patterns_for(path)
	if not patterns then
		return nil
	end

	local ok, lines = pcall(vim.fn.readfile, path, "", SCAN_LINES)
	if not ok or type(lines) ~= "table" then
		return nil
	end

	local kept = {}
	for _, line in ipairs(lines) do
		if #kept >= MAX_DECLARATIONS then
			break
		end
		-- A line long enough to be a whole implementation is not a signature.
		if #line <= 200 then
			for _, pattern in ipairs(patterns) do
				if line:match(pattern) then
					kept[#kept + 1] = (line:gsub("%s+$", ""))
					break
				end
			end
		end
	end

	-- A file can legitimately declare nothing and still describe the project:
	-- every plugin spec under lua/plugins is a table literal, and its first few
	-- lines are what identify it. Falling back to the head of the file keeps
	-- those in the index instead of dropping a third of the repository.
	if #kept == 0 then
		for _, line in ipairs(lines) do
			if #kept >= 8 then
				break
			end
			local trimmed = line:gsub("%s+$", "")
			if trimmed ~= "" and not trimmed:match("^%s*%-%-") and not trimmed:match("^%s*#") then
				kept[#kept + 1] = trimmed
			end
		end
	end

	if #kept == 0 then
		return nil
	end

	return "-- " .. relative(root, path) .. "\n" .. table.concat(kept, "\n")
end

-- The fallback for a project that is not a git repository, or a machine with no
-- git on PATH. Bounded by depth and by the skip list, since without git there
-- is nothing that knows what is generated or vendored here.
local function walk(root)
	local found = {}
	for name, kind in vim.fs.dir(root, {
		depth = 8,
		skip = function(directory)
			return not SKIP_DIRECTORIES[directory]
		end,
	}) do
		if kind == "file" and patterns_for(name) then
			found[#found + 1] = root .. "/" .. name
		end
	end
	return found
end

-- Discovery through git, which already knows what is tracked and what is
-- ignored, so a build directory or a vendored dependency never reaches the
-- index. Falls back to the walk above when there is no repository.
local function file_list(root, callback)
	-- pcall because vim.system raises rather than calling back when the
	-- executable is missing, which is one of the two cases the walk is for.
	local spawned = pcall(
		vim.system,
		{ "git", "-C", root, "ls-files", "--cached", "--others", "--exclude-standard" },
		{ text = true },
		function(result)
			local paths = {}
			if result.code == 0 then
				for line in (result.stdout or ""):gmatch("[^\r\n]+") do
					local segment = line:match("^([^/]+)/")
					if not (segment and SKIP_DIRECTORIES[segment]) then
						paths[#paths + 1] = root .. "/" .. line
					end
				end
			end
			vim.schedule(function()
				if #paths == 0 then
					paths = walk(root)
				end
				callback(paths)
			end)
		end
	)

	if not spawned then
		vim.schedule(function()
			callback(walk(root))
		end)
	end
end

-- Ranks a file by how likely it is to matter to what you are editing: the same
-- directory first, then the same top-level module, then everything else. This
-- only decides what survives the budget. It is not the order things are
-- rendered in, because ordering by anything that follows the cursor would
-- rewrite the prefix every time you changed file.
local function proximity(path, reference)
	if reference == "" then
		return 3
	end
	local directory = vim.fs.dirname(path)
	if directory == reference then
		return 1
	end
	local module = reference:match("^([^/]+/[^/]+)") or reference:match("^([^/]+)")
	if module and path:sub(1, #module + 1) == module .. "/" then
		return 2
	end
	return 3
end

-- Extracts every file's declarations across several event-loop ticks, so a cold
-- scan never blocks input, then keeps what fits.
--
-- Selection and rendering are deliberately separate steps. Which files are kept
-- depends on the current buffer; the order they are rendered in does not -- it
-- is always by path, so the bytes depend on the *set* of files and not on how
-- git listed them or where your cursor happens to be. An unstable order would
-- rewrite the cached prefix on every request and the cache would never hit.
local function render_index(root, paths, callback)
	local reference = ""
	local current = vim.api.nvim_buf_get_name(0)
	if current ~= "" then
		reference = vim.fs.dirname(relative(root, current))
	end

	local pieces = {}
	local cursor = 1

	local function finish()
		local total = 0
		for _, piece in ipairs(pieces) do
			total = total + #piece.text + 2
		end

		-- Under budget, nothing is dropped and proximity is irrelevant. This is
		-- the common case and the one that keeps the prefix stable all session.
		if total > M.index_budget then
			table.sort(pieces, function(a, b)
				if a.rank ~= b.rank then
					return a.rank < b.rank
				end
				return a.path < b.path
			end)
			local kept = {}
			local used = 0
			for _, piece in ipairs(pieces) do
				if used + #piece.text + 2 > M.index_budget then
					break
				end
				kept[#kept + 1] = piece
				used = used + #piece.text + 2
			end
			pieces = kept
		end

		table.sort(pieces, function(a, b)
			return a.path < b.path
		end)

		local rendered = {}
		for _, piece in ipairs(pieces) do
			rendered[#rendered + 1] = piece.text
		end
		callback(table.concat(rendered, "\n\n"), #pieces)
	end

	local function step()
		local stop = math.min(cursor + SCAN_CHUNK - 1, #paths)
		for index = cursor, stop do
			local path = paths[index]
			local text = declarations(root, path)
			if text then
				local short = relative(root, path)
				pieces[#pieces + 1] = {
					path = short,
					text = text,
					rank = proximity(short, reference),
				}
			end
		end

		cursor = stop + 1
		if cursor <= #paths then
			vim.schedule(step)
		else
			finish()
		end
	end

	step()
end

function M.rebuild()
	if state.building then
		return
	end
	state.building = true
	state.root = project_root()

	local root = state.root
	file_list(root, function(paths)
		render_index(root, paths, function(rendered, count)
			state.index = rendered
			state.indexed_files = count
			state.generation = state.generation + 1
			state.memo_key = nil
			state.memo_value = nil
			state.building = false
		end)
	end)
end

--- What the index currently holds, for :AiContext and for the tests.
---@return { files: integer, chars: integer, building: boolean, root: string|nil }
function M.stats()
	return {
		files = state.indexed_files or 0,
		chars = state.index and #state.index or 0,
		building = state.building,
		root = state.root,
	}
end

-- The buffers you last visited, excluding the one you are typing in. Selected
-- by recency, then rendered in path order for the same byte-stability reason as
-- the index: moving between two files must not rewrite the prefix unless the
-- set of files itself changed.
local function neighbours()
	local current = vim.api.nvim_get_current_buf()
	local root = state.root or project_root()
	local candidates = {}

	for _, info in ipairs(vim.fn.getbufinfo({ buflisted = 1 })) do
		local bufnr = info.bufnr
		if bufnr ~= current and info.loaded == 1 and info.name ~= "" then
			local buftype = vim.api.nvim_get_option_value("buftype", { buf = bufnr })
			if buftype == "" and patterns_for(info.name) then
				candidates[#candidates + 1] = {
					bufnr = bufnr,
					path = relative(root, info.name),
					lastused = info.lastused or 0,
					tick = vim.api.nvim_buf_get_changedtick(bufnr),
				}
			end
		end
	end

	table.sort(candidates, function(a, b)
		return a.lastused > b.lastused
	end)
	while #candidates > NEIGHBOUR_COUNT do
		table.remove(candidates)
	end
	table.sort(candidates, function(a, b)
		return a.path < b.path
	end)

	return candidates
end

local function render_neighbours(selected)
	local pieces = {}
	for _, item in ipairs(selected) do
		local lines = vim.api.nvim_buf_get_lines(item.bufnr, 0, -1, false)
		local body = table.concat(lines, "\n")
		if #body > NEIGHBOUR_BUDGET then
			body = body:sub(1, NEIGHBOUR_BUDGET)
			-- Drop the trailing partial line: a half-written statement reads as
			-- a syntax error rather than as an example to follow.
			body = body:match("(.*)\n[^\n]*$") or body
		end
		pieces[#pieces + 1] = ("<file path=%q>\n%s\n</file>"):format(item.path, body)
	end
	return table.concat(pieces, "\n\n")
end

--- The cacheable project preamble. Memoised on the index generation and on the
--- identity of the selected buffers, so a typing pause costs nothing here.
---@return string
function M.digest()
	if not state.index and not state.building then
		M.rebuild()
	end

	local selected = neighbours()

	local key_parts = { tostring(state.generation) }
	for _, item in ipairs(selected) do
		key_parts[#key_parts + 1] = item.path .. ":" .. item.tick
	end
	local key = table.concat(key_parts, "|")

	if key == state.memo_key then
		return state.memo_value
	end

	local sections = {}
	if state.index and state.index ~= "" then
		sections[#sections + 1] = "The declarations of every file in this project, for its layout and naming "
			.. "conventions:\n\n"
			.. state.index
	end
	if #selected > 0 then
		sections[#sections + 1] = "The files most recently open in the editor, in full. Follow the patterns they "
			.. "establish -- their helpers, their error handling, their naming:\n\n"
			.. render_neighbours(selected)
	end

	state.memo_key = key
	state.memo_value = table.concat(sections, "\n\n")
	return state.memo_value
end

--- Opens a scratch buffer with exactly what digest() is sending, which is the
--- only way to see whether the context is worth what it costs.
function M.inspect()
	local digest = M.digest()
	local bufnr = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(digest, "\n", { plain = true }))
	vim.api.nvim_set_option_value("filetype", "markdown", { buf = bufnr })
	vim.api.nvim_buf_set_name(bufnr, ("ai-context (%d chars)"):format(#digest))
	vim.cmd.tabnew()
	vim.api.nvim_win_set_buf(0, bufnr)
end

function M.setup()
	local group = vim.api.nvim_create_augroup("ai_context", { clear = true })

	-- A save is the only thing that changes a declaration on disk. Debounced,
	-- because rebuilding re-renders the prefix and costs one cache write.
	vim.api.nvim_create_autocmd("BufWritePost", {
		group = group,
		callback = function()
			if state.refresh_timer then
				state.refresh_timer:stop()
			end
			state.refresh_timer = vim.defer_fn(function()
				state.refresh_timer = nil
				M.rebuild()
			end, 5000)
		end,
		desc = "Refresh the AI project index after a save",
	})

	vim.api.nvim_create_autocmd("DirChanged", {
		group = group,
		callback = function()
			state.index = nil
			state.memo_key = nil
			M.rebuild()
		end,
		desc = "Rebuild the AI project index for the new working directory",
	})

	vim.api.nvim_create_user_command("AiContext", function()
		M.inspect()
	end, { desc = "Show the project context the AI completion is sending" })

	vim.api.nvim_create_user_command("AiContextRebuild", function()
		state.index = nil
		state.memo_key = nil
		M.rebuild()
	end, { desc = "Rebuild the AI project index now" })
end

return M
