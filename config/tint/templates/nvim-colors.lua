-- {{name}}: the terminal palette for :terminal buffers. Written by `tint apply`
-- from ~/.config/tint/templates/nvim-colors.lua.
local M = {}

M.palette = {
  color_01 = "{{color0}}",
  color_02 = "{{color1}}",
  color_03 = "{{color2}}",
  color_04 = "{{color3}}",
  color_05 = "{{color4}}",
  color_06 = "{{color5}}",
  color_07 = "{{color6}}",
  color_08 = "{{color7}}",
  color_09 = "{{color8}}",
  color_10 = "{{color9}}",
  color_11 = "{{color10}}",
  color_12 = "{{color11}}",
  color_13 = "{{color12}}",
  color_14 = "{{color13}}",
  color_15 = "{{color14}}",
  color_16 = "{{color15}}",
  background = "{{background}}",
  foreground = "{{foreground}}",
  cursor = "{{foreground}}",
}

vim.g.terminal_color_0  = "{{color0}}"
vim.g.terminal_color_1  = "{{color1}}"
vim.g.terminal_color_2  = "{{color2}}"
vim.g.terminal_color_3  = "{{color3}}"
vim.g.terminal_color_4  = "{{color4}}"
vim.g.terminal_color_5  = "{{color5}}"
vim.g.terminal_color_6  = "{{color6}}"
vim.g.terminal_color_7  = "{{color7}}"
vim.g.terminal_color_8  = "{{color8}}"
vim.g.terminal_color_9  = "{{color9}}"
vim.g.terminal_color_10 = "{{color10}}"
vim.g.terminal_color_11 = "{{color11}}"
vim.g.terminal_color_12 = "{{color12}}"
vim.g.terminal_color_13 = "{{color13}}"
vim.g.terminal_color_14 = "{{color14}}"
vim.g.terminal_color_15 = "{{color15}}"

return M
