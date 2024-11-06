Path = {
	lazy = vim.fn.stdpath("data") .. "/lazy/lazy.nvim",
	npm = (function()
		local handle = io.popen("npm root -g");
		if handle == nil then
			return nil
		end
		local result = handle:read("*a");
		return vim.fn.expand(result:gsub("\n", ""));
	end)()
}
