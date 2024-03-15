-- Install plugin manager
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable", -- latest stable release
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

local fileExplorer = {
				-- File explorer plugin
				"nvim-neo-tree/neo-tree.nvim",
				lazy = true,
				dependencies = { 
						"nvim-lua/plenary.nvim",
						-- :"nvim-tree/nvim-web-devicons", -- not strictly required, but recommended
						"MunifTanjim/nui.nvim",
				}
		}

-- Load plugins
local plugins = { fileExplorer, { 'kepano/flexoki-neovim', name = 'flexoki' } }


require("lazy").setup({
		 'kepano/flexoki-neovim', name = 'flexoki' 
}, { install = { missing = false }})

vim.cmd('colorscheme flexoki-dark')


