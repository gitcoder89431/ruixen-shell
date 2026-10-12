# Lessons from wallpaper development

These lessons came from building and auditing the native renderer, rotation,
and both wallpaper pickers in PR #97. Verification evidence and remaining
coverage limits are in [the audit](WALLPAPER-AUDIT.md).

## Package the runtime with the feature

Controls that rely on a separately installed prototype are difficult to share
and reproduce. Bundle the renderer as an optional plugin, keep existing behavior
as the installation default, and use the host's replacement-plugin lifecycle.
Check for competing enabled replacements before changing state. Test disable
and uninstall restoration as well as enable.

## Test actual input and rendering behavior

Hover previews need explicit entry/exit handling and a reliable active state.
A selected duration must drive the preview animation itself, including zero
duration and changes during playback. Wait for both image textures before
starting; keep the incoming frame visible until the final image is ready.
Exercise these cases live: source inspection and manifest validation cannot
prove that QML compiles or that pointer events reach the intended control.

## Deploy groups of QML changes together

Repeated live file copies coincided with a Quickshell crash during development;
this does not establish its root cause. Stop the host, copy the related files,
and restart it when deploying a group of changes. Check a fresh process and its
journal rather than trusting hot reload to recreate every object.

## Treat paths, state, and late results as boundaries

Encode file URLs and test literal `#` and `%` characters, not only spaces.
Validate JSON types, finite numeric bounds, and schema versions before writing.
Refuse to overwrite future-version state; preserve unrelated keys atomically.
Use generation checks so late folder scans or symlink reads cannot undo a newer
manual selection. Keep scans bounded and outside the UI thread.

## Make visual ownership explicit

Separate transition effects from continuous background effects and expose only
settings relevant to the selected effect. Bound expanded controls with scrolling
so artwork remains reachable. Put media on an explicit layer above the native
background and pause rotation and ambient work during playback; plugin load
order is not a stacking contract.

## Keep shared assets and attribution verifiable

Separately packaged pickers need their own shader/component assets. Parity tests
prevent those copies drifting. Retain shader sources, compiled assets, upstream
commit provenance, and license notices together when adapting effects.

## Report evidence at the scope measured

Whole-shell CPU and whole-GPU busy readings are preliminary desktop samples,
not isolated renderer costs. A low-frame-rate demo demonstrates appearance,
not production smoothness. Record hardware and sampling conditions, distinguish
local tests from CI, and explicitly list untested multi-display/hotplug cases.
Capture demos on an empty workspace and restore the user's settings afterward.
