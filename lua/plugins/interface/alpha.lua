return {
	'goolord/alpha-nvim',
	config = function()
		local alpha = require("alpha")
		local dashboard = require("alpha.themes.dashboard")

		dashboard.section.header.val = {
			[[                                                                              ]],
			[[                                                                              ]],
			[[                                                                              ]],
			[[                                                                              ]],
			[[                                                                              ]],
			[[                                                                              ]],
			[[                                                                              ]],
			[[                                                                              ]],
			[[                                                                              ]],
			[[  ██╗ █████╗ ██████╗ ███████╗██╗ █████╗ ███████╗███████╗██████╗  ██████╗ ██╗  ]],
			[[ ██╔╝██╔══██╗██╔══██╗██╔════╝██║██╔══██╗██╔════╝██╔════╝╚════██╗██╔════╝ ╚██╗ ]],
			[[██╔╝ ███████║██████╔╝█████╗  ██║███████║███████╗███████╗ █████╔╝███████╗  ╚██╗]],
			[[╚██╗ ██╔══██║██╔══██╗██╔══╝  ██║██╔══██║╚════██║╚════██║ ╚═══██╗██╔═══██╗ ██╔╝]],
			[[ ╚██╗██║  ██║██║  ██║███████╗██║██║  ██║███████║███████║██████╔╝╚██████╔╝██╔╝ ]],
			[[  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝╚═╝╚═╝  ╚═╝╚══════╝╚══════╝╚═════╝  ╚═════╝ ╚═╝  ]],


		}
		dashboard.section.footer.val = "github.com/areiass36"
		dashboard.section.buttons.val = {}
		alpha.setup(dashboard.opts)
	end,
}
