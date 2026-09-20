-- LookAway-managed: io.github.artemisa81.lookaway
-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 artemisa81
-- LookAway — Hyprland layer rules for the privacy scrim.
--
-- Install: copy this file to ~/.config/hypr/lookaway.lua and add
--   require("hypr.lookaway")
-- to ~/.config/hypr/hyprland.lua (near the other user `require` lines), then
--   hyprctl reload
--
-- The LookAway plugin renders a passive, click-through fullscreen layer surface
-- named "lookaway-scrim". Enabling blur on that layer softens whatever is
-- behind it (windows + wallpaper) without the plugin ever capturing the screen.
-- The surface's own alpha gradient controls how much of the blurred backdrop
-- shows, which is what produces the directional look-away transition.
-- This enables Hyprland's global blur engine; the layer rule below limits the
-- actual backdrop blur to LookAway's surface.
hl.config({
  decoration = {
    blur = {
      enabled = true,
    },
  },
})

hl.layer_rule({
  match = { namespace = "lookaway-scrim" },
  blur = true,
  ignore_alpha = 0,
  no_anim = true,
  animation = "none",
  -- Uncomment to keep the scrim out of screen shares and recordings: you still
  -- see the soften locally, but captured/streamed output is left untouched.
  -- no_screen_share = true,
})
