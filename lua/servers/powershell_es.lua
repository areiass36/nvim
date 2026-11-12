-- PowerShell through PowerShellEditorServices. Mason unpacks the release zip
-- into the package directory, and lspconfig builds the whole shell command
-- line from bundle_path, so the directory is almost all there is to configure.
--
-- The server is a set of PowerShell modules, not an executable: it runs inside
-- a shell. lspconfig uses `pwsh` (PowerShell 7), which is an install of its
-- own on Windows -- the 5.1 that ships with the system is `powershell.exe`,
-- and the server supports it too, so it is the fallback.
--
-- Both are started with -NoProfile, so a profile that prints (this one warns
-- when mise is missing) cannot corrupt the LSP handshake.
local platform = require("core.platform")
local tools = require("tools")

local shell = "pwsh"
if vim.fn.executable(shell) == 0 and platform.is_windows then
	shell = "powershell.exe"
end

vim.lsp.config("powershell_es", {
	bundle_path = tools.mason_package("powershell-editor-services"),
	shell = shell,
})
