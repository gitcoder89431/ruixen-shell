import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Ui

// GNOME/Ubuntu-style workspace switcher -- small dots for inactive
// workspaces, the focused one stretching into a wider horizontal pill,
// instead of the real omarchy.workspaces' numbered digits. Per direct
// request ("swap from digits to like the linux kinda one with the dots
// and bar... i think it will look better more softer").
//
// Reads the exact same real data/dispatch mechanism as
// omarchy.workspaces (confirmed by reading that file directly:
// /usr/share/omarchy/shell/plugins/bar/widgets/Workspaces.qml) --
// Quickshell.Hyprland's own workspaces/focusedWorkspace, hyprctl
// dispatch to focus. Own plugin, not an edit to that file, because
// omarchy.workspaces is Omarchy-owned (wiped on every omarchy-update,
// never a customization target per this project's own standing rule) --
// the underlying logic didn't need reinventing, just a different
// rendering of the same state.
BarWidget {
  id: root
  moduleName: "ruixen.workspaces"

  // White-theme-only override for the focused pill (see its own color
  // binding below) -- direct report after shipping that hardcoded
  // everywhere: "i switch backed to aura and the workspace slider is
  // stuck on white now... it should still be accent color from theme
  // except for that white theme." Watches the same plain-slug state
  // file `omarchy theme current` itself reads
  // (~/.local/state/omarchy/current/theme.name), not colors.toml's own
  // mode -- Rose Pine is dark-mode but shares White's own low-contrast-
  // accent-on-black-pill problem, but nothing else reported that one
  // broken yet, so this stays scoped to the one theme actually reported
  // instead of guessing at a second.
  property string themeSlug: "unknown"
  FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme.name"
    watchChanges: true
    printErrors: false
    onLoaded: root.themeSlug = text().trim()
    onLoadFailed: root.themeSlug = "unknown"
    onFileChanged: reload()
  }

  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id) return values[i]
    }
    return null
  }

  // Same padding-to-5 + append-any-higher-active-ones logic as the
  // real widget, verbatim.
  function workspaceIds() {
    var ids = [1, 2, 3, 4, 5]
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      var id = values[i].id
      if (id > 0 && id <= 10 && ids.indexOf(id) === -1) ids.push(id)
    }
    ids.sort(function(left, right) { return left - right })
    return ids
  }

  function focusWorkspace(id) {
    if (!root.bar) return
    root.bar.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"" + id + "\" })"))
  }

  // The one resolved color for "active, or has real content" -- see
  // its own call site's comment for the White-theme override reasoning.
  readonly property color focusedColor: root.themeSlug === "white" ? root.bar.barForeground : Color.accent

  // Dot/pill geometry -- classic GNOME Shell look: small round dots,
  // the focused one stretches into a horizontal capsule instead of
  // just changing color or swapping a glyph.
  // Grown 8->11 / 20->30 / 6->9, plus real side padding added (was
  // relying entirely on Bar.qml's own workspacesPill outer inset) --
  // per direct feedback ("a bit compact... bigger fat bar and some
  // side padding to the start and end").
  readonly property int dotSize: 11
  readonly property int pillWidth: 30
  readonly property int itemSpacing: 9
  readonly property int sidePadding: 8

  implicitWidth: row.implicitWidth + sidePadding * 2
  implicitHeight: row.implicitHeight

  Row {
    id: row
    anchors.centerIn: parent
    spacing: root.itemSpacing

    Repeater {
      model: root.workspaceIds()

      Item {
        id: indicator
        required property int modelData

        readonly property var workspace: root.workspaceById(modelData)
        readonly property bool occupied: workspace !== null && workspace.toplevels.values.length > 0
        readonly property bool focused: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === modelData

        width: focused ? root.pillWidth : root.dotSize
        height: root.dotSize
        anchors.verticalCenter: parent.verticalCenter

        Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

        Rectangle {
          anchors.fill: parent
          radius: height / 2
          // Direct follow-up: "we are using the accent color, and then
          // white and grey for the round one, we dont need that... the
          // accent wide is the active, accent dots can be opened but
          // not focus, and then for the inactive... muted accent" --
          // moved off root.bar.barForeground (a theme-neutral
          // readable-on-this-surface white/grey, see the removed
          // comment below for why that existed) onto the theme's own
          // accent at three strengths instead: full for focused/
          // occupied, a muted (low-alpha) tint for genuinely empty.
          // Checked directly: this design system (Commons/Color.qml)
          // has no "secondary" token at all, only foreground/background/
          // accent/urgent/muted -- a muted accent is the real,
          // theme-tuned answer here, not a guessed-at color nothing
          // actually sets per theme.
          //
          // root.focusedColor (below) is the single resolved color for
          // "this represents the active workspace, or a workspace with
          // real content" -- occupied dots now share it outright rather
          // than their own separate token, so focused/occupied always
          // agree. Still gets its own White-theme-specific override
          // rather than accent everywhere -- Color.accent reads as a
          // muted grey on White specifically (#6e6e6e); everywhere
          // else, accent is each theme's own deliberate "pop" color and
          // should stay exactly that. Empty dots are that SAME resolved
          // color at a low alpha, not a different hue entirely -- keeps
          // all three states reading as one coherent accent family
          // instead of mixing in a theme-neutral grey.
          color: indicator.focused || indicator.occupied
            ? root.focusedColor
            : Qt.rgba(root.focusedColor.r, root.focusedColor.g, root.focusedColor.b, 0.35)
          opacity: indicator.focused ? 1 : (indicator.occupied ? 0.85 : 1)
          Behavior on color { ColorAnimation { duration: 180 } }
          Behavior on opacity { NumberAnimation { duration: 180 } }
        }

        MouseArea {
          anchors.fill: parent
          // Small dots need a much bigger real hit target than their
          // own visual size -- same -N margin pattern used throughout
          // this project's other small-icon click targets.
          anchors.margins: -6
          cursorShape: Qt.PointingHandCursor
          onClicked: root.focusWorkspace(indicator.modelData)
        }
      }
    }
  }
}
