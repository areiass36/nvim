-- What the runner shows: the :RunnerCheck report and the :RunnerPlan waves.
-- Line building is pure so the tests can read it; the window is a plain scratch
-- float, like :Doctor.
local address = require("runner.address")
local schema = require("runner.schema")

local M = {}

local function icons()
	return require("runner").options.icons
end

local function count(list)
	return type(list) == "table" and #list or 0
end

local function plural(amount, word)
	return ("%d %s%s"):format(amount, word, amount == 1 and "" or "s")
end

local function labels_of(project)
	local labels = {}
	for _, runner in ipairs(project.runner or {}) do
		labels[#labels + 1] = type(runner.label) == "string" and runner.label or "?"
	end
	return table.concat(labels, ", ")
end

local function members_of(cluster)
	local parts = {}
	for _, member in ipairs(cluster.member or {}) do
		if type(member) == "table" then
			parts[#parts + 1] = address.format(member)
		end
	end
	return table.concat(parts, " + ")
end

local function append_entries(lines, mark, entries)
	for _, entry in ipairs(entries) do
		lines[#lines + 1] = ("  %s %s"):format(mark, schema.format(entry))
	end
end

local function append_inventory(lines, doc)
	local icon = icons()

	lines[#lines + 1] = ""
	lines[#lines + 1] = "Projects"
	for _, project in ipairs(doc.project or {}) do
		lines[#lines + 1] = ("  %-10s %-18s %s"):format(
			project.name or "?",
			project.path or "?",
			labels_of(project)
		)
	end

	if count(doc.cluster) > 0 then
		lines[#lines + 1] = ""
		lines[#lines + 1] = "Clusters"
		for _, cluster in ipairs(doc.cluster) do
			lines[#lines + 1] = ("  %s%-9s %s"):format(icon.cluster, cluster.name or "?", members_of(cluster))
		end
	end

	if count(doc.link) > 0 then
		lines[#lines + 1] = ""
		lines[#lines + 1] = "Links"
		for _, link in ipairs(doc.link) do
			lines[#lines + 1] = ("  %-10s %s"):format(link.name or "?", link.path or "?")
		end
	end

	if doc.default then
		lines[#lines + 1] = ""
		lines[#lines + 1] = ("Default    %s"):format(address.format(doc.default))
	end
end

--- @return string[] lines
function M.check_lines(workspace)
	local icon = icons()
	local errors, warnings = workspace.errors or {}, workspace.warnings or {}
	local lines = { ("%s  %s"):format(workspace.name or "(unnamed)", workspace.file) }

	if #errors == 0 then
		local doc = workspace.doc or {}
		lines[#lines + 1] = ("%s %s, %s, %s"):format(
			icon.ok,
			plural(count(doc.project), "project"),
			plural(count(doc.cluster), "cluster"),
			plural(count(doc.link), "link")
		)
	else
		lines[#lines + 1] = ("%s %s"):format(icon.error, plural(#errors, "error"))
		append_entries(lines, icon.error, errors)
	end

	if #warnings > 0 then
		lines[#lines + 1] = ""
		lines[#lines + 1] = ("%s %s"):format(icon.warn, plural(#warnings, "warning"))
		append_entries(lines, icon.warn, warnings)
	end

	if #errors == 0 and workspace.doc then
		append_inventory(lines, workspace.doc)
	end

	return lines
end

-- ------------------------------------------------------------------ plan
local function ready_summary(ready)
	if type(ready) ~= "table" then
		return "no wait"
	end
	if ready.port then
		return ("port %d"):format(ready.port)
	end
	if ready.http then
		return ("http %s"):format(ready.http)
	end
	if ready.log then
		return ("log /%s/"):format(ready.log)
	end
	if ready.delay then
		return ("%dms"):format(ready.delay)
	end
	return "?"
end

local function node_summary(node)
	local spec = node.spec
	local parts = {}
	if spec.command then
		parts[#parts + 1] = table.concat(spec.command, " ")
	end
	if spec.debug then
		parts[#parts + 1] = ("[dap %s %s]"):format(spec.debug.adapter, spec.debug.request or "launch")
	end
	parts[#parts + 1] = ("[%s]"):format(ready_summary(spec.ready))
	if spec.oneShot then
		parts[#parts + 1] = "[one shot]"
	end
	if spec.singleton then
		parts[#parts + 1] = "[singleton]"
	end
	return table.concat(parts, "  ")
end

--- @return string[] lines
function M.plan_lines(plan)
	local icon = icons()
	local lines = { ("target  %s"):format(plan.entry or "?") }

	if #plan.errors > 0 then
		lines[#lines + 1] = ("%s %s"):format(icon.error, plural(#plan.errors, "error"))
		append_entries(lines, icon.error, plan.errors)
		return lines
	end

	lines[#lines + 1] = ("%s %s in %s"):format(
		icon.ok,
		plural(#plan.nodes, "runner"),
		plural(#plan.waves, "wave")
	)
	for index, wave in ipairs(plan.waves) do
		lines[#lines + 1] = ""
		lines[#lines + 1] = ("wave %d%s"):format(index, index > 1 and "  (waits for the one above)" or "")
		for _, node in ipairs(wave) do
			lines[#lines + 1] = ("  %s %-20s %s"):format(icon.runner, node.display, node_summary(node))
		end
	end

	if #plan.skipped > 0 then
		lines[#lines + 1] = ""
		lines[#lines + 1] = ("%s %s"):format(icon.warn, plural(#plan.skipped, "runner") .. " skipped here")
		for _, node in ipairs(plan.skipped) do
			lines[#lines + 1] = ("  %s %-20s %s"):format(icon.warn, node.display, node.skipped)
		end
	end

	return lines
end

function M.show(lines, title)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modifiable = false
	vim.bo[buf].bufhidden = "wipe"

	local width = math.min(110, vim.o.columns - 4)
	vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		row = 1,
		col = math.floor((vim.o.columns - width) / 2),
		width = width,
		height = math.min(#lines + 2, vim.o.lines - 4),
		border = "rounded",
		title = (" %s "):format(title),
		title_pos = "center",
		style = "minimal",
	})
	vim.keymap.set("n", "q", "<cmd>close<CR>", { buffer = buf, nowait = true })
	vim.keymap.set("n", "<Esc>", "<cmd>close<CR>", { buffer = buf, nowait = true })
	return buf
end

return M
