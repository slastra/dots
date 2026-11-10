-- {{name}}. Written by `tint apply` from ~/.config/tint/templates/hypr-theme.lua.
return {
    border_active   = "rgb({{accent|bare}})",     -- accent
    border_inactive = "rgb({{hairline|bare}})",   -- the hairline: background stepped 20% toward foreground
    rounding        = {{radius}},                  -- `tint shape --radius N`
    border_size     = {{border}},                  -- `tint shape --border N`
}
