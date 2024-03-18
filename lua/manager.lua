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
				"nvim-neo-tree/neo-tree.nvim",
				lazy = true,
				dependencies = { 
						"nvim-lua/plenary.nvim",
						-- :"nvim-tree/nvim-web-devicons", -- not strictly required, but recommended
						"MunifTanjim/nui.nvim",
				}
		}

local theme = {
		'Mofiqul/vscode.nvim',
		name = 'vscode',
		config = function()
				vim.cmd('colorscheme vscode')
		end
}

local treeSitter = {
		'nvim-treesitter/nvim-treesitter',
		build = ":TSUpdate",
		config = function () 
						local configs = require("nvim-treesitter.configs")

				configs.setup({
						ensure_installed = { "c", "lua", "vim", "vimdoc", "query", "elixir", "heex", "javascript", "html", "c_sharp" },
						sync_install = false,
						highlight = { enable = true },
						indent = { enable = true },  
				})
				end
}  

local plugins = { fileExplorer, theme, treeSitter,
{'VonHeikemen/lsp-zero.nvim', branch = 'v3.x'},
{'neovim/nvim-lspconfig'},
{'hrsh7th/cmp-nvim-lsp'},
{'hrsh7th/nvim-cmp'},
{'L3MON4D3/LuaSnip'},
}

require("lazy").setup(plugins)


local lsp_zero = require('lsp-zero')

lsp_zero.on_attach(function(client, bufnr)
  -- see :help lsp-zero-keybindings
  -- to learn the available actions
  lsp_zero.default_keymaps({buffer = bufnr})
end)

require('lspconfig').csharp_ls.setup({})

