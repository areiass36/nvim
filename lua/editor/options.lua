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
	virtual_text = {
		prefix = ''
	}
}

-- Install Lazy
if not vim.loop.fs_stat(path.lazy) then
	vim.fn.system({
		"git",
		"clone",
		"--filter=blob:none",
		"https://github.com/folke/lazy.nvim.git",
		"--branch=stable",
		path.lazy,
	})
end
vim.opt.rtp:prepend(path.lazy)

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
