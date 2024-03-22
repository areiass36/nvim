local options = {
	clipboard = "unnamedplus",
	number = true,
	relativenumber = true,
	tabstop = 4, -- set tab size
	--wildmenu = true,
	--wildmode = "list:longest",
}

for k, v in pairs(options) do
	vim.opt[k] = v
end

