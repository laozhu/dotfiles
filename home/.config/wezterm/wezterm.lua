local wezterm = require("wezterm")
local window_state = require("window_state")

local config = wezterm.config_builder()

config.color_scheme = "Gruvbox Dark (Gogh)"
config.font = wezterm.font("Hack Nerd Font Mono")
config.font_size = 14.0
config.line_height = 1.25
config.window_background_opacity = 0.8
config.macos_window_background_blur = 50
config.hide_tab_bar_if_only_one_tab = true
-- Native shadows outline rounded corners without clipping a custom border.
config.window_decorations = "RESIZE|MACOS_FORCE_ENABLE_SHADOW"

wezterm.on("window-focus-changed", window_state.update)
wezterm.on("window-config-reloaded", window_state.update)

return config
