-- Git from inside the editor. Vimscript, so there is no setup() to call: the
-- plugin is its commands, and loading it on them is enough.
--
-- ,g is the git prefix. It was the last free letter next to the others: ,d is
-- the debugger, ,b and ,B its breakpoints, ,q the database, ,a harpoon.
--
-- The lualine branch component does its own git detection rather than calling
-- FugitiveHead(), so nothing on screen depends on this being loaded already.
return {
	"tpope/vim-fugitive",
	cmd = {
		"G",
		"Git",
		"Gdiffsplit",
		"Gvdiffsplit",
		"Gread",
		"Gwrite",
		"Gedit",
		"Ggrep",
		"Glgrep",
		"Gclog",
		"GMove",
		"GRename",
		"GDelete",
		"GRemove",
	},
	keys = {
		{ "<leader>gs", "<cmd>Git<cr>", desc = "Git: status" },
		{ "<leader>gb", "<cmd>Git blame<cr>", desc = "Git: blame this file" },
		-- Against the index, which is what you want before committing: it shows
		-- what is staged against what is not.
		{ "<leader>gd", "<cmd>Gvdiffsplit<cr>", desc = "Git: diff this file against the index" },
		{ "<leader>gl", "<cmd>Gclog<cr>", desc = "Git: commits of this file into the quickfix" },
		{ "<leader>gw", "<cmd>Gwrite<cr>", desc = "Git: stage this file" },
	},
}
