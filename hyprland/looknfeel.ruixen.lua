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
local function readAnimationProfile()
  local path = (os.getenv("HOME") or "") .. "/.local/state/ruixen/animation-profile"
  local f = io.open(path, "r")
  if not f then return "bubbly" end
  local line = f:read("*l") or "bubbly"
  f:close()
  line = line:gsub("%s+", "")
  if line == "calm" or line == "snappy" then return line end
  return "bubbly"
end

local ruixenAnimProfile = readAnimationProfile()

hl.config({
  animations = {
    enabled = true,
  },
})

if ruixenAnimProfile == "calm" then
  -- Slow, smooth, macOS-ish -- lofi cafe vibes. No overshoot anywhere
  -- (easeOutCubic: cubic-bezier(0.33, 1, 0.68, 1)) -- direct follow-up
  -- ("the calm over laps or shoots too much"): the real cause wasn't
  -- the curve itself (mathematically bounded at y=1, can't overshoot)
  -- but the `popin NN%` style on windowsIn/Out -- a slow ~800ms scale-
  -- from-95%-to-100% reads as the window visibly growing/"shooting"
  -- into place, not a clean fade. Dropped the style entirely (falls
  -- back to Hyprland's own plain size+alpha crossfade, no scale-pop
  -- component to misread as overshoot) and cut every speed down --
  -- still the slowest of the three profiles, just not so long that
  -- overlapping window opens felt tangled.
  hl.curve("ruixenSmooth", { type = "bezier", points = { { 0.33, 1 }, { 0.68, 1 } } })
  hl.animation({ leaf = "windows", enabled = true, speed = 4.5, bezier = "ruixenSmooth" })
  hl.animation({ leaf = "windowsIn", enabled = true, speed = 5.0, bezier = "ruixenSmooth" })
  hl.animation({ leaf = "windowsOut", enabled = true, speed = 3.5, bezier = "ruixenSmooth" })
  hl.animation({ leaf = "border", enabled = true, speed = 4.0, bezier = "ruixenSmooth" })
  hl.animation({ leaf = "fade", enabled = true, speed = 3.0, bezier = "ruixenSmooth" })
  hl.animation({ leaf = "fadeIn", enabled = true, speed = 3.3, bezier = "ruixenSmooth" })
  hl.animation({ leaf = "fadeOut", enabled = true, speed = 2.4, bezier = "ruixenSmooth" })
elseif ruixenAnimProfile == "snappy" then
  -- Fast, tight, no bounce -- gets out of the way immediately.
  hl.curve("ruixenSnap", { type = "bezier", points = { { 0.4, 0 }, { 0.2, 1 } } })
  hl.animation({ leaf = "windows", enabled = true, speed = 2.0, bezier = "ruixenSnap" })
  hl.animation({ leaf = "windowsIn", enabled = true, speed = 2.2, bezier = "ruixenSnap", style = "popin 92%" })
  hl.animation({ leaf = "windowsOut", enabled = true, speed = 1.4, bezier = "ruixenSnap", style = "popin 92%" })
  hl.animation({ leaf = "border", enabled = true, speed = 2.0, bezier = "ruixenSnap" })
  hl.animation({ leaf = "fade", enabled = true, speed = 1.5, bezier = "ruixenSnap" })
  hl.animation({ leaf = "fadeIn", enabled = true, speed = 1.6, bezier = "ruixenSnap" })
  hl.animation({ leaf = "fadeOut", enabled = true, speed = 1.2, bezier = "ruixenSnap" })
else
  -- Bubbly -- springy, bouncy, overshoots. Default, fun. Real
  -- overshoot via a backOut-style curve (cubic-bezier(0.34, 1.35,
  -- 0.64, 1) -- the y > 1 control point is what actually produces the
  -- overshoot/bounce, not just a fast speed). Direct follow-up ("the
  -- bubbly is abit too slow"): a strong 1.56 overshoot at a slow speed
  -- meant the window visibly wobbled and took a while to settle on
  -- top of an already-slow base animation, compounding into
  -- "sluggish" overall. Eased the overshoot back to 1.35 (still a
  -- real, visible bounce) and cut every speed roughly 30-40% so the
  -- whole motion reads quicker while keeping the springy character.
  hl.curve("ruixenBounce", { type = "bezier", points = { { 0.34, 1.35 }, { 0.64, 1 } } })
  hl.curve("ruixenFade", { type = "bezier", points = { { 0.4, 0 }, { 0.2, 1 } } })
  hl.animation({ leaf = "windows", enabled = true, speed = 3.0, bezier = "ruixenBounce" })
  hl.animation({ leaf = "windowsIn", enabled = true, speed = 3.2, bezier = "ruixenBounce", style = "popin 85%" })
  hl.animation({ leaf = "windowsOut", enabled = true, speed = 2.2, bezier = "ruixenBounce", style = "popin 85%" })
  hl.animation({ leaf = "border", enabled = true, speed = 3.0, bezier = "ruixenBounce" })
  hl.animation({ leaf = "fade", enabled = true, speed = 2.0, bezier = "ruixenFade" })
  hl.animation({ leaf = "fadeIn", enabled = true, speed = 2.2, bezier = "ruixenFade" })
  hl.animation({ leaf = "fadeOut", enabled = true, speed = 1.5, bezier = "ruixenFade" })
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
