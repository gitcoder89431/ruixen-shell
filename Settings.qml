import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons

// Ruixen Settings -- standalone center-panel settings app. First plugin
// in the "ruixen apps" family (settings/launcher/AI chat/notepad, per
// direct request): meant to carry the same dark card look and radii as
// ruixen.notch's own stat tiles, but as its own independent plugin --
// no dependency on ruixen.bar or ruixen.notch, works if someone installs
// only this one. `qs.Commons` (the Color singleton used here) is part of
// the Omarchy shell runtime itself, not a ruixen-specific dependency, so
// pulling real theme tokens from it doesn't break that independence.
//
// Contract matches Omarchy's own built-in overlay plugins (confirmed by
// reading $OMARCHY_PATH/shell/plugins/emojis/Emojis.qml directly, not
// guessed): root exposes `shell`/`manifest` (injected by the host),
// open()/close()/toggle()/dismiss(), and an internal PanelWindow whose
// `visible` follows `root.opened`. `dismiss()` calls `shell.hide(id)` so
// the host's own toggle bookkeeping (`omarchy-shell shell toggle
// ruixen.settings`) stays in sync with an in-panel close/Escape too.
Item {
  id: root
  property var shell: null
  property var manifest: null

  property bool opened: false

  // Same theme-aware-with-safety-net treatment as ruixen.notch/ruixen.bar
  // (see Overlay.qml's own themeForeground comment for the full
  // reasoning) -- this panel is meant to read as OLED-dark on every
  // theme, so fall back to a fixed light color only when a theme's own
  // foreground would be unreadably dark against that.
  readonly property color themeForeground: Color.bar.text
  readonly property real themeForegroundLuminance: 0.299 * themeForeground.r + 0.587 * themeForeground.g + 0.114 * themeForeground.b
  readonly property color safeForeground: "#e8e8e8"
  readonly property color textColor: themeForegroundLuminance > 0.45 ? themeForeground : safeForeground
  readonly property color muted: Qt.rgba(textColor.r, textColor.g, textColor.b, 0.5)
  readonly property color accent: Color.accent

  // Real menu-surface tokens (Color.menu.*) for the panel chrome itself
  // -- same tokens Omarchy's own built-in modal-style overlays (Emojis,
  // the root menu) use, so this panel's card/border/scrim stay
  // theme-correct instead of a hardcoded black that could clash with a
  // light theme.
  readonly property color panelBackground: Color.menu.background
  readonly property color panelBorder: Color.menu.border
  readonly property color scrim: Color.menu.scrim

  readonly property string fontFamily: "JetBrainsMono Nerd Font"

  function open() {
    root.opened = true
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "ruixen.settings")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open()
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; left: true; right: true; bottom: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.namespace: "ruixen-settings"
    WlrLayershell.layer: WlrLayer.Overlay
    // Exclusive -- Escape needs to reach this surface to close it, same
    // as Emojis' own search-box overlay.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    // Backdrop -- click anywhere outside the card to dismiss, same
    // pattern as any modal.
    Rectangle {
      anchors.fill: parent
      color: root.scrim

      MouseArea {
        anchors.fill: parent
        onClicked: root.dismiss()
      }
    }

    Rectangle {
      id: card
      anchors.centerIn: parent
      width: 480
      height: 360
      radius: 16
      color: root.panelBackground
      border.width: 1
      border.color: root.panelBorder
      focus: root.opened

      Keys.onEscapePressed: root.dismiss()

      // Swallow clicks so they don't fall through to the backdrop's own
      // dismiss handler.
      MouseArea {
        anchors.fill: parent
        onClicked: {}
      }

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12

        RowLayout {
          Layout.fillWidth: true
          spacing: 8

          Text {
            text: ""
            font.family: root.fontFamily
            font.pixelSize: 16
            color: root.accent
          }

          Text {
            text: "Settings"
            font.family: root.fontFamily
            font.pixelSize: 15
            font.weight: Font.DemiBold
            color: root.textColor
            Layout.fillWidth: true
          }

          Text {
            text: ""
            font.family: root.fontFamily
            font.pixelSize: 14
            color: root.muted

            MouseArea {
              anchors.fill: parent
              anchors.margins: -6
              cursorShape: Qt.PointingHandCursor
              onClicked: root.dismiss()
            }
          }
        }

        Rectangle { Layout.preferredHeight: 1; Layout.fillWidth: true; color: root.muted }

        // Placeholder -- real sections (appearance, notifications,
        // about, etc.) land in a follow-up pass, same "coming soon"
        // stub pattern ruixen.notch's own Metrics/Wallpapers tabs
        // started from before being filled in iteratively.
        Item {
          Layout.fillWidth: true
          Layout.fillHeight: true

          Text {
            anchors.centerIn: parent
            text: "Settings sections coming soon"
            font.family: root.fontFamily
            font.pixelSize: 12
            color: root.muted
          }
        }
      }
    }
  }
}
