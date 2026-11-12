-- How debugging looks: a separate "debug tab" with the dap-ui panels, focused
-- floats for quick looks -- the program output full screen, like the terminal of
-- this config -- session notifications and a real terminal for adapters that
-- cannot provide one.
local dap = require("dap")
local dapui = require("dapui")
local icons = require("core.icons")

local M = {}

local SIGNS = {
	DapBreakpoint = { text = icons.breakpoint, texthl = "DiagnosticError" },
	DapBreakpointCondition = { text = icons.breakpoint_condition, texthl = "DiagnosticWarn" },
	DapBreakpointRejected = { text = icons.breakpoint_rejected, texthl = "DiagnosticHint" },
	DapStopped = { text = icons.stopped, texthl = "DiagnosticInfo", linehl = "Visual" },
}

local FLOAT_FILETYPES = {
	"dapui_scopes",
	"dapui_stacks",
	"dapui_breakpoints",
	"dapui_watches",
	"dapui_console",
	"dapui_hover",
	"dap-repl",
	"dap-float",
}

local function notify(message, level)
	vim.notify("[dap] " .. message, level or vim.log.levels.INFO)
end

local function is_floating(win)
	return vim.api.nvim_win_get_config(win).relative ~= ""
end

-- ---------------------------------------------------------------- floats
-- Two shapes, both taken from the rest of this config: program output opens like
-- the terminal (lua/plugins/editor/toggleterm.lua) -- the whole screen, no
-- border -- and the inspection panels open like the database document float, a
-- wide rounded one. Both are entered on open and close with q or Esc.
--
-- dapui.float_element is not used for them: it anchors the window at the cursor,
-- shrinks it to the content and registers "au WinEnter,CursorMoved * ++once
-- close_float", so a panel that does not hold the focus dies on the next cursor
-- move; and its single open_float slot swallows the next call when a float was
-- closed behind its back.

--- @alias debugger.Shape "terminal"|"panel"

--- @param shape debugger.Shape
local function window_config(shape, title)
	if shape == "terminal" then
		return {
			relative = "editor",
			row = 0,
			col = 0,
			width = vim.o.columns,
			height = vim.o.lines - 2,
			border = "none",
			style = "minimal",
		}
	end
	return {
		relative = "editor",
		row = 1,
		col = 2,
		width = vim.o.columns - 4,
		height = vim.o.lines - 6,
		border = "rounded",
		title = (" %s "):format(title or "debug"),
		title_pos = "center",
		style = "minimal",
	}
end

-- win -> { buf, shape, title }: a resize keeps a full screen float full screen,
-- and a stop takes the quick looks off the screen.
local floats = {}

local function close_floats()
	for _, win in ipairs(vim.tbl_keys(floats)) do
		if vim.api.nvim_win_is_valid(win) then
			pcall(vim.api.nvim_win_close, win, true)
		end
		floats[win] = nil
	end
end

--- nvim-dap opens the debuggee's terminal with no window of its own, so its pty
--- is sized at half the screen (session.lua: height = ceil(lines / 2)). Telling
--- the job the size of the window it is shown in keeps the program's own line
--- breaks straight.
local function fit_pty(win, buf)
	local job = vim.b[buf] and vim.b[buf].terminal_job_id
	if job then
		pcall(vim.fn.jobresize, job, vim.api.nvim_win_get_width(win), vim.api.nvim_win_get_height(win))
	end
end

local function resize_floats()
	for win, float in pairs(floats) do
		if vim.api.nvim_win_is_valid(win) then
			pcall(vim.api.nvim_win_set_config, win, window_config(float.shape, float.title))
			fit_pty(win, float.buf)
		end
	end
end

