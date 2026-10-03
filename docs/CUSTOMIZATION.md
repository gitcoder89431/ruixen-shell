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
