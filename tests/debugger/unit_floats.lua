-- The windows of the debugger: the shape of each float, who holds the focus, and
-- what a cursor move, a resize and a stop do to them. The cursor move is here
-- because dapui.float_element closes an unfocused float on the next one, which
-- is why lua/debugger/ui.lua opens its own windows.
local support = require("tests.debugger.support")

local check = support.check
local ui = require("debugger.ui")

ui.setup()

local function config_of(win)
	return vim.api.nvim_win_get_config(win)
end

support.describe("inspection panels")

ui.float_element("scopes")
local panel = vim.api.nvim_get_current_win()
local panel_config = config_of(panel)

check("opens floating", panel_config.relative, "editor")
check("holds the focus", vim.bo[vim.api.nvim_win_get_buf(panel)].filetype, "dapui_scopes")
check("as wide as the other floats of this config", {
	panel_config.width,
	panel_config.height,
}, { vim.o.columns - 4, vim.o.lines - 6 })
check("rounded", panel_config.border[1], "╭")

local windows_before = #vim.api.nvim_list_wins()
ui.float_element("scopes")
check("a second call reuses the window", #vim.api.nvim_list_wins(), windows_before)

vim.api.nvim_exec_autocmds("CursorMoved", {})
check("a cursor move does not close it", vim.api.nvim_win_is_valid(panel), true)

vim.api.nvim_set_current_win(panel)
vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "x", false)
check("Esc closes it", vim.api.nvim_win_is_valid(panel), false)

support.describe("program output")

local buf = vim.api.nvim_create_buf(true, true)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "line 1", "line 2" })
local terminal = ui.float_buffer(buf, "Console: test")
local terminal_config = config_of(terminal)

check("holds the focus", vim.api.nvim_get_current_win(), terminal)
check("full screen, like the terminal of this config", {
	terminal_config.width,
	terminal_config.height,
}, { vim.o.columns, vim.o.lines - 2 })
check("at the top left corner", { terminal_config.row, terminal_config.col }, { 0, 0 })
check("without a border", terminal_config.border, "none")
check("scrolled to the end of the output", vim.api.nvim_win_get_cursor(terminal)[1], 2)

vim.o.columns = 120
vim.api.nvim_exec_autocmds("VimResized", {})
check("a resize keeps it full screen", config_of(terminal).width, 120)

require("dap").listeners.before.event_stopped["ui.floats"]()
check("a stop takes it off the screen", vim.api.nvim_win_is_valid(terminal), false)
