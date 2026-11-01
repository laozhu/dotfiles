#!/usr/bin/env bash
set -euo pipefail
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
nix shell --max-jobs 0 --inputs-from "$repo_dir" nixpkgs#lua --command \
  lua - "$repo_dir/home/.config/wezterm/wezterm.lua" <<'LUA'
local handlers = {}
package.preload.wezterm = function()
  return {
    config_builder = function() return {} end,
    font = function(name) return name end,
    on = function(event, handler) handlers[event] = handler end,
  }
end
local config = dofile(arg[1])
assert(config.window_frame == nil, "Keep native rounded corners without clipped custom borders")
assert(config.window_decorations:find("MACOS_FORCE_ENABLE_SHADOW", 1, true))
local window = { focused = true, overrides = {}, changes = 0 }
function window:is_focused() return self.focused end
function window:get_config_overrides()
  -- Real WezTerm returns a copy, not the original table.
  local copy = {}
  for key, value in pairs(self.overrides) do copy[key] = value end
  return copy
end
function window:set_config_overrides(overrides)
  self.overrides = overrides
  self.changes = self.changes + 1
end
local focus = assert(handlers["window-focus-changed"])
focus(window)
local changes = window.changes
focus(window)
assert(window.changes == changes, "Stable focus must not trigger another config reload")
window.focused = false
focus(window)
assert(window.overrides.foreground_text_hsb ~= nil, "Keep inactive text dimming")
assert(window.overrides.window_background_opacity < config.window_background_opacity)
changes = window.changes
focus(window)
assert(window.changes == changes, "Repeated blur events must not reload config")
window.focused = true
focus(window)
assert(window.overrides.foreground_text_hsb == nil)
assert(window.overrides.window_background_opacity == nil)
print("WezTerm native decorations and focus tests passed.")
LUA
