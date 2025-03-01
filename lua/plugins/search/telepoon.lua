return {
	'areiass36/telepoon',
	name = 'telepoon',
	dependencies = { "nvim-telescope/telescope.nvim", "ThePrimeagen/harpoon" },
	config = function()
		local telescope = require('telescope');
		telescope.setup();
		telescope.load_extension('telepoon');
	end
}
