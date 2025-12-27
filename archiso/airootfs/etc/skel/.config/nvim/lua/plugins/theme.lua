return {
	{
		"catppuccin/nvim",
		name = "catppuccin",
		priority = 1000,
    opts = {
      flavour = "mocha", -- Default mocha
      transparent_background = true,
      integrations = {
        alpha = true,
        mason = true,
        neotree = true,
        neotest = true,
        notify = true,
        telescope = {
          enabled = true,
          style = "nvchad",
        },
        which_key = true,
      },
    },
	},
	{
		"LazyVim/LazyVim",
		opts = {
			colorscheme = "catppuccin",
		},
	},
}
