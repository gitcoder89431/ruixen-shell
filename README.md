# ruixen-workspaces

A `kind: bar-widget` Omarchy plugin -- a GNOME/Ubuntu-style workspace
indicator (small dots for inactive workspaces, a wider pill for the
focused one) instead of the stock `omarchy.workspaces`' numbered digits.
Per direct request: "swap from digits to like the linux kinda one with
the dots and bar... i think it will look better more softer".

## Why a separate plugin, not an edit to omarchy.workspaces

`omarchy.workspaces` (`/usr/share/omarchy/shell/plugins/bar/widgets/
Workspaces.qml`) is Omarchy-owned -- replaced wholesale on every
`omarchy-update`, never a customization target, same standing rule every
other `ruixen.*` plugin in this project already follows. The underlying
logic in that file is genuinely simple (~70 lines) and didn't need
reinventing, just a different rendering of the same real state, so this
plugin reads the exact same data through the exact same real API:

- `Quickshell.Hyprland`'s own `Hyprland.workspaces`/`Hyprland.focusedWorkspace`
  for live workspace/occupied/focused state.
- The same `workspaceIds()` logic verbatim (pad to `[1,2,3,4,5]`, append
  any active workspace up to id 10, sorted) -- confirmed by reading the
  real file directly, not guessed.
- The same `hyprctl dispatch` mechanism to focus a workspace on click
  (`hl.dsp.focus({ workspace = "<id>" })` via `root.bar.run(...)`).

## The look

Each workspace renders as a round dot; the currently focused one
animates into a wider horizontal capsule instead (`Behavior on width`,
`180ms` `OutCubic`) -- the actual GNOME Shell tell, not just a color
swap. Both color and opacity animate too
(`ColorAnimation`/`NumberAnimation`, `180ms`).

**Colors, real token fix**: first pass used `Color.foreground` (the
theme's PRIMARY text token) dimmed via opacity (`60%`/`30%`) for BOTH
occupied and empty dots. Per direct question ("the grey and muted grey
dots... is it a color token issue or how do gnome original do it") --
yes, a real token issue: double-dimming an already-whatever-hue-that-
theme-uses foreground color, instead of using `Color.muted`, the design
system's own dedicated token specifically for "present but de-
emphasized" content that every theme already tunes for readable-but-
calm contrast against its own background. Now: `Color.accent` (focused),
`Color.foreground` at `85%` (occupied -- real content, should read
clearly), `Color.muted` at `70%` (genuinely empty). Verified via
screenshot -- occupied and empty dots now read as two clearly distinct
shades instead of both looking like the same washed-out grey.

Sizing (`dotSize`/`pillWidth`/`itemSpacing`/`sidePadding`): started at
`8`/`20`/`6`/none, grown to `11`/`30`/`9`/`8` per direct follow-up ("a
bit compact... bigger fat bar and some side padding to the start and
end") -- `sidePadding` is real breathing room baked into this widget's
own `implicitWidth` now, not just relying on `ruixen-bar`'s own
`workspacesPill` outer inset.

Click target is deliberately much bigger than the dot itself
(`anchors.margins: -6` on the `MouseArea`, same pattern used throughout
this project's other small-icon click targets) -- an `8px` dot alone
would be a genuinely hard target to hit precisely.

## Verified

- **No QML errors**: checked `log.qslog` directly after enabling, clean.
- **Correct rendering**: screenshotted the live bar -- teal accent pill on
  the focused workspace, dim dots on the rest, matching the real GNOME/
  Ubuntu reference look being asked for.
- **Genuinely live, not just correct at startup**: ran
  `hyprctl dispatch 'hl.dsp.focus({ workspace = "3" })'` directly in the
  terminal -- the exact same dispatch command a real click on workspace 3
  would trigger -- *without restarting the shell*, and screenshotted
  again: the accent pill smoothly animated over to the 3rd position, on
  its own. This also proves the click-to-focus dispatch mechanism itself
  is correct, even though an actual mouse click couldn't be simulated in
  this environment (documented limitation elsewhere in this project's
  history). Restored workspace 1 after.

## Companion setup

- **[`ruixen-bar`](https://github.com/gitcoder89431/ruixen-bar)** -- see
  its own README for the exact `shell.json` layout swap
  (`omarchy.workspaces` -> `ruixen.workspaces`) this plugin replaces.

## Install (local dev)

```bash
cp manifest.json Workspaces.qml ~/.config/omarchy/plugins/ruixen.workspaces/
omarchy plugin validate ~/.config/omarchy/plugins/ruixen.workspaces
omarchy plugin enable ruixen.workspaces
```

Plugin folders can't contain symlinks (the shell's loader rejects them),
so this has to be a real copy, not `ln -s`. See `ruixen-bar`'s own README
for the `shell.json` layout entry swap needed to actually put this in the
bar in place of `omarchy.workspaces`.
