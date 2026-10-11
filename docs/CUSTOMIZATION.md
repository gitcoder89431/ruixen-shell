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
installations to preserve Omarchy's stock behavior. Open **Wallpaper appearance**
in the notch picker (`SUPER+CTRL+SPACE`) or launcher's Wallpapers extension.
Preview and save settings, then choose **Enable renderer** to apply them to the
desktop. **Use stock renderer** restores the previous stock state through
Omarchy's plugin lifecycle. The enable button refuses competing background
replacements; disable those yourself before switching. Rotation and video/GIF
playback work independently of this renderer.

Choose one of thirteen transitions: Reveal, Bleed through, Pixel dissolve, Iris
bloom, Glass shutters, Scanline, Ink spread, Aurora wash, Vortex, Signal tear,
Datamosh, VHS tracking, or Code bleed. Duration is 0–30 seconds; zero switches
instantly. Mask effects offer softness; glitch effects remember their own
distortion strength and band/block/column density or VHS wobble frequency.
Hover a choice to preview it using the selected duration and its saved controls.
Previews start after images load and never change the desktop or save an effect.

Background effects are independent: **None**, static **CRT texture**, or animated
**Matrix rain**, with intensity and rain speed controls. Preview tiles show the
combination. Ambient zoom and theme glow remain independent toggles.
**Disable motion** finishes transitions, stops zoom/glow, and freezes rain while
retaining static textures. **Reset effects** restores a 420 ms reveal, 0.02
softness, and no background effects. Background overlays pause during media
playback. Matrix uses a 640-pixel texture at 10 fps; CRT has no animation timer.

Appearance is persisted atomically in
`~/.local/state/ruixen/wallpaper-appearance.json`. The earlier local prototype's
settings are imported only when this file does not exist; its file is never
modified. The renderer uses public Quickshell APIs and Omarchy's `background`
compatibility IPC / `shell applyTheme`, with no private runtime imports.
Shaders adapted from [DasPoxy's Glitch collection](https://github.com/DasPoxy/Glitch-Launcher-Collection)
retain their MIT notices and source attribution in each plugin's
`GLITCH-LICENSE.txt` and the renderer's `GLITCH-SOURCES.md`.

### Artwork rotation

Both wallpaper pickers include **Artwork rotation**, independently of the optional
effects renderer. Enable **Rotate artwork**, enter an absolute folder path (or
`~/Pictures/...`), and choose an interval of 1–1440 minutes. **Next artwork**
advances immediately even when automatic rotation is off. Clicking a section
heading opens its controls and collapses the other section.

The persistent `ruixen.wallpaper` service rotates PNG, JPEG, WebP, and AVIF images
in filename order and wraps at the end. Enable **Shuffle** for random selection
without repeating the current image when alternatives exist. Shuffle affects
both scheduled rotation and **Next artwork**; it defaults to off. Subfolders and
video/GIF files are excluded.
Rotation pauses during video/GIF playback and starts a fresh interval afterward.
Settings survive shell restarts in
`~/.local/state/ruixen/wallpaper-rotation.json`. New installations default to off;
rotation never edits the theme's wallpaper collection. Disable any independent
wallpaper-rotation timer before enabling this feature to avoid competing changes.
Missing/empty folders produce an error in the panel. Discovery runs off the UI
thread and is bounded to 10000 directory entries.
