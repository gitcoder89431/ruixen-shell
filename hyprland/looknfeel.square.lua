-- Change the default Omarchy look'n'feel.
--
-- "Square" variant -- direct request: someone wanted stock Omarchy's
-- own square corners (no rounding) but WITHOUT losing the rest of
-- this repo's own look (the thinner 1px border, blur, shadow, the
-- animation profiles) the way switching all the way to
-- looknfeel.default.lua (ruixen-lookfeel.sh off) would. A full copy of
-- looknfeel.ruixen.lua with just rounding changed (24 -> 0) rather
-- than an include/override split -- this repo's own existing on/off
-- pair is ALREADY two fully independent files with no shared base, so
-- this follows that same established pattern rather than introducing
-- unverified Lua hl.config() merge-semantics risk (does a later
-- decoration.rounding-only call preserve an earlier call's blur/
-- shadow keys, or replace the whole table? -- untested, not worth
-- risking here). The tradeoff is real: any future tweak to the shared
-- parts (blur/shadow/animation profiles) needs applying in both files
-- by hand.
--
-- ruixen.frame-widget/Overlay.qml's own screen-frame corner mask
-- reads which of the three variants is active and matches its
-- rounding automatically (0 here, 24 for looknfeel.ruixen.lua) --
-- direct bug report, live: mismatched rounding between the real
-- window and the frame's own hole punch made a square window's real
-- corner get partly painted over by the frame's still-rounded mask,
-- reading as "the bottom corner clips under the shell frame".

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

