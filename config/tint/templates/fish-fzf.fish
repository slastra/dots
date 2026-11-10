set -Ux FZF_DEFAULT_OPTS "
	--color=fg:{{subtle}},bg:{{background}},hl:{{accent}}
	--color=fg+:{{foreground}},bg+:{{hairline}},hl+:{{accent}}
	--color=border:{{hairline}},header:{{color4}},gutter:{{background}}
	--color=spinner:{{color3}},info:{{ok}}
	--color=pointer:{{color5}},marker:{{color1}},prompt:{{subtle}}"

# Shells that are already open pick up a new scheme too: `tint apply` bumps
# this universal variable, which fires here in every running fish.
function __tint_refresh --on-variable __tint_rev
    source ~/.config/fish/conf.d/fish_frozen_theme.fish
    sed -n '/^# tint:begin/,/^# tint:end/p' ~/.config/fish/config.fish | source
    status is-interactive; and commandline -f repaint
end
