-- Windows: DPAPI through PowerShell. The encrypted blob is bound to the current
-- user account, so a file copied to another machine is useless.
--
-- The script is passed as base64 UTF-16LE (-EncodedCommand) and the secret goes
-- in on stdin, so neither ever appears in a command line. Building a -Command
-- string by hand would also break on quotes, which passwords are full of.
local db = require("db")

local M = {}

--- Which PowerShell to run, newest first.
---
--- pwsh is preferred for a reason beyond being newer. The DPAPI cmdlets live in
--- Microsoft.PowerShell.Security, and Windows PowerShell 5.1 cannot always load
--- its own copy of that module: one duplicated member in the extended type data
--- is enough for the autoloader to give up, and then ConvertTo-SecureString
--- simply does not exist -- it reports "CouldNotAutoloadMatchingModule" and
--- storing a password fails with nothing that points at the cause. PowerShell 7
--- ships the same cmdlets in a module of its own, so preferring it steps around
--- a broken 5.1 rather than asking anyone to repair one.
local function shell()
	for _, candidate in ipairs({ "pwsh", "powershell" }) do
		if vim.fn.executable(candidate) == 1 then
			return candidate
		end
	end
	return nil
end

local function blob_dir()
	local dir = db.state_dir .. "/dpapi"
	vim.fn.mkdir(dir, "p")
	return dir
end

local function blob_path(account)
	return ("%s/%s.bin"):format(blob_dir(), vim.fn.sha256(account))
end

local function encode_command(script)
	-- PowerShell wants UTF-16LE. iconv rather than padding every byte with a
	-- zero, which is only UTF-16 for ASCII and would mangle the script the
	-- moment a path carried an accent -- a user whose name has one would find
	-- their passwords unstorable for a reason nothing would explain.
	local utf16 = vim.iconv(script, "utf-8", "utf-16le")
	if not utf16 then
		utf16 = script:gsub(".", function(char)
			return char .. "\0"
		end)
	end
	return vim.base64.encode(utf16)
end

--- PowerShell writes its errors as a CLIXML document whenever its output is
--- redirected, which is what reached the user before: a notification full of
--- `#< CLIXML` and escaped newlines, with the actual sentence buried in it.
local function readable(stderr, fallback)
	local text = stderr or ""
	if text:find("#< CLIXML", 1, true) then
		local parts = {}
		for chunk in text:gmatch('<S S="Error">(.-)</S>') do
			parts[#parts + 1] = chunk
		end
		text = table.concat(parts, " ")
	end
	-- The escapes CLIXML uses for the characters it cannot carry literally.
	text = text:gsub("_x000D_", " "):gsub("_x000A_", " "):gsub("_x%x%x%x%x_", " ")
	text = vim.trim((text:gsub("%s+", " ")))
	if text == "" then
		return fallback
	end
	if text:find("CouldNotAutoloadMatchingModule", 1, true) or text:find("ConvertTo%-SecureString") then
		-- The one failure worth naming, because the fix is an install and not
		-- anything about the password that was being stored.
		text = text .. " -- this PowerShell cannot load Microsoft.PowerShell.Security; installing"
			.. " PowerShell 7 (pwsh) gives the database client a working one."
	end
	return text
end

local function powershell(script, stdin, callback)
	local program = shell()
	if not program then
		return callback({ code = 1, stderr = "no PowerShell found to reach DPAPI with" })
	end
	vim.system(
		{ program, "-NoProfile", "-NonInteractive", "-EncodedCommand", encode_command(script) },
		{ stdin = stdin, text = true },
		vim.schedule_wrap(callback)
	)
end

function M.available()
	return shell() ~= nil
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
			return callback(nil, readable(result.stderr, "DPAPI read failed"))
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
		local failed = result.code ~= 0
		callback(not failed, failed and readable(result.stderr, "DPAPI write failed") or nil)
	end)
end

function M.delete(account, callback)
	pcall(vim.fn.delete, blob_path(account))
	callback(true, nil)
end

return M
