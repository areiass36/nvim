return {
	'nvim-tree/nvim-web-devicons',
	config = function()
		--[[
		local file_icon = ""
		local folder_icon = ""
		local icon_color = "#6d8086"

		local devicons = require('nvim-web-devicons');
		devicons.setup({
			override = {

			},
			defualt = true
		});
		for name, icon_data in pairs(devicons.get_icons()) do
			devicons.set_icon({
				[name] = {
					icon = file_icon,
					name = icon_data.name
				}
			})
		end
		devicons.set_icon {
			Folder = { icon = folder_icon, color = icon_color, name = "Folder" },
			FolderOpen = { icon = folder_icon, color = icon_color, name = "FolderOpen" },
			FolderEmpty = { icon = folder_icon, color = icon_color, name = "FolderEmpty" },
		}
		]] --
	end
}