--- Open `buf` focused in a float of this shape. A buffer already on screen is
--- jumped to instead of stacked twice: the panels share their buffer with the
--- debug tab.
--- @param shape debugger.Shape
local function open_float(buf, shape, title, tail)
	for win, float in pairs(floats) do
		if float.buf == buf and vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_set_current_win(win)
			return win
		end
	end

	local win = vim.api.nvim_open_win(buf, true, window_config(shape, title))
	floats[win] = { buf = buf, shape = shape, title = title }
	vim.api.nvim_create_autocmd("WinClosed", {
		pattern = tostring(win),
		once = true,
		callback = function()
			floats[win] = nil
		end,
	})

	vim.keymap.set("n", "q", "<cmd>close<CR>", { buffer = buf, nowait = true })
	vim.keymap.set({ "n", "t" }, "<Esc>", function()
		vim.cmd("stopinsert")
		if is_floating(0) then
			vim.api.nvim_win_close(0, true)
		end
	end, { buffer = buf, nowait = true })

	fit_pty(win, buf)
	if tail then
		vim.cmd("normal! G")
	end
	return win
end

--- Show a buffer full screen, like the terminal of this config.
function M.float_buffer(buf, title)
	return open_float(buf, "terminal", title, true)
end

-- Output grows at the bottom; a variable tree is read from the top.
local TAIL = { console = true, repl = true }

--- A dap-ui element in a focused float. The buffer comes from the element
--- itself, so the window is ours and survives a cursor move.
function M.float_element(name)
	local element = dapui.elements[name]
	if not element then
		return notify("no such element: " .. name, vim.log.levels.ERROR)
	end
	-- The element renders through nio, so it needs a task of its own.
	pcall(require("nio").run, element.render)
	local ok, buf = pcall(element.buffer)
	if not ok or type(buf) ~= "number" or not vim.api.nvim_buf_is_valid(buf) then
		return notify(name .. " has no buffer yet", vim.log.levels.WARN)
	end
	return open_float(buf, name == "console" and "terminal" or "panel", name, TAIL[name])
end

-- ------------------------------------------------------------- debug tab
local debug_tab

local function debug_tab_is_valid()
	return debug_tab ~= nil and vim.api.nvim_tabpage_is_valid(debug_tab)
end

--- Put the cursor on a panel of the debug tab instead of leaving it on the copy
--- of the code behind them. dapui.open() builds its windows in a nio task, so
--- the panel is not always there on the first look.
local function focus_panel(filetype, attempt)
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == filetype then
			vim.api.nvim_set_current_win(win)
			return
		end
	end
	attempt = (attempt or 0) + 1
	if attempt < 6 then
		vim.defer_fn(function()
			focus_panel(filetype, attempt)
		end, 40)
	end
end

--- Switch between the code tab and the debug tab (created on first use). The
--- cursor lands on the variables, which is what the tab is for.
function M.toggle_debug_tab()
	if debug_tab_is_valid() and vim.api.nvim_get_current_tabpage() == debug_tab then
		return vim.cmd("tabprevious")
	end
	if debug_tab_is_valid() then
		vim.api.nvim_set_current_tabpage(debug_tab)
	else
		vim.cmd("tab split")
		debug_tab = vim.api.nvim_get_current_tabpage()
		dapui.open()
	end
	focus_panel("dapui_scopes")
end

function M.close_debug_tab()
	if debug_tab_is_valid() then
		vim.api.nvim_set_current_tabpage(debug_tab)
		dapui.close()
		if #vim.api.nvim_list_tabpages() > 1 then
			vim.cmd("tabclose")
		end
	else
		dapui.close()
	end
	debug_tab = nil
end

-- ------------------------------------------------------ session terminal
local last_terminal_buf
local output_terminals = {}

--- Terminal of the active session (or the last one) in a full screen float.
function M.float_terminal()
	local session = dap.session()
	local buf = session and session.term_buf or last_terminal_buf
	if buf and vim.api.nvim_buf_is_valid(buf) then
		return M.float_buffer(
			buf,
			"Console: " .. (session and vim.trim(session.config.name) or "last session")
		)
	end
	if not pcall(M.float_element, "console") then
		notify("no session with a terminal")
	end
end

