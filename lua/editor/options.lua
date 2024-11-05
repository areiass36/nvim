require("editor.global")
require("editor.keys");
require("plugins.keys");
-- Standard config
vim.opt.clipboard = "unnamedplus";
vim.opt.number = true;
vim.opt.relativenumber = true;
vim.opt.wrap = false;
vim.opt.showmode = false;
vim.g.mapleader = ","

if vim.fn.has("win32") then
	vim.opt.shell = "powershell"
	vim.opt.shellcmdflag = "-NoLogo -NoProfile -ExecutionPolicy RemoteSigned -Command"
	vim.opt.shellquote = ""
	vim.opt.shellxquote = ""
end
vim.api.nvim_create_autocmd("InsertLeave", {
	callback = function()
		vim.lsp.buf.format { async = false }
	end
})


vim.diagnostic.config {
	virtual_text = false
}

-- Install Lazy
if not vim.loop.fs_stat(Path.lazy) then
	vim.fn.system({
		"git",
		"clone",
		"--filter=blob:none",
		"https://github.com/folke/lazy.nvim.git",
		"--branch=stable",
		Path.lazy,
	})
end
vim.opt.rtp:prepend(Path.lazy)

local lazy = require("lazy");
lazy.setup({
	spec = {
		{ import = 'plugins.interface' },
		{ import = 'plugins.terminal' },
		{ import = 'plugins.search' },
		{ import = 'plugins.browser' },
		{ import = 'plugins.server' },
	},
});

-- Applying keys
Keys_editor();
Keys_terminal();
Keys_search();
Keys_browser();
Keys_server();
