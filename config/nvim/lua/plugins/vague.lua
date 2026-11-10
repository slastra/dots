return {
  {
    "vague2k/vague.nvim",
    name = "vague",
    lazy = false,
    priority = 1000,
    opts = {
      -- the desktop's palette is Vague on pure black (see ~/.config/kitty/colors.conf)
      colors = {
        bg = "#000000",
        inactiveBg = "#080808",
      },
    },
  },
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "vague",
    },
  },
}
