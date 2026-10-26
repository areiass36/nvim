-- Windows: DPAPI through PowerShell. The encrypted blob is bound to the current
-- user account, so a file copied to another machine is useless.
--
-- The script is passed as base64 UTF-16LE (-EncodedCommand) and the secret goes
-- in on stdin, so neither ever appears in a command line. Building a -Command
-- string by hand would also break on quotes, which passwords are full of.
local db = require("db")

local M = {}

local function blob_dir()
	local dir = db.state_dir .. "/dpapi"
	vim.fn.mkdir(dir, "p")
	return dir
end

local function blob_path(account)
	return ("%s/%s.bin"):format(blob_dir(), vim.fn.sha256(account))
end

local function encode_command(script)
	-- PowerShell wants UTF-16LE: pad each byte of this ASCII script with a zero.
	local utf16 = script:gsub(".", function(char)
		return char .. "\0"
	end)
	return vim.base64.encode(utf16)
end

local function powershell(script, stdin, callback)
	vim.system(
		{ "powershell", "-NoProfile", "-NonInteractive", "-EncodedCommand", encode_command(script) },
		{ stdin = stdin, text = true },
		vim.schedule_wrap(callback)
	)
end

function M.available()
	return vim.fn.executable("powershell") == 1
end

function M.get(account, callback)
	local path = blob_path(account)
	if vim.fn.filereadable(path) == 0 then
		return callback(nil, nil)
	end
	local script = ([[
$ErrorActionPreference = 'Stop'
$secure = Get-Content -Raw -LiteralPath '%s' | ConvertTo-SecureString
$pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
[Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
]]):format(path)
	powershell(script, nil, function(result)
		if result.code ~= 0 then
			return callback(nil, (result.stderr or "DPAPI read failed"):gsub("[\r\n]+$", ""))
		end
		callback((result.stdout or ""):gsub("[\r\n]+$", ""), nil)
	end)
end

function M.set(account, secret, callback)
	local script = ([[
$ErrorActionPreference = 'Stop'
$plain = [Console]::In.ReadToEnd().TrimEnd("`r","`n")
$secure = ConvertTo-SecureString -String $plain -AsPlainText -Force
ConvertFrom-SecureString -SecureString $secure | Set-Content -NoNewline -LiteralPath '%s'
]]):format(blob_path(account))
	powershell(script, secret .. "\n", function(result)
		callback(result.code == 0, result.code ~= 0 and (result.stderr or "DPAPI write failed") or nil)
	end)
end

function M.delete(account, callback)
	pcall(vim.fn.delete, blob_path(account))
	callback(true, nil)
end

return M
