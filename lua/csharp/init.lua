-- C# extras on top of the Roslyn server:
--   * gd that lands in real, decompiled source for .NET/ASP.NET types
--   * read-only, diagnostics-free buffers for that decompiled source
--   * 4-space indentation (Roslyn formats with the buffer's tabstop)
local M = {}

function M.setup()
	local group = vim.api.nvim_create_augroup("Csharp", { clear = true })

	vim.api.nvim_create_autocmd("LspAttach", {
		group = group,
		callback = function(args)
			local client = vim.lsp.get_client_by_id(args.data.client_id)
			if client and client.name == "roslyn_ls" then
				vim.keymap.set(
					"n",
					"gd",
					require("csharp.goto_definition").run,
					{ buffer = args.buf, silent = true }
				)
			end
		end,
	})

	vim.api.nvim_create_autocmd("BufReadPost", {
		group = group,
		pattern = "*.cs",
		callback = function(args)
			require("csharp.decompiled_sources").on_buffer_read(args.buf)
		end,
	})

	-- Roslyn formats with the buffer's tabstop; Neovim's default (8) would reindent
	-- every file. A project .editorconfig still takes precedence.
	vim.api.nvim_create_autocmd("FileType", {
		group = group,
		pattern = "cs",
		callback = function(args)
			vim.bo[args.buf].shiftwidth = 4
			vim.bo[args.buf].tabstop = 4
			vim.bo[args.buf].softtabstop = 4
			vim.bo[args.buf].expandtab = true
		end,
	})
end

return M
