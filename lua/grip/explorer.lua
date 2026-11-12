-- The database explorer: a Telescope picker you walk into, like the file browser.
--
-- neogrip answers the catalog as data and ships no explorer of its own (its
-- ADR-0037), so the one the editor shows is this file. It is the file browser's
-- shape on purpose -- the same plugin, the same full-window layout, a ".." row
-- that walks back out, a pane beside the list describing whatever the cursor is
-- on -- because a database is a tree you browse and this editor already has a
-- way of browsing trees.
--
--   connections -> databases -> schemas -> tables -> columns
--
-- Which of those a connection actually has is the engine's shape and none of
-- this file's business: neogrip's tree answers the walk already truncated --
-- SQLite has neither databases nor schemas, MySQL calls its one level a
-- database, Trino has catalogs full of them -- so every level here is "the
-- children of the node I am on" and nothing here names an engine. The one
-- exception is walking into a database on PostgreSQL or SQL Server, which
-- cannot query across them: see M.walk_into.
--
-- The keys, which are the file browser's where they mean the same thing:
--
--   <CR>   walk in; on a table open its definition; on a column insert its name
--   <BS>   walk back out  (insert mode: when the prompt is empty)
--   <C-o>  walk in anyway -- a table's columns, where <CR> stops
--   <C-s>  a SELECT in a query buffer           <C-g>  pick the statement to write
--   <C-y>  insert the qualified name where the explorer was opened from
--   <C-d>  open it as a document: a table's definition, a schema's listing
--   <C-l>  sample this table's rows into the pane
--   <C-e>  export what the cursor is on as a runnable DDL file: a schema with
--          all its tables, an instance with all its schemas, a table alone
--   <C-r>  forget the cached catalog, re-read it, and sweep it again
--
-- The window is reused between levels by refreshing the finder, so walking the
-- tree does not flash a new picker on every step. Telescope's refresh is not
-- public API, so every call is wrapped and falls back to reopening.
local connections = require("neogrip.connections")
local grip = require("grip")
local preview = require("grip.preview")
local tree = require("neogrip.catalog.tree")

local M = {}

local function notify(message, level)
	vim.notify("DB: " .. message, level or vim.log.levels.INFO)
end

--- A frame is one level on screen: the node whose children are listed -- nil
--- for the configured connections, which is where the walk starts -- plus what
--- those children turned out to be and how this engine labels them.
--- @class grip.Frame
--- @field node table|nil
--- @field level string|nil
--- @field label string|nil

