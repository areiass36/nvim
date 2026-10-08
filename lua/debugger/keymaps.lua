local dap = require("dap")
local dapui = require("dapui")
local ui = require("debugger.ui")

local M = {}

function M.setup()
	local map = function(mode, lhs, rhs, desc)
		vim.keymap.set(mode, lhs, rhs, { noremap = true, silent = true, desc = desc })
	end

	-- Flow (F-keys and leader alternatives, since macOS reserves some F-keys)
	map("n", "<F5>", dap.continue, "Debug: continue")
	map("n", "<F10>", dap.step_over, "Debug: step over")
	map("n", "<F11>", dap.step_into, "Debug: step into")
	map("n", "<F12>", dap.step_out, "Debug: step out")
	map("n", "<leader>dc", dap.continue, "Debug: continue")
	map("n", "<leader>do", dap.step_over, "Debug: step over")
	map("n", "<leader>di", dap.step_into, "Debug: step into")
	map("n", "<leader>dO", dap.step_out, "Debug: step out")
	map("n", "<leader>dl", dap.run_last, "Debug: run last configuration")
	map("n", "<leader>dx", ui.terminate_all, "Debug: terminate every session")

	-- Breakpoints
	map("n", "<leader>b", dap.toggle_breakpoint, "Debug: toggle breakpoint")
	map("n", "<leader>B", function()
		dap.set_breakpoint(vim.fn.input("Breakpoint condition: "))
	end, "Debug: conditional breakpoint")

	-- Views
	map("n", "<leader>dd", ui.toggle_debug_tab, "Debug: toggle debug tab")
	map("n", "<leader>du", ui.close_debug_tab, "Debug: close debug tab")
	map("n", "<leader>dt", ui.float_terminal, "Debug: program output (full screen)")
	map("n", "<leader>dR", function()
		ui.float_element("repl")
	end, "Debug: REPL (full screen)")
	map("n", "<leader>ds", function()
		ui.float_element("scopes")
	end, "Debug: scopes (full screen)")
	map("n", "<leader>dk", function()
		ui.float_element("stacks")
	end, "Debug: stack (full screen)")
	map("n", "<leader>dr", dap.repl.toggle, "Debug: REPL")
	map("n", "<leader>dS", ui.pick_session, "Debug: pick active session")
	map({ "n", "v" }, "<leader>de", dapui.eval, "Debug: evaluate expression")
end

return M
