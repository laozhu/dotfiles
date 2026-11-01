local M = {}

-- Dim unfocused windows so the focused one is obvious at a glance.
local UNFOCUSED_FOREGROUND_TEXT_HSB = { hue = 1.0, saturation = 0.25, brightness = 0.45 }
local UNFOCUSED_WINDOW_BACKGROUND_OPACITY = 0.62

-- get_config_overrides() hands back a copy, so compare fields instead of
-- table identity to avoid triggering redundant config reloads.
local function same_text_hsb(actual, expected)
  if actual == nil or expected == nil then
    return actual == expected
  end
  return actual.hue == expected.hue
    and actual.saturation == expected.saturation
    and actual.brightness == expected.brightness
end

function M.update(window)
  local overrides = window:get_config_overrides() or {}
  -- Window overrides survive config reloads; remove borders from the old config.
  local removed_border = false
  local frame = overrides.window_frame
  if frame then
    for _, key in ipairs({
      "border_left_width",
      "border_right_width",
      "border_top_height",
      "border_bottom_height",
      "border_left_color",
      "border_right_color",
      "border_top_color",
      "border_bottom_color",
    }) do
      if frame[key] ~= nil then
        frame[key] = nil
        removed_border = true
      end
    end
    if next(frame) == nil then
      overrides.window_frame = nil
    end
  end
  local text_hsb, opacity
  if not window:is_focused() then
    text_hsb = UNFOCUSED_FOREGROUND_TEXT_HSB
    opacity = UNFOCUSED_WINDOW_BACKGROUND_OPACITY
  end

  if
    not removed_border
    and same_text_hsb(overrides.foreground_text_hsb, text_hsb)
    and overrides.window_background_opacity == opacity
  then
    return
  end

  overrides.foreground_text_hsb = text_hsb
  overrides.window_background_opacity = opacity
  window:set_config_overrides(overrides)
end

return M
