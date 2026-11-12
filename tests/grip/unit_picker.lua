-- The picker itself: a real Telescope window, over the fixture snapshot.
--
-- The two suites beside this one check nodes in and strings out, which is where
-- the thinking is; this one checks the wiring -- that the window opens full
-- screen with a pane beside it, that the rows are the ones the list half
-- produced, that <CR> and <C-o> and <BS> move between levels and that the
-- titles follow. Telescope is driven through its own actions and keymaps rather
-- than around them, because a mapping that is never pressed is a mapping that
-- is never tested.
--
-- The defaults come from the editor's own spec, captured rather than copied: a
-- picker that fills the screen does so because lua/plugins/editor/telescope.lua
-- says every picker does, and a copy of that here would keep passing after the
-- real one changed.
local support = require("tests.grip.support")
local check, has = support.check, support.has

support.describe("the picker")

if not support.telescope() then
	support.note("skipped: telescope is not installed")
	return support
end

local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local icons = require("core.icons")
local preview = require("grip.preview")
local state_module = require("telescope.state")

-- A connection out of a file rather than a registered one: this suite walks all
-- the way back out to the connection list, which neogrip answers from the
-- configured files.
local shop = support.file_connection({ name = "Shop", database = "shop" })
support.sweep(shop, require("neogrip.schema").catalog_of(shop))
local origin = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(origin)
require("neogrip.resolve").bind(origin, shop.id)

preview.forget()
require("grip.explorer").open({ origin_buf = origin, origin_win = vim.api.nvim_get_current_win() })

local prompt = nil
support.wait(function()
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		if vim.bo[bufnr].filetype == "TelescopePrompt" then
			prompt = bufnr
			return true
		end
	end
	return false
end)

if not prompt then
	support.fail("the picker", "no picker opened")
	return support
end

local picker = action_state.get_current_picker(prompt)

--- Let the picker settle: a sort, a redraw and a pane are all one tick away.
local function settle()
	vim.wait(400, function()
		return false
	end, 10)
end

--- The rows on screen. Telescope pads its results buffer out to the height of
--- the window, so the blank lines go: a failure here should print three rows
--- and not three hundred.
local function rows()
	if not picker.results_bufnr or not vim.api.nvim_buf_is_valid(picker.results_bufnr) then
		return {}
	end
	local drawn = {}
	for _, line in ipairs(vim.api.nvim_buf_get_lines(picker.results_bufnr, 0, -1, false)) do
		if vim.trim(line) ~= "" then
			drawn[#drawn + 1] = line
		end
	end
	return drawn
end

local function pane()
	local status = state_module.get_status(prompt)
	local winid = status and status.layout and status.layout.preview and status.layout.preview.winid
	if not winid or not vim.api.nvim_win_is_valid(winid) then
		return {}, nil
	end
	local bufnr = vim.api.nvim_win_get_buf(winid)
	return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), winid
end

local function selection()
	local entry = action_state.get_selected_entry()
	return entry and entry.value or {}
end

--- Press a key in the prompt, the way a person would.
local function press(key, mode)
	vim.api.nvim_set_current_win(state_module.get_status(prompt).layout.prompt.winid)
	if mode == "n" then
		vim.cmd("stopinsert")
	else
		vim.cmd("startinsert")
	end
	vim.api.nvim_feedkeys(vim.keycode(key), "x", false)
	settle()
end

settle()

check("it opens on the database the buffer runs against", picker.prompt_title, "Schemas  Shop")
has("listing its schemas, with an icon each", rows(), ("%s public"):format(icons.schema))
has("and the way back out on top", rows(), ".. Connections")
check("with the cursor on a real row, not on the way out", selection().name, "public")

local _, preview_win = pane()
check("a pane is drawn beside the list", preview_win ~= nil, true)

local layout = state_module.get_status(prompt).layout
local width = vim.api.nvim_win_get_width(layout.results.winid) + vim.api.nvim_win_get_width(preview_win)
check("the two of them fill the width of the screen", width >= vim.o.columns - 6, true)
check("and the list fills its height", vim.api.nvim_win_get_height(layout.results.winid) >= vim.o.lines - 8, true)
has("the pane says what is in the schema", pane(), "2 tables, 1 view")

support.describe("walking in")

actions.select_default(prompt)
settle()
check("<CR> on a schema lists its tables", picker.prompt_title, "Tables  Shop/public")
has("with an icon and what is in them", rows(), ("%s customers"):format(icons.set))
has("a view saying so", rows(), ("%s active_customers"):format(icons.view))
has("and the way back to the schemas", rows(), ".. Schemas")
has("the pane holds the table's definition", pane(), 'CREATE TABLE "public"."customers" (')

for row = 1, picker.manager:num_results() do
	local entry = picker.manager:get_entry(row)
	if entry and entry.value and entry.value.name == "orders" then
		picker:set_selection(picker:get_row(row))
		break
	end
end
settle()
check("resting on another table draws that one", selection().name, "orders")
has("in the pane as well", pane(), 'CREATE TABLE "public"."orders" (')
has("foreign keys and all", pane(), 'REFERENCES "public"."customers" ("id")')

press("<C-o>", "i")
check("<C-o> on a table lists its columns", picker.prompt_title, "Columns  Shop/public.orders")
has("a key column drawn with a key", rows(), ("%s id"):format(icons.key))
has("and a plain one with columns", rows(), ("%s customer_id"):format(icons.column))
has("the pane describes the column itself", pane(), "type        bigint")

support.describe("walking back out")

press("<BS>", "n")
check("<BS> goes back to the tables", picker.prompt_title, "Tables  Shop/public")
press("<BS>", "n")
check("and again to the schemas", picker.prompt_title, "Schemas  Shop")
press("<BS>", "n")
check("and once more to every connection", picker.prompt_title, "Connections")
has("which lists this one", rows(), ("%s Shop"):format(icons.server))
has("with the driver and where it points", rows(), "postgres  db.example.test:5432")
press("<BS>", "n")
check("there is nothing above that", picker.prompt_title, "Connections")

pcall(actions.close, prompt)
settle()

return support
