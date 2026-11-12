-- Which database does this buffer run against?
--
-- Five rules, most specific first:
--
--   1. an explicit choice made in this session (,qc)
--   2. a binding saved for this exact file
--   3. a glob or folder from .nvim/databases.json
--   4. the project default
--   5. the last connection used in this project
--
-- Rules 1 and 2 are the same store: choosing a connection for a buffer saves
-- it, so the choice survives a restart (same idea as debugger/breakpoints.lua).
local db = require("db")
local connections = require("db.connections")

local M = {}

local bindings = {}
local last_used = nil
local loaded_root = nil

local function store_path()
	local dir = db.state_dir .. "/bindings"
	vim.fn.mkdir(dir, "p")
	return ("%s/%s.json"):format(dir, vim.fn.sha256(connections.project_root()))
end

local function read_store()
	local path = store_path()
	if vim.fn.filereadable(path) == 0 then
		return {}, nil
	end
	local ok, lines = pcall(vim.fn.readfile, path)
	if not ok then
		return {}, nil
	end
	local decoded, data = pcall(vim.json.decode, table.concat(lines, "\n"))
	if not decoded or type(data) ~= "table" then
		return {}, nil
	end
	return data.files or {}, data.last_used
end

local function load()
	local root = connections.project_root()
	if loaded_root == root then
		return
	end
	loaded_root = root
	bindings, last_used = read_store()
end

local function save()
	load()
	local payload = { files = bindings, last_used = last_used }
	if next(bindings) == nil and not last_used then
		pcall(vim.fn.delete, store_path())
		return
	end
	pcall(vim.fn.writefile, { vim.json.encode(payload) }, store_path())
end

--- Match a project-relative path against a glob. vim.glob.to_lpeg understands
--- "**", which glob2regpat does not.
local function match_glob(relative, pattern)
	local ok, parser = pcall(vim.glob.to_lpeg, pattern)
	if ok and parser then
		return parser:match(relative) ~= nil
	end
	-- Fall back to a regex, approximating "**" with ".*".
	local escaped = vim.fn.glob2regpat(pattern)
	return vim.fn.match(relative, escaped) >= 0
end

--- A pattern with more literal characters is more specific: "reports/**/*.sql"
--- beats "**/*.sql". Ties go to the first declared entry, because the order in
--- the file is the author's own ranking.
local function binding_for_path(relative)
	local best, best_score
	for _, binding in ipairs(connections.project_bindings()) do
		local pattern = binding.glob or (binding.dir and (binding.dir:gsub("/$", "") .. "/**"))
		if pattern and binding.connection and match_glob(relative, pattern) then
			local score = #(pattern:gsub("[%*%?]", ""))
			if not best_score or score > best_score then
				best, best_score = binding.connection, score
			end
		end
	end
	return best
end

--- @return table|nil connection
--- @return string|nil reason which rule matched, for :DbWhich
function M.for_buf(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	load()

	local path = vim.api.nvim_buf_get_name(bufnr)
	local candidates = {}

	-- An explicit choice for this buffer, which is also what a scratch buffer
	-- with no file on disk has to rely on.
	if vim.b[bufnr].db_connection_resolved then
		candidates[#candidates + 1] = { vim.b[bufnr].db_connection_resolved, "chosen for this buffer" }
	end

	if path ~= "" and bindings[path] then
		candidates[#candidates + 1] = { bindings[path], "saved for this file" }
	end

	if path ~= "" then
		local root = connections.project_root()
		local normalized = vim.fs.normalize(path)
		if vim.startswith(normalized, vim.fs.normalize(root) .. "/") then
			local relative = normalized:sub(#vim.fs.normalize(root) + 2)
			local id = binding_for_path(relative)
			if id then
				candidates[#candidates + 1] = { id, "matched a binding in .nvim/databases.json" }
			end
		end
	end

	local default = connections.project_default()
	if default then
		candidates[#candidates + 1] = { default, "project default" }
	end
	if last_used then
		candidates[#candidates + 1] = { last_used, "last used in this project" }
	end

	for _, candidate in ipairs(candidates) do
		local connection = connections.get(candidate[1])
		if connection then
			return connection, candidate[2]
		end
	end
	return nil, nil
end

--- Remember the connection for this buffer's file, and as the project's last used.
function M.bind(bufnr, id)
	load()
	local path = vim.api.nvim_buf_get_name(bufnr)
	if path ~= "" then
		bindings[path] = id
	end
	last_used = id
	vim.b[bufnr].db_connection_resolved = id
	save()
	-- The language server answers from the chosen database's catalog, so the
	-- choice starts it rather than the next FileType: this is also the path
	-- M.pick and the explorer take.
	require("db.lsp").start(bufnr)
end

function M.unbind(bufnr)
	load()
	local path = vim.api.nvim_buf_get_name(bufnr)
	if path ~= "" then
		bindings[path] = nil
	end
	vim.b[bufnr].db_connection_resolved = nil
	save()
end

function M.set_last_used(id)
	load()
	last_used = id
end

--- Ask for a connection and apply it to the buffer. vim.ui.select is a
--- Telescope dropdown in this config (telescope-ui-select).
function M.pick(bufnr, on_done)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local list = connections.all()
	if #list == 0 then
		db.notify("no connections configured; run :DbInit", vim.log.levels.WARN)
		return
	end
	vim.ui.select(list, {
		prompt = "Database connection",
		format_item = function(connection)
			return ("%s  [%s]  %s"):format(connection.name, connection.driver, connection.scope)
		end,
	}, function(choice)
		if not choice then
			return
		end
		M.bind(bufnr, choice.id)
		require("db.dialect").attach(bufnr, choice.driver)
		db.notify(("%s selected for this buffer"):format(choice.name))
		if on_done then
			on_done(choice)
		end
	end)
end

function M.setup()
	local group = vim.api.nvim_create_augroup("DbBindings", { clear = true })
	vim.api.nvim_create_autocmd("VimLeavePre", { group = group, callback = save })
	vim.api.nvim_create_autocmd("DirChanged", {
		group = group,
		callback = function()
			save()
			loaded_root = nil
		end,
	})
end

return M
