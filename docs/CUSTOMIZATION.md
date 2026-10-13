# Customizing Ruixen

Look-and-feel options that sit on top of a working install. Most of these
are also reachable from **Ruixen Settings** (open it with the keybind from
[`KEYBINDS.md`](KEYBINDS.md)); the commands below are the same switches from
a terminal. Back to the [manual index](README.md).

## Docked bar mode (experimental)

By default the left and right icon groups float as separate pills, inset
from the frame. Docked mode merges each side into one continuous shape
flush with the frame's corners instead — like the notch, just with one
shoulder curve per side instead of two. Not the default look, but worth
trying:

```bash
./dev/ruixen-bar-mode.sh docked      # merged pills, flush with the frame
./dev/ruixen-bar-mode.sh floating    # back to the default separate pills
./dev/ruixen-bar-mode.sh status      # show which one is active
```

No restart needed either way — it's a live config reload.

## Bar style

The normal style is `notch`: the center island stays visible and the bar keeps
its center reserved. `fullbar` is the saved full-width statusline skin from the
old sharp+docked experiment. It hides the notch overlay and lets the bar own the
center space again.

```bash
./dev/ruixen-bar-style.sh notch      # current island/notch skin
./dev/ruixen-bar-style.sh fullbar    # full-width statusline skin, no notch
./dev/ruixen-bar-style.sh status     # show which one is active
```

This is independent from `./dev/ruixen-bar-mode.sh docked|floating` and independent
from Hyprland sharp/rounded window corners.

## Window look'n'feel (Hyprland)

Ruixen also rounds window corners and adds blur, to match the frame/bar.
Fresh installs default to the half-radius look (12px). Toggle it
independently of the plugins above:

```bash
hyprland/ruixen-lookfeel.sh on      # rounded corners + blur, matches the frame
hyprland/ruixen-lookfeel.sh half    # rounded corners at half the radius (12px), same border/blur/shadow/animations
hyprland/ruixen-lookfeel.sh off     # stock Omarchy: square corners, no blur
hyprland/ruixen-lookfeel.sh square  # square corners, but keeps the thin border/blur/shadow/animations
hyprland/ruixen-lookfeel.sh status  # show which one is active
```

`half` is the default middle step between `on` and `square` — the same rounded
look at half the corner radius, for when 24px reads too soft and sharp reads
too stark. `square` is for anyone who wants stock Omarchy's own square corners
without giving up the rest of Ruixen's look. The screen frame's own corner
rounding follows whichever of the four is active automatically when the bar is
floating. When the bar is docked, the frame's corner always stays rounded
regardless of which variant is active -- docked mode's own wider gaps already
keep real window corners well clear of that curve, so nothing clips, and it
keeps the docked bar's own corner (always rounded) visually consistent with the
frame right next to it.

## Wallpaper appearance

The installer includes the native **ruixen.background** renderer, disabled on new
installations to preserve Omarchy's stock behavior. The launcher's Wallpapers
extension carries the full **Wallpaper appearance** panel (the notch picker
carries Artwork rotation instead -- see below -- so the two surfaces split the
feature set rather than both carrying everything), flattened into chips next
to the hero tile rather than a separate expandable card: the hero itself
doubles as the live preview, instead of a dedicated preview box.

