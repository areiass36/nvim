-- Bootstrap lazy.nvim and load every spec under lua/plugins/*.
local lazy_path = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"

if not vim.uv.fs_stat(lazy_path) then
	vim.fn.system({
		"git",
		"clone",
		"--filter=blob:none",
		"https://github.com/folke/lazy.nvim.git",
		"--branch=stable",
		lazy_path,
	})
end
vim.opt.rtp:prepend(lazy_path)

require("lazy").setup({
	spec = {
		{ import = "plugins.ui" },
		{ import = "plugins.editor" },
		{ import = "plugins.lsp" },
		{ import = "plugins.dap" },
	},
	-- luarocks would need Lua 5.1 and a compiler; no plugin here uses it.
	rocks = { enabled = false },
})
