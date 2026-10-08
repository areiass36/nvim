local platform = require("core.platform")
local opt = vim.opt

vim.g.mapleader = ","

opt.clipboard = "unnamedplus"
opt.number = true
opt.relativenumber = true
opt.wrap = false
opt.showmode = false
opt.signcolumn = "yes"
-- Rounded border on every floating window (hover, signature help, diagnostics, dap-ui).
opt.winborder = "rounded"

if platform.is_windows then
	opt.shell = "powershell"
	opt.shellcmdflag = "-NoLogo -NoProfile -ExecutionPolicy RemoteSigned -Command"
	opt.shellquote = ""
	opt.shellxquote = ""
end

local icons = require("core.icons")
vim.diagnostic.config({
	virtual_text = false,
	float = { source = true, header = "", prefix = icons.diagnostic_info .. " " },
	signs = {
		text = {
			[vim.diagnostic.severity.ERROR] = icons.diagnostic_error,
			[vim.diagnostic.severity.WARN] = icons.diagnostic_warn,
			[vim.diagnostic.severity.HINT] = icons.diagnostic_hint,
			[vim.diagnostic.severity.INFO] = icons.diagnostic_info,
		},
	},
})
