-- Every file gets the same generic icon, everywhere nvim-web-devicons is used
-- (Telescope pickers, LSP references/definitions lists, file browser, Harpoon).
return {
	"nvim-tree/nvim-web-devicons",
	config = function()
		local icons = require("core.icons")
		local devicons = require("nvim-web-devicons")
		local HIGHLIGHT = "DevIconDefault"
		local COLOR = "#8b949e"

		devicons.setup({
			default = true,
			default_icon = { icon = icons.file, color = COLOR, name = "Default" },
		})
		vim.api.nvim_set_hl(0, HIGHLIGHT, { fg = COLOR })

		local function generic_icon()
			return icons.file, HIGHLIGHT
		end
		devicons.get_icon = generic_icon
		devicons.get_icon_by_filetype = generic_icon
		devicons.get_icon_color = function()
			return icons.file, COLOR
		end
		devicons.get_icon_color_by_filetype = devicons.get_icon_color
		devicons.get_icon_cterm_color = function()
			return icons.file, 245
		end
		devicons.get_icon_colors = function()
			return icons.file, COLOR, 245
		end
	end,
}
