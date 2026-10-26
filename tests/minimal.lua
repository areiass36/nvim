-- Minimal init for the headless tests: this config's own lua/ and tests/ on the
-- runtimepath, and nothing else. No plugin manager, so the tests exercise the
-- modules rather than lazy.nvim's loading of them.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path
vim.g.db_config = { timeout_ms = 20000 }