--- Pick the active session (a compound launch has one per app).
function M.pick_session()
	local sessions = vim.tbl_values(dap.sessions())
	if #sessions == 0 then
		return notify("no active session")
	end
	table.sort(sessions, function(a, b)
		return a.id < b.id
	end)
	vim.ui.select(sessions, {
		prompt = "Debug session: ",
		format_item = function(session)
			return vim.trim(session.config.name) .. (session.stopped_thread_id and "  (stopped)" or "")
		end,
	}, function(choice)
		if choice then
			dap.set_session(choice)
			notify("active session: " .. vim.trim(choice.config.name))
		end
	end)
end

--- Terminate every session (not just the active one).
function M.terminate_all()
	local sessions = dap.sessions()
	if vim.tbl_isempty(sessions) then
		return notify("no active session")
	end
	for _, session in pairs(sessions) do
		dap.set_session(session)
		dap.terminate()
	end
end

-- The dap-ui console panel has a single buffer. A second concurrent session
-- (compound API + Web) would fail with "jobstart requires unmodified buffer",
-- so sessions after the first get their own buffer.
local function setup_terminal_allocation()
	local dapui_console = dap.defaults.fallback.terminal_win_cmd
	local function has_running_job(buf)
		local job = vim.b[buf] and vim.b[buf].terminal_job_id
		return job and vim.fn.jobwait({ job }, 0)[1] == -1
	end
	dap.defaults.fallback.terminal_win_cmd = function(config)
		local buf = type(dapui_console) == "function" and dapui_console(config) or nil
		if
			buf
			and vim.api.nvim_buf_is_valid(buf)
			and not has_running_job(buf)
			and vim.bo[buf].buftype ~= "terminal"
		then
			return buf
		end
		return vim.api.nvim_create_buf(true, false)
	end
end

--- Adapters without an integrated terminal (netcoredbg) deliver program output
--- as "output" events. To render colors, attach a terminal emulator to a buffer
--- with no process (nvim_open_term) and feed the events to it. The dap-ui
--- console buffer is used when free, so the output shows up in the debug tab.
local function output_terminal(session)
	local terminal = output_terminals[session.id]
	if terminal and vim.api.nvim_buf_is_valid(terminal.buf) then
		return terminal
	end

	local buf
	local ok, console_buf = pcall(function()
		return dapui.elements.console.buffer()
	end)
	local console_is_free = ok
		and console_buf
		and vim.api.nvim_buf_is_valid(console_buf)
		and vim.bo[console_buf].buftype ~= "terminal"
		and vim.api.nvim_buf_line_count(console_buf) <= 1
		and (vim.api.nvim_buf_get_lines(console_buf, 0, 1, false)[1] or "") == ""
	if console_is_free then
		buf = console_buf
	else
		buf = vim.api.nvim_create_buf(true, true)
		pcall(
			vim.api.nvim_buf_set_name,
			buf,
			("[dap-terminal] %s #%d"):format(vim.trim(session.config.name), session.id)
		)
	end

	terminal = { buf = buf, channel = vim.api.nvim_open_term(buf, {}) }
	output_terminals[session.id] = terminal
	session.term_buf = buf
	last_terminal_buf = buf
	return terminal
end

local function wants_output_terminal(session, body)
	local category = body.category
	return session.config.type == "coreclr"
		and (category == nil or category == "stdout" or category == "stderr" or category == "console")
end

local function setup_output_routing()
	dap.listeners.before.event_output["ui.output"] = function(session, body)
		if not body or type(body.output) ~= "string" or body.category == "telemetry" then
			return
		end
		if wants_output_terminal(session, body) then
			local terminal = output_terminal(session)
			pcall(vim.api.nvim_chan_send, terminal.channel, (body.output:gsub("\r?\n", "\r\n")))
			body.output = "" -- already in the console; keep the REPL for expressions
			return
		end
		if body.output:find("\27", 1, true) then
			body.output = body.output:gsub("\27%[[%d;?]*[ -/]*[@-~]", "") -- the REPL cannot render ANSI colors
		end
	end
	dap.listeners.after.event_terminated["ui.output"] = function(session)
		local terminal = output_terminals[session.id]
		if terminal then
			pcall(vim.api.nvim_chan_send, terminal.channel, "\r\n[process exited]\r\n")
		end
	end
	dap.listeners.after.event_initialized["ui.last-terminal"] = function(session)
		vim.defer_fn(function()
			if session.term_buf then
				last_terminal_buf = session.term_buf
			end
		end, 1000)
	end
	dap.listeners.before.event_terminated["ui.last-terminal"] = function(session)
		if session.term_buf then
			last_terminal_buf = session.term_buf
		end
	end
