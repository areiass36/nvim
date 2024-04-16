local os = vim.loop.os_uname().sysname;
local windowsNodePath = "C:\\Program Files\\nodejs\\node_modules"
local macNodePath = "/Users/areiass36/.asdf/installs/nodejs/20.11.1/lib/node_modules"
return os == "Darwin" and macNodePath or windowsNodePath
