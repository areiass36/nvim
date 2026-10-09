-- :Doctor shows the state of everything the config installs by itself. Useful
-- on a new machine (especially Windows) to see what is missing at a glance.
local platform = require("core.platform")
local tools = require("tools")
local dotnet = require("tools.dotnet")
local netcoredbg = require("tools.netcoredbg")
local icons = require("core.icons")
local nerd_font = require("tools.nerd_font")
local icon_font = require("tools.icon_font")
local zig = require("tools.zig")
local windows_terminal = require("tools.windows_terminal")

local MASON_PACKAGES = {
	"typescript-language-server",
	"vue-language-server",
	"lua-language-server",
	"angular-language-server",
	"json-lsp",
	"pyright",
	"css-lsp",
	"debugpy",
	"js-debug-adapter",
	"tree-sitter-cli",
}

local function executable(name)
	return vim.fn.executable(name) == 1, vim.fn.exepath(name)
end

local function build_report()
	local lines = {}
	local function section(title)
		lines[#lines + 1] = ""
		lines[#lines + 1] = title
	end
	local function row(ok, label, detail)
		lines[#lines + 1] = ("%s  %-28s %s"):format(
			ok and (icons.check .. " ") or (icons.cross .. " "),
			label,
			detail or ""
		)
	end

	local uname = vim.uv.os_uname()
	row(true, "system", ("%s %s (%s)"):format(uname.sysname, uname.release, uname.machine))
	row(true, "neovim", tostring(vim.version()))

	section("Prerequisites")
	for _, name in ipairs({ "git", "curl", "tar" }) do
		local ok, path = executable(name)
		row(ok, name, ok and path or "MISSING (required)")
	end
	for _, name in ipairs({ "node", "npm", "dotnet", "python3" }) do
		local ok, path = executable(name)
		row(ok, name, ok and path or "missing (only needed for that language)")
	end
	local has_compiler = platform.has_c_compiler()
	local zig_used = vim.fn.executable(zig.path) == 1 and (vim.env.CC or ""):find("zig", 1, true) ~= nil
	row(
		has_compiler,
		"C compiler",
		has_compiler and (zig_used and "zig (downloaded by the config)" or "ok")
			or "missing: downloading zig on startup"
	)

	section("Fonts and terminal")
	row(
		nerd_font.is_installed(),
		"JetBrainsMono Nerd Font Mono",
		nerd_font.is_installed() and "installed" or "downloading on startup"
	)
	local icon_font_ok = vim.fn.filereadable(icon_font.target) == 1
	row(icon_font_ok, "ConfigIcons.ttf", icon_font_ok and icon_font.target or "not installed")
	if platform.is_windows then
		local settings = windows_terminal.settings_path()
		row(settings ~= nil, "Windows Terminal settings", settings or "not found")
	elseif platform.detect() == "mac" then
		local profile = vim.env.ITERM_PROFILE
		row(
			profile == "ConfigIcons",
			"iTerm2 profile",
			profile and ("current: " .. profile) or "not running in iTerm2"
		)
	end

	section("Downloaded by the config")
	local ok, path = executable("rg")
	row(ok, "ripgrep", ok and path or "not yet (downloads on startup)")
	ok, path = executable(netcoredbg.path)
	row(ok, "netcoredbg (.NET debugger)", ok and path or netcoredbg.path .. " (not yet)")
	local roslyn = dotnet.roslyn()
	row(roslyn ~= nil, "roslyn (C# LSP)", roslyn or "installs when a .cs file is opened")
	local ilspy = dotnet.ilspy()
	row(ilspy ~= nil, "ilspycmd (.NET decompiler)", ilspy or "installs on the first gd into a .NET type")
	local decompiled = vim.fn.glob(tools.tools_dir .. "/ilspy-src/*/*/*/.ilspy-done", true, true)
	row(true, "decompiled assemblies", #decompiled .. " cached")
	ok, path = executable("tree-sitter")
	row(ok, "tree-sitter-cli (Mason)", ok and path or "not yet")

	section("Mason")
	local registry_ok, registry = pcall(require, "mason-registry")
	if registry_ok then
		for _, name in ipairs(MASON_PACKAGES) do
			local package_ok, package = pcall(registry.get_package, name)
			local installed = package_ok and package:is_installed()
			row(installed, name, package_ok and (installed and "installed" or "missing") or "unknown")
		end
	end

	section("Treesitter")
	local treesitter_ok, treesitter = pcall(require, "nvim-treesitter")
	row(
		treesitter_ok,
		"parsers",
		treesitter_ok and (#treesitter.get_installed() .. " installed") or "plugin not loaded"
	)

	section("LSP in this buffer")
	local clients = vim.lsp.get_clients({ bufnr = 0 })
	local names = vim.tbl_map(function(client)
		return client.name
	end, clients)
	row(#clients > 0, "clients", #clients > 0 and table.concat(names, ", ") or "none")

	return lines
end

local function show(lines)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modifiable = false
	vim.bo[buf].bufhidden = "wipe"

	local width = math.min(100, vim.o.columns - 4)
	vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		row = 1,
		col = math.floor((vim.o.columns - width) / 2),
		width = width,
		height = math.min(#lines + 2, vim.o.lines - 4),
		border = "rounded",
		title = " :Doctor ",
		title_pos = "center",
		style = "minimal",
	})
	vim.keymap.set("n", "q", "<cmd>close<CR>", { buffer = buf, nowait = true })
	vim.keymap.set("n", "<Esc>", "<cmd>close<CR>", { buffer = buf, nowait = true })
end

vim.api.nvim_create_user_command("Doctor", function()
	show(build_report())
end, { desc = "Show the state of the tools installed by this config" })