end

-- ---------------------------------------------------------- notifications
-- js-debug spawns one child session per process; only the root session is
-- reported. nvim-dap clears `parent` before the termination event, so roots are
-- recorded on initialization.
local function setup_session_notifications()
	local started_at = {}
	local stopped_once = {}

	dap.listeners.after.event_initialized["ui.notify"] = function(session)
		if session.parent then
			return
		end
		started_at[session.id] = vim.uv.now()
		notify("session started. ,dd opens the debug tab.")
	end
	dap.listeners.after.event_stopped["ui.notify"] = function(session)
		stopped_once[session.id] = true
		if session.parent then
			stopped_once[session.parent.id] = true
		end
	end

	local function on_end(verb)
		return function(session, body)
			local start = started_at[session.id]
			if not start then
				return
			end
			started_at[session.id] = nil
			local seconds = (vim.uv.now() - start) / 1000
			local exit_code = body and body.exitCode
			local message = ('"%s" %s after %.1fs%s'):format(
				vim.trim(session.config.name or "?"),
				verb,
				seconds,
				exit_code and (" (exit code " .. exit_code .. ")") or ""
			)
			local suspicious = seconds < 5 and not stopped_once[session.id]
			stopped_once[session.id] = nil
			if suspicious then
				message = message
					.. ". It ended very quickly: check the console (,dt) or the REPL (,dR) for the error."
			end
			notify(message, suspicious and vim.log.levels.WARN or vim.log.levels.INFO)
		end
	end
	dap.listeners.after.event_exited["ui.notify"] = on_end("exited")
	dap.listeners.after.event_terminated["ui.notify"] = on_end("terminated")
end

-- Esc closes any dap-ui float; in the fixed debug tab panels it does nothing special.
local function setup_escape_to_close()
	vim.api.nvim_create_autocmd("FileType", {
		group = vim.api.nvim_create_augroup("DapFloatEscape", { clear = true }),
		pattern = FLOAT_FILETYPES,
		callback = function(args)
			vim.keymap.set("n", "<Esc>", function()
				if is_floating(0) then
					vim.api.nvim_win_close(0, true)
				end
			end, { buffer = args.buf, nowait = true })
		end,
	})
end

-- A float covers the code, so the line the program just stopped on would sit
-- behind it: a stop closes the quick looks and leaves the debug tab alone. A
-- terminal float is meant to be the whole screen, so it follows a resize.
local function setup_float_lifecycle()
	dap.listeners.before.event_stopped["ui.floats"] = function()
		close_floats()
	end
	vim.api.nvim_create_autocmd("VimResized", {
		group = vim.api.nvim_create_augroup("DapFloatResize", { clear = true }),
		callback = resize_floats,
	})
end

function M.setup()
	dapui.setup({
		icons = {
			expanded = icons.chevron_down,
			collapsed = icons.chevron_right,
			current_frame = icons.current_frame,
		},
		layouts = {
			{
				elements = {
					{ id = "scopes", size = 0.45 },
					{ id = "watches", size = 0.20 },
					{ id = "stacks", size = 0.20 },
					{ id = "breakpoints", size = 0.15 },
				},
				size = 50,
				position = "left",
			},
			{
				elements = { { id = "console", size = 0.6 }, { id = "repl", size = 0.4 } },
				size = 14,
				position = "bottom",
			},
		},
		floating = { border = "rounded" },
	})

	for name, definition in pairs(SIGNS) do
		vim.fn.sign_define(name, definition)
	end

	setup_terminal_allocation()
	setup_output_routing()
	setup_session_notifications()
	setup_escape_to_close()
	setup_float_lifecycle()
end

return M
