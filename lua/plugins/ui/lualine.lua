local icons = require("core.icons")

return {
	"nvim-lualine/lualine.nvim",
	dependencies = { "nvim-tree/nvim-web-devicons" },
	opts = {
		options = {
			theme = "vscode",
			component_separators = { left = "\u{e0b1}", right = "\u{e0b3}" },
			section_separators = { left = "\u{e0b0}", right = "\u{e0b2}" },
			globalstatus = true,
		},
		sections = {
			lualine_a = { "mode" },
			lualine_b = { { "branch", icon = icons.branch }, "diff" },
			lualine_c = {
				{
					"filename",
					path = 1,
					symbols = { modified = " " .. icons.modified, readonly = " " .. icons.readonly },
				},
			},
			lualine_x = {
				{
					"diagnostics",
					symbols = {
						error = icons.diagnostic_error .. " ",
						warn = icons.diagnostic_warn .. " ",
						info = icons.diagnostic_info .. " ",
						hint = icons.diagnostic_hint .. " ",
					},
				},
			},
			lualine_y = {},
			lualine_z = { "location" },
		},
		inactive_sections = {
			lualine_c = { { "filename", path = 1 } },
			lualine_x = {},
		},
	},
}