-- Direct request ("for the border thickness, is there abit more
-- thinner?") -- Omarchy's own default is 2 (confirmed live via
-- `hyprctl getoption general:border_size`, not assumed), never
-- overridden by this file until now. 1 is the thinnest non-zero
-- border Hyprland supports; going to 0 would remove the border
-- entirely, which isn't what was asked for here.
--
-- gaps_out: top stays Hyprland's own default (10, confirmed live via
-- `hyprctl getoption general:gaps_out`), right/bottom/left bumped to
-- 20 -- direct request, docked mode: a real window's own square
-- corner (rounding: 0 in this variant) sitting close to
-- ruixen.bar's own wing decoration (still rounded, ruixen.bar/Bar.qml)
-- or ruixen.frame-widget's side/bottom border reads as touching/
-- clipping with no buffer. Top isn't included here -- the bar's own
-- exclusiveZone already reserves real top space independent of gaps;
-- side/bottom have no such reservation, so they're the ones that
-- actually need the extra room. Table form, not a CSS-style string --
-- confirmed via `hyprctl configerrors` after the string form failed:
-- "css_gap type requires an integer or a table with optional 'top',
-- 'right', 'bottom', 'left' fields".
--
-- gaps_in (Comfy/Tight) -- same shared spacing-profile file
-- looknfeel.ruixen.lua reads (see its own comment for the full "why")
-- -- direct instruction ("if its tight then both round and sharp will
-- get no inner padding") -- so this variant honors the same choice
-- rather than always sitting at the stock 5 regardless of what the
-- user picked.
local function readSpacingProfile()
  local path = (os.getenv("HOME") or "") .. "/.local/state/ruixen/spacing-profile"
  local f = io.open(path, "r")
  if not f then return "comfy" end
  local line = f:read("*l") or "comfy"
  f:close()
  line = line:gsub("%s+", "")
  if line == "tight" then return line end
  return "comfy"
end

local ruixenGapsIn = readSpacingProfile() == "tight" and 0 or 5

hl.config({
  general = {
    border_size = 1,
    gaps_in = ruixenGapsIn,
    gaps_out = { top = 10, right = 20, bottom = 20, left = 20 },
  },
})

-- https://wiki.hypr.land/Configuring/Basics/Variables/#decoration
hl.config({
  decoration = {
    -- No rounding -- the whole point of this variant. The frame's own
    -- corner mask matches this automatically (see this file's own
    -- header comment).
    rounding = 0,

    -- Ported from the user's own past cachyos-dotfiles config
    -- (0.98/0.94, unchanged from that source -- direct request: "yea
    -- both the color inactive and opacity split"). Focused windows
    -- read as slightly more solid, unfocused ones fade back a touch --
    -- same depth-hierarchy idea as shadow's own color_inactive below,
    -- a different lever. Belongs under decoration, not general --
    -- confirmed directly (`hyprctl getoption general:active_opacity`
    -- returned "no such option") after an initial wrong placement.
    active_opacity = 0.98,
    inactive_opacity = 0.94,

    -- Window blur -- lets transparent surfaces (e.g. Kitty's
    -- background_opacity, see ../kitty.conf) show a blurred desktop
    -- behind them instead of plain see-through.
    blur = {
      enabled = true,
      size = 7,
      passes = 3,
      noise = 0.08,
    },

    -- Direct request ("i feel like this design could do drop shadow
    -- for depth... i want it to feel premium") -- global (Hyprland's
    -- own decoration.shadow applies to every real window uniformly,
    -- there's no per-app override), unlike a per-surface Quickshell
    -- effect. Started deliberately small/soft (range 12, 25% alpha,
    -- offset 3). A follow-up widened range to 20 and offset to 6 to
    -- make it more noticeable -- overshot: direct correction ("too
    -- much fadded now, distance is too much, like before but more
    -- intense") wanted the ORIGINAL tight distance back (range/offset
    -- are what push the shadow further out and soften/fade it), with
    -- only the color intensity (alpha) pushed higher instead. Range
    -- and offset back to 12/3, alpha up further to ~56%
    -- (rgba(00000090), well past the ~38% the widen attempt used) --
    -- close and dark, not far and soft.
    shadow = {
      enabled = true,
      range = 12,
      render_power = 3,
      color = "rgba(00000090)",
      -- Dimmer than the active color above (~56% -> ~28% alpha, same
      -- roughly-half ratio the user's own past cachyos-dotfiles config
      -- used for this exact pair) -- direct request: "yea both the
      -- color inactive and opacity split". Focused window's shadow
      -- reads darker/closer, unfocused ones recede -- same depth-
      -- hierarchy idea as active_opacity/inactive_opacity above.
      color_inactive = "rgba(00000048)",
      offset = { 0, 3 },
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
  -- Direct follow-up ("can we animate the effect moving between
  -- window so its sliding as well to fit with the design") -- Omarchy's
  -- own default explicitly disables this leaf (`workspaces, enabled =
  -- false`, see /usr/share/omarchy/default/hypr/looknfeel.lua), and
  -- this file never overrode it, so switching workspaces cut instantly
  -- with none of the slide motion windowsIn/windowsOut already have.
  --
  -- Own toned-down curve, not the shared ruixenBounce above -- direct
  -- follow-up ("bubbly dont make it over scroll as much") after trying
  -- the full window-open bounce on a workspace slide: the same 1.35
  -- overshoot that reads as a nice springy pop for a window appearing
  -- read as the whole workspace overshooting past its target and
  -- sliding back, which is a much larger, more noticeable motion over
  -- a full-screen slide than over one window. Same curve shape (same x
  -- control points), just a shallower overshoot (1.12, not 1.35) --
  -- windows/windowsIn/windowsOut above are untouched, no complaint
  -- there.
  hl.curve("ruixenBounceSoft", { type = "bezier", points = { { 0.34, 1.12 }, { 0.64, 1 } } })
  hl.animation({ leaf = "workspaces", enabled = true, speed = 3.0, bezier = "ruixenBounceSoft", style = "slide" })
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
  -- See the bubbly profile's own comment above for why this leaf is
  -- here now and why it reuses "windows" own speed/bezier.
  hl.animation({ leaf = "workspaces", enabled = true, speed = 2.0, bezier = "ruixenSnap", style = "slide" })
  hl.animation({ leaf = "border", enabled = true, speed = 2.0, bezier = "ruixenSnap" })
  hl.animation({ leaf = "fade", enabled = true, speed = 1.5, bezier = "ruixenSnap" })
  hl.animation({ leaf = "fadeIn", enabled = true, speed = 1.6, bezier = "ruixenSnap" })
  hl.animation({ leaf = "fadeOut", enabled = true, speed = 1.2, bezier = "ruixenSnap" })
else
  -- Calm (default) -- slow, smooth, macOS-ish, lofi cafe vibes. No
  -- overshoot anywhere (easeOutCubic: cubic-bezier(0.33, 1, 0.68, 1)).
  --
  -- Every speed here is ~20% faster than the original tuning (4.5 ->
  -- 3.6, 5.0 -> 4.0, etc.) -- direct follow-up ("make calm abit more
  -- snappy"). Same curve (ruixenSmooth, no overshoot) and the same
  -- relative pacing between leaves as before, just the whole profile
  -- nudged toward bubbly's own pace (windows: bubbly 3.0, calm now
  -- 3.6) without losing its identity as the slowest, calmest of the
  -- three -- still meaningfully slower than snappy's 2.0 or bubbly's
  -- 3.0.
  hl.curve("ruixenSmooth", { type = "bezier", points = { { 0.33, 1 }, { 0.68, 1 } } })
  hl.animation({ leaf = "windows", enabled = true, speed = 3.6, bezier = "ruixenSmooth" })
  hl.animation({ leaf = "windowsIn", enabled = true, speed = 4.0, bezier = "ruixenSmooth", style = "slide" })
  hl.animation({ leaf = "windowsOut", enabled = true, speed = 2.8, bezier = "ruixenSmooth", style = "slide" })
  -- See the bubbly profile's own comment above for why this leaf is
  -- here now and why it reuses "windows" own speed/bezier.
  hl.animation({ leaf = "workspaces", enabled = true, speed = 3.6, bezier = "ruixenSmooth", style = "slide" })
  hl.animation({ leaf = "border", enabled = true, speed = 3.2, bezier = "ruixenSmooth" })
  hl.animation({ leaf = "fade", enabled = true, speed = 2.4, bezier = "ruixenSmooth" })
  hl.animation({ leaf = "fadeIn", enabled = true, speed = 2.6, bezier = "ruixenSmooth" })
  hl.animation({ leaf = "fadeOut", enabled = true, speed = 1.9, bezier = "ruixenSmooth" })
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
