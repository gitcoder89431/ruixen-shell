import QtQuick

// Exposes the Notch's own reserved screen-space footprint to other
// Ruixen plugins (currently just ruixen.bar) via Omarchy's own real
// first-party service registry (shell.firstPartyServiceFor) -- the
// same established cross-plugin mechanism ruixen.media's own
// Service.qml already uses for its bar widget, not a new one invented
// here. Direct review finding ("Reserve horizontal space for the
// Notch so bar widgets cannot render underneath it", #28): one source
// of truth for the collapsed Notch width/shoulders/breathing room,
// instead of copying this same 284 + 28 + 28-style arithmetic into
// ruixen.bar's own file where it could silently drift out of sync
// with Overlay.qml's real numbers.
//
// Deliberately scoped to the COLLAPSED baseline only, not Overlay.qml's
// full live bodyWidth (which genuinely varies at runtime: 284
// collapsed, 420 with the launcher open, 900 pinned/dashboard open --
// see notchOuter's own bodyWidth property there). Reflecting THAT
// live value here would need real bidirectional wiring between two
// separately-instantiated plugin entry points (this service and the
// overlay are loaded as two independent components by shell.qml, with
// no natural object reference between them -- confirmed by reading
// shell.qml's own ensureService directly) -- genuinely new
// cross-plugin infrastructure, not a small addition. The issue's own
// "if full overflow UX is out of scope, at minimum clip/constrain at
// the reserved boundary and leave a follow-up hook for a future
// collapse/overflow treatment" explicitly covers scoping to exactly
// this: the always-present collapsed reservation, with live expansion-
// awareness left as a real, named follow-up rather than solved here.
Item {
  id: root

  property var shell: null

  // Mirrors Overlay.qml's own notchOuter.cornerSize exactly -- a
  // literal here, not imported, for the same "no live object
  // reference between separately-instantiated entry points" reason
  // explained above. Comment-documented manual sync, same convention
  // already used for the playGif() poster-hash formula duplicated
  // between ruixen.wallpaper/Service.qml and
  // ruixen.notch/list-wallpapers.sh (#23) -- if Overlay.qml's own
  // cornerSize ever changes, this must change with it.
  readonly property int cornerSize: 28

  // Mirrors Overlay.qml's own notchOuter.bodyWidth's COLLAPSED case
  // specifically (panel.launcherOpen/pinnedOpen both false) -- see
  // this file's own top comment for why the expanded cases aren't
  // reflected here.
  readonly property int collapsedBodyWidth: 284

  // The actual number ruixen.bar consumes: the Notch's full collapsed
  // footprint, corner shoulders included on both sides.
  readonly property int reservedWidth: collapsedBodyWidth + cornerSize * 2

  // Mirrors Overlay.qml's own PanelWindow margins.top (4) and its
  // notchOuter's own COLLAPSED height (44, panel.launcherOpen/
  // pinnedOpen both false) -- see this file's own top comment for why
  // only the collapsed case is reflected here. Same manual-sync
  // convention as cornerSize/collapsedBodyWidth above.
  readonly property int collapsedTopMargin: 4
  readonly property int collapsedHeight: 44

  // Absolute screen Y of the Notch's own collapsed bottom edge --
  // ruixen.bar's own popup-clearance fix (a direct live report:
  // weather/clock's popup opened underneath the Notch in floating
  // mode) needs this to size its own window tall enough that popups
  // anchored off it clear the Notch, without hardcoding this same
  // arithmetic a second time where it could drift out of sync.
  readonly property int collapsedBottomEdge: collapsedTopMargin + collapsedHeight
}