--- The entries of a level, plus the row that walks back out of it.
---
--- The same row the file browser puts at the top of a directory, because a way
--- back you have to remember is a way back you do not use. The sorter drops it
--- as soon as you type a letter, which is what happens to the file browser's
--- own ".." and is right: while you are filtering you want tables, not the way
--- out.
--- @param stack grip.Frame[] the frames walked through to get here
function M.with_parent(nodes, stack)
	if #stack == 0 then
		return nodes
	end
	local above = stack[#stack]
	local list = { { parent = true, text = (".. %s"):format(above.label or "back") } }
	vim.list_extend(list, nodes)
	return list
end

--- One row: the icon and the name, then whatever is worth knowing about it.
function M.row(node)
	local hint = grip.hint_of(node)
	if hint == "" then
		return grip.display(node)
	end
	return ("%-40s %s"):format(grip.display(node), hint)
end

--- The title: the level, and the walk that led to it.
--- @param frame grip.Frame
function M.title(frame)
	local label = frame.label or "Connections"
	local path = frame.node and grip.path_of(frame.node.ref) or ""
	if path == "" then
		return label
	end
	return ("%s  %s"):format(label, path)
end

--- What this node is called in SQL, quoted the way this engine quotes.
function M.name_of(node)
	if node.parent then
		return ""
	end
	local connection = connections.get(node.ref.server)
	if node.level == "attribute" and connection then
		-- qualified_name answers for the set a column belongs to, which is not
		-- what you want when the cursor is on the column.
		return require("neogrip.catalog").quote(connection.driver, node.name)
	end
	return tree.qualified_name(node.ref) or tostring(node.name)
end

--- A server node for a connection, which is where a walk begins.
local function server_node(connection)
	local ref = { server = connection.id }
	return {
		id = tree.id(ref),
		level = "server",
		kind = connection.driver,
		name = connection.name or connection.id,
		ref = ref,
		expandable = true,
		source = "cache",
		facts = {},
	}
end

--- The node to expand, which is not always the node under the cursor.
---
--- Walking into a database on an engine that binds a connection to one means a
--- connection pointed at that database: PostgreSQL and SQL Server cannot query
--- across databases, so JDBC answers nothing about another one's schemas and
--- the level below would come back empty. neogrip marks that level
--- `reconnects` and leaves the reopening to the client (its ADR-0039), which is
--- here: the derived connection is registered under an id of its own and never
--- written to a config file, so it lasts the session and the walk continues
--- from its server node as if it had always been configured.
---
--- Trino leaves the flag off -- one session queries every catalog, so picking
--- one only changes the names a statement is written with -- and there the node
--- under the cursor is the node that gets expanded.
function M.walk_into(node)
	if node.level ~= "instance" or not (node.facts or {}).reconnects then
		return node
	end
	local connection = connections.get(node.ref.server)
	if not connection or connection.database == node.name then
		return node
	end

	local id = ("%s/%s"):format(connection.id, node.name)
	local derived = connections.get(id)
	if not derived then
		derived = vim.deepcopy(connection)
		derived.id = id
		derived.name = ("%s · %s"):format(connection.name or connection.id, node.name)
		derived.database = node.name
		-- The catalog field is Trino's, and Trino never reaches this branch.
		derived.catalog = nil
		connections.register(derived)
	end

	return server_node(derived)
end

-- Databases a sweep has been started for, so a failure is reported once rather
-- than on every open. ,qi forces another.
local sweeps = {}

--- Is there a catalog to sweep yet, and which one?
---
--- "No catalog" is not the same question per engine: for SQLite it is the whole
--- database, and for Trino it would mean every catalog on the server. So a
--- sweep waits until the walk has reached something that names one -- which,
--- for a connection that names its own database, is true from the start.
--- @return table|nil ref
function M.sweep_target(connection, node)
	local shape = tree.shape(connection)
	if not shape.sweepable then
		-- A collection catalog cannot be swept: a document store is described by
		-- sampling documents (neogrip's ADR-0029).
		return nil
	end
	if node.level == "instance" then
		return node.ref
	end
	if node.level ~= "server" then
		return nil
	end
	for _, entry in ipairs(shape.levels) do
		if entry.level == "instance" then
			-- A database still to be chosen.
			return nil
		end
	end
	return node.ref
end

--- Sweep this database once, in the background, the first time the explorer
--- reaches it.
---
--- Started and never waited for: the levels keep being served a round trip at a
--- time while it runs, and once it lands the whole walk -- and every table's
--- definition in the pane beside it -- is answered from disk instead. This is
--- the difference between an explorer that stutters and one that does not.
function M.prepare(connection, node)
	if not connection then
		return
	end
	local ref = M.sweep_target(connection, node)
	if not ref then
		return
	end
	local key = ("%s|%s"):format(connection.id, tostring(ref.instance or ""))
	if sweeps[key] or tree.swept(ref) then
		return
	end
	sweeps[key] = true
	local name = connection.name or connection.id
	notify(("introspecting %s in the background; the explorer works meanwhile"):format(name))
	tree.sweep(ref, {}, function(summary, err)
		if err or type(summary) ~= "table" then
			return notify(
				("introspecting %s failed: %s"):format(name, grip.message_of(err or "no answer")),
				vim.log.levels.WARN
			)
		end
		notify(("%s: %s ready to explore"):format(name, grip.counted(summary.tables or 0, "table")))
	end)
end

--- The thing itself, as a buffer: a table's definition, a schema's listing.
---
--- Named by its neogrip:// URI and filled by neogrip's own reader rather than
--- written here, so this <CR> and an :edit of the same name from anywhere else
--- -- a go-to-definition out of a query, a buffer recovered from a session --
--- land in the one buffer.
function M.open_document(node)
	local connection = connections.get(node.ref.server)
	if not connection then
		return nil
	end
	local document = require("neogrip.ui.document")
	local catalog, namespace = grip.qualifiers(connection, node.ref)

	if node.level == "namespace" then
		return document.open(document.schema_uri(connection, catalog, node.name))
	end
	if node.level ~= "set" and node.level ~= "attribute" then
		return nil
	end

	local set = node.level == "set" and node.name or node.ref.set
	local bufnr, winid = document.open(document.table_uri(connection, catalog, namespace, set))
	if node.level == "set" or not bufnr then
		return bufnr
	end

	-- On a column, land on the line that defines it. The definition can still be
	-- a round trip away, so the line is looked for once now and once after it has
	-- had time to arrive; failing that the buffer is open at the top, which is
	-- where it would have been anyway.
	local function focus()
		if not vim.api.nvim_buf_is_valid(bufnr) then
			return true
		end
		local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
		local line = document.column_line(lines, node.name)
		if not line then
			return false
		end
		pcall(vim.api.nvim_win_set_cursor, winid or 0, { line, 4 })
		return true
	end
	if not focus() then
		vim.defer_fn(focus, 300)
	end
	return bufnr
end

--- A statement to start from, in a query buffer. Text only: nothing is run.
--- @param kind string "select" | "insert" | "update" | "delete"
function M.open_statement(node, kind)
	local connection = connections.get(node.ref.server)
	if not connection then
		return
	end
	tree.statement(node.ref, kind, function(text, err)
		if err or not text then
			return notify(grip.message_of(err or "no statement for that"), vim.log.levels.ERROR)
		end
		require("neogrip.ui.buffer").new_query(connection, text)
	end)
end

--- Write a name into the buffer the explorer was opened from.
---
--- Both the window and the buffer are remembered, because the window is not
--- enough: by the time this runs it may be showing something else, and putting
--- the text into whatever is current would edit the wrong file.
function M.insert_name(origin_win, origin_buf, name)
	if not name or name == "" then
		return
	end
	local target_win = nil
	if
		origin_win
		and vim.api.nvim_win_is_valid(origin_win)
		and vim.api.nvim_win_get_buf(origin_win) == origin_buf
	then
		target_win = origin_win
	else
		for _, winid in ipairs(vim.api.nvim_list_wins()) do
			if vim.api.nvim_win_get_buf(winid) == origin_buf then
				target_win = winid
				break
			end
		end
	end

	if target_win then
		vim.api.nvim_set_current_win(target_win)
		vim.api.nvim_put({ name }, "c", true, true)
		return
	end

	-- The buffer is not on screen any more: write at its last cursor position
	-- without making it current.
	if origin_buf and vim.api.nvim_buf_is_valid(origin_buf) then
		local mark = vim.api.nvim_buf_get_mark(origin_buf, '"')
		local row = math.max(mark[1] - 1, 0)
		local line = vim.api.nvim_buf_get_lines(origin_buf, row, row + 1, false)[1] or ""
		vim.api.nvim_buf_set_text(origin_buf, row, #line, row, #line, { name })
	end
end

--- @param opts table|nil { frame, stack, origin_buf, origin_win }
function M.open(opts)
	opts = opts or {}
	local origin_buf = opts.origin_buf or vim.api.nvim_get_current_buf()
	local origin_win = opts.origin_win or vim.api.nvim_get_current_win()

	-- No frame asked for means this is the entry and not a step. The walk opens
	-- on the database this buffer runs against -- which neogrip's resolve
	-- already knows, so asking would be asking a question that has an answer --
	-- with the list of every configured connection one ".." above it.
	local frame, stack = opts.frame, opts.stack
	if not frame then
		local connection = require("neogrip.connections.resolve").for_buf(origin_buf)
		if connection then
			frame = { node = server_node(connection) }
			stack = { { node = nil, level = "server", label = "Connections" } }
		else
			frame = { node = nil }
			stack = {}
		end
	end

	local ok_telescope, pickers = pcall(require, "telescope.pickers")
	if not ok_telescope then
		return notify("telescope is not available", vim.log.levels.ERROR)
	end
	local finders = require("telescope.finders")
	local conf = require("telescope.config").values
	local actions = require("telescope.actions")
	local action_state = require("telescope.actions.state")

	-- Where this picker currently is. Mutable on purpose: walking a level
	-- refreshes the one picker instead of closing it and building another, so
	-- the previewer and the mappings are created once and read the frame from
	-- here rather than from what they captured.
	local state = { frame = frame, stack = stack or {} }

	--- The children of a frame, with the level and the label they turned out to
	--- be filled in: which level comes next is the engine's shape, so it is read
	--- off the answer rather than predicted.
	local function load(target, done)
		if target.node then
			M.prepare(connections.get(target.node.ref.server), target.node)
		end
		tree.children(target.node, {}, function(nodes, err)
			if err then
				return notify(grip.message_of(err), vim.log.levels.ERROR)
			end
			if not nodes or #nodes == 0 then
				if not target.node then
					return notify(
						"no connections configured: write .nvim/database.json in the project",
						vim.log.levels.WARN
					)
				end
				return notify(("%s holds nothing"):format(grip.path_of(target.node.ref)), vim.log.levels.WARN)
			end
			target.level = nodes[1].level
			target.label = grip.label_of(
				target.node and connections.get(target.node.ref.server) or nil,
				target.node and target.level or nil
			)
			done(nodes)
		end)
	end

	load(state.frame, function(entries)
		local picker, prompt_buf

		local function finder_for(nodes)
			return finders.new_table({
				results = M.with_parent(nodes, state.stack),
				entry_maker = function(item)
					return {
						value = item,
						display = M.row(item),
						-- The icon is left out on purpose: typing filters names,
						-- not glyphs. And the way back sorts as ".." and not as
						-- the level it goes to, so typing a schema's name cannot
						-- leave the cursor on the row that leaves the schema.
						ordinal = item.parent and ".."
							or vim.trim(("%s %s"):format(item.name or "", grip.hint_of(item))),
					}
				end,
			})
		end

		--- Put the cursor on the first real row rather than on "..".
		---
		--- The first result is drawn next to the prompt and the selection resets
		--- to it after every sort, so walking into a level would leave <CR>
		--- pointing straight back out. Telescope runs these callbacks when a sort
		--- settles, which is the hook the file browser uses for the same problem;
		--- default_selection_index would also fire while typing, where the ".."
		--- row has been filtered away and row two is a real result.
		local function keep_cursor_off_parent()
			if not picker then
				return
			end
			picker._completion_callbacks = picker._completion_callbacks or {}
			table.insert(picker._completion_callbacks, function(self)
				local manager = self.manager
				local first = manager and manager:get_entry(1)
				if first and first.value and first.value.parent and manager:num_results() > 1 then
					pcall(self.set_selection, self, self:get_row(2))
				end
				table.remove(self._completion_callbacks)
			end)
		end

		--- Move this picker to another frame in place.
		---
		--- Telescope's refresh and its title setter are both internal, so a
		--- failure here falls back to closing and reopening, which is what every
		--- step did before the refresh existed.
		local function go(target, next_stack)
			load(target, function(nodes)
				state.frame, state.stack = target, next_stack
				local title = M.title(target)
				local refreshed = picker
					and pcall(function()
						keep_cursor_off_parent()
						picker:refresh(finder_for(nodes), { reset_prompt = true })
						picker.prompt_title = title
						if picker.prompt_border and picker.prompt_border.change_title then
							picker.prompt_border:change_title(" " .. title .. " ")
						end
					end)
				if not refreshed then
					if prompt_buf then
						pcall(actions.close, prompt_buf)
					end
					M.open({
						frame = target,
						stack = next_stack,
						origin_buf = origin_buf,
						origin_win = origin_win,
					})
				end
			end)
		end

		pickers
			-- Almost no layout of its own: the defaults in
			-- plugins/editor/telescope.lua are a full-window horizontal split
			-- with the preview taking half, and this is one of the editor's
			-- pickers rather than a dialog, so anything spelled out here would
			-- drift from the rest of them. The one exception is the cutoff:
			-- Telescope drops the preview entirely below 120 columns, and for
			-- this picker the pane is half the point -- a narrow one still says
			-- what a table is, where no pane at all says nothing. The merge is
			-- depth two, so the width, the height and the preview's share are
			-- still the ones every other picker uses.
			.new({}, {
				layout_config = { horizontal = { preview_cutoff = 0 } },
				prompt_title = M.title(state.frame),
				finder = finder_for(entries),
				sorter = conf.generic_sorter({}),
				previewer = preview.previewer(),
				attach_mappings = function(prompt_bufnr, map)
					prompt_buf = prompt_bufnr
					picker = action_state.get_current_picker(prompt_bufnr)
					-- Reopening after a failed refresh lands on a level that has a
					-- way back, and this is the first moment the picker exists to
					-- register against.
					keep_cursor_off_parent()

					local function selected()
						local entry = action_state.get_selected_entry()
						return entry and entry.value or nil
					end

					local function go_back()
						local above = state.stack[#state.stack]
						if not above then
							-- The top of the tree is the connection list, so there
							-- is nothing above it; <Esc> and q are how you leave.
							return
						end
						local next_stack = vim.deepcopy(state.stack)
						table.remove(next_stack)
						go(above, next_stack)
					end

					local function descend(item)
						if item.parent or not item.expandable then
							return false
						end
						local next_stack = vim.deepcopy(state.stack)
						next_stack[#next_stack + 1] = state.frame
						go({ node = M.walk_into(item) }, next_stack)
						return true
					end

					--- Only where it makes sense: a statement needs a table.
					local function on_set(callback)
						return function()
							local item = selected()
							if not item or item.parent or item.level ~= "set" then
								return
							end
							callback(item)
						end
					end

					actions.select_default:replace(function()
						local item = selected()
						if not item then
							return
						end
						-- Before anything else: on the ".." row every action below
						-- would be asking about a table called "..".
						if item.parent then
							return go_back()
						end
						if item.level == "set" then
							-- A table is where walking in stops being a list: the
							-- definition is the thing, and <C-o> still steps into
							-- the columns.
							actions.close(prompt_bufnr)
							return M.open_document(item)
						end
						if item.level == "attribute" then
							-- The deepest level: inserting the name is the only
							-- useful thing left to do with a column.
							local name = M.name_of(item)
							actions.close(prompt_bufnr)
							return M.insert_name(origin_win, origin_buf, name)
						end
						descend(item)
					end)

					map("i", "<BS>", function()
						-- Only leave the level when the prompt is empty, so
						-- backspace still edits the filter.
						if action_state.get_current_line() == "" then
							go_back()
						else
							vim.api.nvim_feedkeys(vim.keycode("<BS>"), "n", false)
						end
					end, { desc = "DB: back out of this level" })
					map("n", "<BS>", go_back, { desc = "DB: back out of this level" })

					map({ "i", "n" }, "<C-o>", function()
						local item = selected()
						if item then
							descend(item)
						end
					end, { desc = "DB: walk in (a table's columns)" })

					map({ "i", "n" }, "<C-s>", on_set(function(item)
						actions.close(prompt_bufnr)
						M.open_statement(item, "select")
					end), { desc = "DB: SELECT in a query buffer" })

					map({ "i", "n" }, "<C-g>", on_set(function(item)
						actions.close(prompt_bufnr)
						vim.ui.select({ "select", "insert", "update", "delete" }, {
							prompt = ("Statement for %s"):format(item.name),
						}, function(kind)
							if kind then
								M.open_statement(item, kind)
							end
						end)
					end), { desc = "DB: write a statement for this table" })

					map({ "i", "n" }, "<C-y>", function()
						local item = selected()
						if not item or item.parent then
							return
						end
						local name = M.name_of(item)
						actions.close(prompt_bufnr)
						M.insert_name(origin_win, origin_buf, name)
					end, { desc = "DB: insert this name where I came from" })

					map({ "i", "n" }, "<C-d>", function()
						local item = selected()
						if not item or item.parent then
							return
						end
						if item.level ~= "set" and item.level ~= "namespace" and item.level ~= "attribute" then
							return
						end
						actions.close(prompt_bufnr)
						M.open_document(item)
					end, { desc = "DB: open this as a document" })

					map({ "i", "n" }, "<C-l>", on_set(function(item)
						-- The pane decides what it draws, so asking for rows is
						-- telling it this table is one to sample and then having
						-- it drawn again -- the same path the cursor landing here
						-- takes, rather than a second way of writing a pane.
						preview.force_rows(item)
						if picker and picker.refresh_previewer then
							pcall(picker.refresh_previewer, picker)
						end
					end), { desc = "DB: sample this table's rows" })

					map({ "i", "n" }, "<C-e>", function()
						-- Whatever the cursor is on, as one runnable DDL script
						-- (neogrip's ADR-0047): on a schema that schema with every
						-- table in it, on an instance every schema of it, on a
						-- table that one table, on a connection the whole database
						-- -- through the same reconnect derivation walking in
						-- uses. On the ".." row the level itself is the target. A
						-- column row exports the table it belongs to: a column
						-- alone has no definition.
						local item = selected()
						local node
						if item and not item.parent then
							node = M.walk_into(item)
						else
							node = state.frame.node
						end
						if not node then
							return
						end
						local ref = {
							server = node.ref.server,
							instance = node.ref.instance,
							namespace = node.ref.namespace,
							set = node.ref.set,
						}
						local connection = connections.get(ref.server)
						if not connection then
							return
						end
						local parts = { connection.id }
						for _, key in ipairs({ "instance", "namespace", "set" }) do
							if ref[key] then
								parts[#parts + 1] = tostring(ref[key])
							end
						end
						local stem = table.concat(parts, "-"):gsub("[^%w%-_.]", "-")
						actions.close(prompt_bufnr)
						vim.ui.input({
							prompt = "Write the DDL to: ",
							default = vim.fs.joinpath(vim.fn.getcwd(), stem .. ".sql"),
							completion = "file",
						}, function(path)
							if not path or path == "" then
								return
							end
							notify(("exporting %s in the background"):format(connection.name or connection.id))
							require("neogrip.catalog.export").script(ref, { path = path }, function(summary, err)
								if err then
									return notify(grip.message_of(err), vim.log.levels.ERROR)
								end
								local counted = ("%d tables, %d views"):format(summary.tables, summary.views)
								if summary.collections > 0 then
									counted = counted .. (", %d collections"):format(summary.collections)
								end
								if summary.skipped > 0 then
									counted = counted .. (", %d skipped"):format(summary.skipped)
								end
								notify(("DDL written to %s: %s"):format(summary.path, counted))
							end)
						end)
					end, { desc = "DB: export the DDL of what the cursor is on" })

					map({ "i", "n" }, "<C-r>", function()
						local node = state.frame.node
						preview.forget()
						if node then
							tree.forget(node.ref)
							local connection = connections.get(node.ref.server)
							local ref = connection and M.sweep_target(connection, node) or nil
							if ref then
								sweeps[("%s|%s"):format(connection.id, tostring(ref.instance or ""))] = nil
							end
						end
						notify("re-reading the catalog")
						go(state.frame, state.stack)
					end, { desc = "DB: forget the cached catalog and re-read it" })

					return true
				end,
			})
			:find()
	end)
end

return M
