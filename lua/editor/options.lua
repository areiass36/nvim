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

vim.api.nvim_create_autocmd("InsertLeave", {
	callback = function()
		vim.lsp.buf.format { async = false }
	end
})


vim.diagnostic.config {
	virtual_text = false
}

-- Install Lazy
if not vim.loop.fs_stat(Consts.lazy) then
	vim.fn.system({
		"git",
		"clone",
		"--filter=blob:none",
		"https://github.com/folke/lazy.nvim.git",
		"--branch=stable",
		Consts.lazy,
	})
end
vim.opt.rtp:prepend(Consts.lazy)

local lazy = require("lazy");
lazy.setup({
	spec = {
		{ import = 'plugins.interface' },
		{ import = 'plugins.terminal' },
		{ import = 'plugins.search' },
		{ import = 'plugins.server' },
		{ import = 'plugins.store' },
	},
});

-- Applying keys
Keys_editor();
Keys_terminal();
Keys_search();
Keys_server();

-- After pack load config
local kvstore = require('kvstore')
local os = kvstore.get(Keys.os)

if os == Consts.os.windows then
	vim.opt.shell = "powershell"
	vim.opt.shellcmdflag = "-NoLogo -NoProfile -ExecutionPolicy RemoteSigned -Command"
	vim.opt.shellquote = ""
	vim.opt.shellxquote = ""
end