**Transition** is a row of chips -- **Stock** plus all thirteen effects
(Reveal, Bleed through, Pixel dissolve, Iris bloom, Glass shutters, Scanline,
Ink spread, Aurora wash, Vortex, Signal tear, Datamosh, VHS tracking, Code
bleed). Picking a real transition applies a baked-in duration (900ms for
mask effects, 550ms for the four glitch effects -- a glitch reads as itself
*because* it's abrupt, everything else favors a slower, less snappy feel)
plus softness or strength/density, and turns the renderer on automatically,
no separate enable step; picking Stock turns transitions off (an instant
cut) without disabling the renderer if **Effect** is still using it. Hover
any transition chip to preview it live in the hero tile before picking it;
hovering never changes the desktop or saves anything.

**Effect** is three chips -- **Off**, **CRT**, **Matrix** -- for the
independent background effect, with **Intensity** always available once one
is active and **Speed** shown only for Matrix (CRT has no animation timer).
Picking CRT or Matrix also turns the renderer on; picking Off only clears the
background effect, leaving the renderer's on/off state to Transition, so
turning Effect off doesn't kill an active Transition (or the reverse).
Hovering an Effect chip also live-previews it in the hero tile. No ambient
toggles remain: zoom and glow were too subtle to read as real options (max
~0.7% scale variance over a 3-minute cycle and ~4% opacity over a 60s cycle
respectively), and disable motion followed since Transition Stock + Effect
Off already reaches the same "nothing moving" state through controls that
already exist.

The notch picker gets the same two features as compact chips instead, next
to Shuffle in its own filter row -- a quicker path that trades the
launcher's full chip set and sliders for one-click cycling. **Transition**
cycles **Stock → Reveal → Bleed through → … → Code bleed → Stock**, same
baked-in per-effect durations and auto-enable as the launcher's chips.
**Effect** cycles **Off → CRT → Matrix → Off**, same shared-renderer rule as
above. Right-clicking either chip jumps straight back to its own Off/Stock.
Intensity and Speed stay launcher-only -- Effect is a continuous overlay on
whatever's already showing, not a between-two-images thing, so it has no
preview of its own either.

The notch's own wallpaper grid doubles as Transition's live preview surface
-- no separate preview box. With a real transition selected, hovering any
image tile (not a video/GIF tile, since the renderer never transitions into
one of those -- always an instant cut) plays that transition from the
current wallpaper into the hovered one, right in the grid, using the same
baked-in duration/softness the chip already set. The current wallpaper's
own tile previews too (both ends are the same image -- mask effects won't
show a visible swap, but the glitch effects still show real motion since
their distortion is procedural, not content-driven). Moving off the tile
stops it; nothing is selected or saved by hovering.

Appearance is persisted atomically in
`~/.local/state/ruixen/wallpaper-appearance.json`. The earlier local prototype's
settings are imported only when this file does not exist; its file is never
modified. The renderer uses public Quickshell APIs and Omarchy's `background`
compatibility IPC / `shell applyTheme`, with no private runtime imports.
Shaders adapted from [DasPoxy's Glitch collection](https://github.com/DasPoxy/Glitch-Launcher-Collection)
retain their MIT notices and source attribution in each plugin's
`GLITCH-LICENSE.txt` and the renderer's `GLITCH-SOURCES.md`.

### Artwork rotation

The notch picker includes **Artwork rotation**, independently of the optional
effects renderer in the launcher's Wallpapers extension. One grouped chip
sits in the notch's wallpaper filter row, next to All/Images/Video/Gif --
same two-segment shape as Cliamp Radio's LIVE/clock pill, just square
(radius 8) instead of fully rounded. A constant-accent **Shuffle** segment
marks it as a feature, and a second segment shows the current value: **Off**,
**5m**, **15m**, **30m**, or **60m**. Click anywhere on it to cycle
**Off → 5m → 15m → 30m → 60m → Off**; rotation always shuffles when it's on,
so there's no separate on/off for that. Always reads from
`~/Pictures/ruixen-wallpapers`, the same folder the rest of the picker
already shows artwork from.

The persistent `ruixen.wallpaper` service rotates PNG, JPEG, WebP, and AVIF
images in that folder at random, without repeating the current image when
alternatives exist. Subfolders and video/GIF files are excluded.
Rotation pauses during video/GIF playback and starts a fresh interval afterward.
Settings survive shell restarts in
`~/.local/state/ruixen/wallpaper-rotation.json`. New installations default to off;
rotation never edits the theme's wallpaper collection. Disable any independent
wallpaper-rotation timer before enabling this feature to avoid competing changes.
A missing or empty folder fails silently in the chip itself (no separate
status line -- it used to shift the grid down whenever it appeared).
Discovery runs off the UI thread and is bounded to 10000 directory entries.
