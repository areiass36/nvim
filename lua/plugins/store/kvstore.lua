local get_npm_path = function()
	local handle = io.popen("npm root -g");
	if handle == nil then
		return nil
	end
	local result = handle:read("*a");
	return vim.fn.expand(result:gsub("\n", ""));
end

local get_os = function()
	local os = {
		["Windows_NT"] = Consts.os.windows,
		["Darwin"] = Consts.os.mac,
		["Linux"] = Consts.os.linux
	}
	return os[vim.loop.os_uname().sysname]
end


return {
	'areiass36/kvstore.nvim',
	name = 'kvstore',
	config = function()
		local kvstore = require('kvstore')

		kvstore.get_or_set(Keys.path.npm, get_npm_path)
		kvstore.get_or_set(Keys.os, get_os)
	end
}
