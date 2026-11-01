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
  local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
  end
  return copy(self.overrides)
end
function window:set_config_overrides(overrides)
  self.overrides = overrides
  self.changes = self.changes + 1
end
-- Existing GUI windows retain overrides written by the previous configuration.
local reload = assert(handlers["window-config-reloaded"], "Reload must clear stale border overrides")
local borders = {
  "border_left_width", "border_right_width", "border_top_height", "border_bottom_height",
  "border_left_color", "border_right_color", "border_top_color", "border_bottom_color",
}
window.overrides = {window_frame = {font_size = 12}, cursor_blink_rate = 500}
for _, key in ipairs(borders) do window.overrides.window_frame[key] = "old-border" end
reload(window)
for _, key in ipairs(borders) do assert(window.overrides.window_frame[key] == nil) end
assert(window.overrides.window_frame.font_size == 12, "Keep unrelated frame overrides")
assert(window.overrides.cursor_blink_rate == 500, "Keep unrelated window overrides")
local changes = window.changes
reload(window)
assert(window.changes == changes, "Reload cleanup must not cause a reload loop")
window.overrides = {window_frame = {border_left_color = "old-border"}}
reload(window)
assert(window.overrides.window_frame == nil, "Remove an empty legacy frame override")
window.overrides = {}
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
