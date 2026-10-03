# Plugins and features reference

What each Ruixen plugin does, and the longer notes on the notch's Kanban
board and the Shelf. The [README](../README.md) shows the product; this is
the inventory. Technical ids (`ruixen.bar`, `ruixen.launcher`, ...) are
unchanged. Back to the [manual index](README.md).

## What's included

- **`ruixen.bar`** — the top bar itself: app launcher, dot-style
  workspace indicator, pinned quick-launch apps, weather, clock, and a
  settings shortcut, all in one connected pill layout. Fresh installs use
  floating glass pills with accent-toned icons.
- **`ruixen.notch`** — a center-notch dashboard with metrics, wallpapers
  (and a theme switcher on the same tab: a segmented control above the
  search box lists every installed Omarchy theme; clicking one applies it
  via Omarchy's own `omarchy-theme-set`),
  storage, music control, a notification history card (attaches to
  Omarchy's own notification service, adding read/unread tracking and a
  deeper backlog on top of it), and a Kanban board (see below), expanding
  from the bar.
- **`ruixen.launcher`** — a Raycast/Spotlight-style command palette in a
  frosted-glass card (real Hyprland compositor blur, not a fake overlay):
  fuzzy-searches Omarchy menu actions and installed apps from one overlay,
  plus a dedicated Search Files mode. Searches both filenames (multi-word
  queries match across path components, not just the final segment) and
  file *contents* (ripgrep-powered, ranked together — content matches
  fill in around real filename hits rather than needing a separate mode),
  across every auto-discovered drive (an internal HDD, a USB stick)
  individually or all at once — plus any custom folder you add yourself,
  or exclude, from this plugin's own built-in Settings extension (its
  File Search page). Filter by file
  type/hidden-files/names-or-contents from a small control row, or type
  the same filters directly into the query (`type:image`, `in:Home`,
  `hidden:true`, ...). Selecting a file shows a real preview — an
  extracted video frame, an image thumbnail, or a text/markdown/JSON
  snippet — plus metadata (type, dimensions/duration, created/modified,
  permissions), and a contextual action menu (Tab, or right-click a row)
  for opening its containing folder or copying its path/name. It also hosts
a Clipboard History view (see [`LAUNCHER.md`](LAUNCHER.md#clipboard-history))
and a browser for the bjarneo community Omarchy themes. Its own
  built-in Settings extension is also the full settings app for this
  shell — Profile, Bar, Audio, Wi-Fi, Bluetooth, Display, Night Light,
  Plugins — replacing the default Omarchy settings panel entirely. Full
  reference: [`docs/LAUNCHER.md`](LAUNCHER.md).
- **The screen frame** — the border that ties the bar and notch together
  visually, in black or following the active theme. It is part of `ruixen.bar` (an earlier standalone
  `ruixen.frame-widget` was merged into it).
- **`ruixen.shelf`** — the drop pocket under the notch (see
  [Shelf](#shelf-drop-pocket) below).
- **`ruixen.wallpaper`** — muted looping video wallpaper support, chosen
  from the notch's own Wallpapers picker; it sits alongside Omarchy's static
  background rather than replacing it.
- **`ruixen.cava`** — a live, edge-docked, audio-reactive spectrum overlay,
  controlled from Ruixen Settings. Needs `cava` and PipeWire.
- **`ruixen.workspaces`**, **`ruixen.power`**, **`ruixen.capturestatus`** —
  bar widgets: a dots-and-pill workspace indicator, battery/power-profile/
  system stats, and a pinned screen-recording control.
- **`ruixen.pinnedapps`** — quick-launch row for apps pinned in the notch's
  own app launcher.
- **`ruixen.pluginpins`** — a pin/unpin dropdown on the bar for any other
  installed bar-widget plugin (yours or a third party's) — install
  something new, pin it from here, no shell.json editing required.
- **`ruixen.peripherals`** — battery percentage for wireless mice,
  keyboards, headsets and controllers (Bluetooth and USB receivers alike),
  pin the ones you care about to show inline on the bar. Detection reads
  `/sys` directly rather than Quickshell's own Bluetooth/UPower bindings,
  which don't reliably cover every wireless peripheral — ported from
  [xgborgeso/omarchy-peripheral-batteries](https://github.com/xgborgeso/omarchy-peripheral-batteries)
  (MIT license).
- **Tray widgets** — `ruixen.tray`, `ruixen.stayawake`,
  `ruixen.quickactions`, `ruixen.weather`, `ruixen.applauncher`,
  `ruixen.settingsbutton`. `ruixen.stayawake` (and any stock Omarchy widget
  it sits next to, like the AI usage indicator) is pinned on or off through
  `ruixen.pluginpins` above, not a separate settings toggle.

`ruixen.media` backs `ruixen.notch`'s own music control as a background
service — it never shows a bar icon of its own by design (an earlier,
oversized play/pause badge was retired), so it's locked in Settings' Plugins
list with no toggle.

Every plugin shares the same surface (black or theme-aware, glass or solid),
corner radii, and motion language, so they read as one shell instead of a pile of separate widgets.

## Kanban board

`ruixen.notch`'s dashboard has a 4th tab: a fixed 3-column board (Todo / In
Progress / Done — Tab cycles through all 4 tabs, or click the column-icon in
the left rail). It's agent-native — every mutation (add, move, rename,
priority, due date, label, description) is a plain IPC call a script or
agent can drive — and it's fully editable in the notch itself now too:
per-column add buttons, hover edit/delete on each card, and a done/total
progress bar. Renaming a column stays CLI-only. Full command reference and
how the click model works: [`docs/CONTROL.md`](CONTROL.md).

## Shelf (drop pocket)

`ruixen.shelf` is a panel that grows out of the frame at the notch's position — the notch's expanded silhouette, with concave wing shoulders, hanging from the top edge: drag files in
from any app, drag them back out into another app or a terminal. It
remembers file paths, never copies anything. Drag local files over the
collapsed notch and the Shelf opens so you can drop them in and see them land
(it hides again if you drag back out without dropping). It's
agent-readable too — `omarchy-shell ruixen.shelf list` shows an agent what
you dropped, and `add /abs/path` lets it put a file on the shelf for you to
drag out. It's its own plugin rather than a notch tab so other apps stay
reachable for drag-and-drop. Details: [`docs/CONTROL.md`](CONTROL.md).
