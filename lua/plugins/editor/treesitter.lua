local PARSERS = {
	"c",
	"lua",
	"vim",
	"vimdoc",
	"query",
	"javascript",
	"typescript",
	"tsx",
	"vue",
	"html",
	"css",
	"json",
	"c_sharp",
	"python",
	"elixir",
	"heex",
}

return {
	"nvim-treesitter/nvim-treesitter",
	branch = "main",
	lazy = false,
	build = ":TSUpdate",
	dependencies = { "mason-org/mason.nvim" }, -- puts Mason's tree-sitter-cli on PATH first
	config = function()
		local platform = require("core.platform")
		local treesitter = require("nvim-treesitter")

		-- Highlighting and indentation are built into Neovim; enable them per
		-- buffer only when a parser exists for the filetype.
		vim.api.nvim_create_autocmd("FileType", {
			group = vim.api.nvim_create_augroup("TreesitterStart", { clear = true }),
			callback = function(args)
				if pcall(vim.treesitter.start, args.buf) then
					vim.bo[args.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
				end
			end,
		})

		local function install_parsers()
			-- Without a compiler tools/zig.lua downloads one and fires ZigReady.
			if not platform.has_c_compiler() or vim.fn.executable("tree-sitter") == 0 then
				return
			end
			treesitter.install(PARSERS)
		end

		install_parsers()
		vim.api.nvim_create_autocmd(
			"User",
			{ pattern = { "ToolsReady", "ZigReady" }, callback = install_parsers }
		)
	end,
}
