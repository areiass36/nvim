-- One file per language server. Each calls vim.lsp.config(name, {...}).
require("servers.lua_ls")
require("servers.ts_ls")
require("servers.vue_ls")
require("servers.angularls")
require("servers.cssls")
require("servers.pyright")
require("servers.roslyn")
