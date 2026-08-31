-- Change the default Omarchy look'n'feel.

-- https://wiki.hypr.land/Configuring/Basics/Variables/#general
-- hl.config({
--   general = {
--     -- No gaps between windows or borders.
--     gaps_in = 0,
--     gaps_out = 0,
--     border_size = 0,
--
--     -- Change to niri-like side-scrolling layout.
--     layout = "scrolling",
--   },
-- })

-- https://wiki.hypr.land/Configuring/Basics/Variables/#decoration
hl.config({
  decoration = {
    -- Matches the frame/bar's cornerRadius (24) for a consistent look.
    rounding = 24,

    -- Window blur -- lets transparent surfaces (e.g. Kitty's
    -- background_opacity, see ../kitty.conf) show a blurred desktop
    -- behind them instead of plain see-through.
    blur = {
      enabled = true,
      size = 7,
      passes = 3,
      noise = 0.08,
    },
  },
})

-- https://wiki.hypr.land/Configuring/Basics/Variables/#animations
--
-- Animation Profiles -- direct request ("its the hyprland windows
-- that needs it... bubbly, calm, snappy seems to be enough").
-- Investigated a MangoWM+Quickshell dotfiles repo's own "5 animation
-- profiles" feature for the idea, but that repo's WM half is
-- MangoWM-specific (sed-edits its own config.conf, reloads via `mmsg
-- -d reload_config`) -- doesn't apply to Hyprland at all. This is a
-- real Hyprland-native port instead: three named hl.curve()/
-- hl.animation() sets (Omarchy's own default file, read directly, is
-- what the leaf names/shape below are based on), chosen by a plain-
-- text profile file ruixen.settings' System page writes to. Reading
-- state from a file instead of this file being regenerated/templated
-- means `hyprctl reload` alone re-executes this whole script fresh
-- and picks up whatever profile was last chosen -- no separate IPC
-- path needed, same "let the config read real state" spirit as every
-- other file-backed setting in this repo (see ruixen.settings/
-- Settings.qml's own barModeReadProc for the same plain-text-file
-- convention).
-- Default is calm now, not bubbly -- direct request ("switch the
-- order so we start with calm by default and then user can pick next
-- toggle as Bubbly then Snappy last").
local function readAnimationProfile()
  local path = (os.getenv("HOME") or "") .. "/.local/state/ruixen/animation-profile"
  local f = io.open(path, "r")
  if not f then return "calm" end
  local line = f:read("*l") or "calm"
  f:close()
  line = line:gsub("%s+", "")
  if line == "bubbly" or line == "snappy" then return line end
  return "calm"
end

local ruixenAnimProfile = readAnimationProfile()

hl.config({
  animations = {
    enabled = true,
  },
})

-- All three profiles use style = "slide" on windowsIn/windowsOut now,
-- not `popin NN%` -- direct follow-up ("its still wierd i think its
-- the animation from the center thats why... im pretty sure one of
-- them has a slide, is like slide in and out that i like"). Checked
-- omarchy-dotfiles-mini, omarchy-dotfiles, and cachyos-dotfiles
-- directly for a slide setup to port -- none of the three actually
-- customize this (the first two don't override animations at all,
-- cachyos-dotfiles just has Omarchy's own stock popin defaults
-- inline) -- but the diagnosis was right regardless: `popin` scales
-- the window in from its own center, which is exactly the "from the
-- center" motion that read as weird even after calm's speed/overshoot
-- got fixed. Hyprland's own built-in `slide` style (https://wiki.hypr.
-- land/Configuring/Animations/#style) moves the window in from an
-- edge instead of scaling from the middle -- swaps every profile onto
-- it for a consistent, non-center motion; only the curve/speed/bounce
-- differ between profiles now, not the fundamental motion shape.
if ruixenAnimProfile == "bubbly" then
  -- Bubbly -- springy, bouncy, overshoots. Real overshoot via a
  -- backOut-style curve (cubic-bezier(0.34, 1.35, 0.64, 1) -- the y >
  -- 1 control point is what actually produces the overshoot/bounce,
  -- not just a fast speed).
  hl.curve("ruixenBounce", { type = "bezier", points = { { 0.34, 1.35 }, { 0.64, 1 } } })
  hl.curve("ruixenFade", { type = "bezier", points = { { 0.4, 0 }, { 0.2, 1 } } })
  hl.animation({ leaf = "windows", enabled = true, speed = 3.0, bezier = "ruixenBounce" })
  hl.animation({ leaf = "windowsIn", enabled = true, speed = 3.2, bezier = "ruixenBounce", style = "slide" })
  hl.animation({ leaf = "windowsOut", enabled = true, speed = 2.2, bezier = "ruixenBounce", style = "slide" })
  hl.animation({ leaf = "border", enabled = true, speed = 3.0, bezier = "ruixenBounce" })
  hl.animation({ leaf = "fade", enabled = true, speed = 2.0, bezier = "ruixenFade" })
  hl.animation({ leaf = "fadeIn", enabled = true, speed = 2.2, bezier = "ruixenFade" })
  hl.animation({ leaf = "fadeOut", enabled = true, speed = 1.5, bezier = "ruixenFade" })
elseif ruixenAnimProfile == "snappy" then
  -- Fast, tight, no bounce -- gets out of the way immediately.
  hl.curve("ruixenSnap", { type = "bezier", points = { { 0.4, 0 }, { 0.2, 1 } } })
  hl.animation({ leaf = "windows", enabled = true, speed = 2.0, bezier = "ruixenSnap" })
  hl.animation({ leaf = "windowsIn", enabled = true, speed = 2.2, bezier = "ruixenSnap", style = "slide" })
  hl.animation({ leaf = "windowsOut", enabled = true, speed = 1.4, bezier = "ruixenSnap", style = "slide" })
  hl.animation({ leaf = "border", enabled = true, speed = 2.0, bezier = "ruixenSnap" })
  hl.animation({ leaf = "fade", enabled = true, speed = 1.5, bezier = "ruixenSnap" })
  hl.animation({ leaf = "fadeIn", enabled = true, speed = 1.6, bezier = "ruixenSnap" })
  hl.animation({ leaf = "fadeOut", enabled = true, speed = 1.2, bezier = "ruixenSnap" })
else
  -- Calm (default) -- slow, smooth, macOS-ish, lofi cafe vibes. No
  -- overshoot anywhere (easeOutCubic: cubic-bezier(0.33, 1, 0.68, 1)).
  hl.curve("ruixenSmooth", { type = "bezier", points = { { 0.33, 1 }, { 0.68, 1 } } })
  hl.animation({ leaf = "windows", enabled = true, speed = 4.5, bezier = "ruixenSmooth" })
  hl.animation({ leaf = "windowsIn", enabled = true, speed = 5.0, bezier = "ruixenSmooth", style = "slide" })
  hl.animation({ leaf = "windowsOut", enabled = true, speed = 3.5, bezier = "ruixenSmooth", style = "slide" })
  hl.animation({ leaf = "border", enabled = true, speed = 4.0, bezier = "ruixenSmooth" })
  hl.animation({ leaf = "fade", enabled = true, speed = 3.0, bezier = "ruixenSmooth" })
  hl.animation({ leaf = "fadeIn", enabled = true, speed = 3.3, bezier = "ruixenSmooth" })
  hl.animation({ leaf = "fadeOut", enabled = true, speed = 2.4, bezier = "ruixenSmooth" })
end

-- https://wiki.hypr.land/Configuring/Basics/Variables/#layout
-- hl.config({
--   layout = {
--     -- Avoid overly wide single-window layouts on wide screens.
--     single_window_aspect_ratio = { 1, 1 },
--   },
-- })

-- https://wiki.hypr.land/Configuring/Layouts/Scrolling-Layout/
-- hl.config({
--   scrolling = {
--     -- See only one column per screen instead of two.
--     column_width = 0.97,
--   },
-- })
