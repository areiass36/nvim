local os = vim.loop.os_uname().sysname;
local windowsPath = 'C:/Users/AugustoBarreto/omnisharp-win-x64/OmniSharp.exe'
local macosPath = '/Users/areiass36/.local/share/nvim/mason/packages/omnisharp/libexec/OmniSharp.dll'
return os == "Darwin" and macosPath or windowsPath
