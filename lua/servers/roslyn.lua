-- C# through Microsoft's Roslyn language server (the one VS Code uses). It is
-- installed as a dotnet tool by tools/dotnet.lua. Navigation into .NET types
-- is handled by lua/csharp (see csharp/init.lua).
local dotnet = require("tools.dotnet")
local decompiled = require("csharp.decompiled_sources")

local log_dir = vim.fn.stdpath("log") .. "/roslyn"
vim.fn.mkdir(log_dir, "p") -- Roslyn does not create it

local function root_dir(bufnr, on_dir)
	-- Decompiled sources reuse the Roslyn client of the open project.
	if decompiled.owns(vim.api.nvim_buf_get_name(bufnr)) then
		local client = vim.lsp.get_clients({ name = "roslyn_ls" })[1]
		local root = client and client.config.root_dir or decompiled.project_root(bufnr)
		return on_dir(root)
	end
	local root = vim.fs.root(bufnr, function(name)
		return name:match("%.slnx?$") ~= nil
	end) or vim.fs.root(bufnr, function(name)
		return name:match("%.csproj$") ~= nil
	end)
	if root then
		on_dir(root)
	end
end

vim.lsp.config("roslyn_ls", {
	cmd = { dotnet.roslyn, "--logLevel", "Warning", "--extensionLogDirectory", log_dir, "--stdio" },
	-- Roslyn registers its capabilities for language "csharp". Sending the
	-- filetype ("cs") as languageId makes the selector miss and gd/gr fail.
	get_language_id = function()
		return "csharp"
	end,
	root_dir = root_dir,
	capabilities = {
		-- Neovim's file watcher logs "watch.watch: ENOENT" with Roslyn's patterns; Roslyn has its own.
		workspace = { didChangeWatchedFiles = { dynamicRegistration = false } },
	},
	settings = {
		-- Sections without a language prefix: Roslyn asks for "navigation.dotnet_...".
		navigation = {
			dotnet_navigate_to_decompiled_sources = true,
			dotnet_navigate_to_source_link_and_embedded_sources = true,
		},
		projects = { dotnet_enable_automatic_restore = true },
		["csharp|symbol_search"] = { dotnet_search_reference_assemblies = true },
		["csharp|background_analysis"] = {
			-- Much lighter than "fullSolution" on large solutions.
			dotnet_analyzer_diagnostics_scope = "openFiles",
			dotnet_compiler_diagnostics_scope = "openFiles",
		},
		["csharp|completion"] = {
			dotnet_show_completion_items_from_unimported_namespaces = true,
			dotnet_show_name_completion_suggestions = true,
		},
		["csharp|code_lens"] = { dotnet_enable_references_code_lens = false },
	},
})

-- Enable as soon as the binary exists (it is installed on first use), then
-- attach to .cs buffers opened before that.
dotnet.ensure_roslyn(function(ok)
	if not ok then
		return
	end
	vim.lsp.enable("roslyn_ls")
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].filetype == "cs" then
			vim.api.nvim_exec_autocmds("FileType", { buffer = buf, modeline = false })
		end
	end
end)

require("csharp").setup()
