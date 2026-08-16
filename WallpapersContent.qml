import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import Quickshell.Widgets

// Real wallpaper picker for the notch dashboard's own "Wallpapers" tab,
// replacing the "coming soon" stub. Reads from the exact same two
// directories Omarchy's own omarchy-theme-bg-switcher does (confirmed
// by reading that script directly, not guessed):
//   - ~/.local/state/omarchy/current/theme/backgrounds (the active
//     theme's own shipped wallpapers)
//   - ~/.config/omarchy/backgrounds/<theme-name>/ (Omarchy's existing
//     per-theme user-additions folder -- already the real extension
//     point, no custom watcher needed)
// Clicking a tile calls the same real omarchy-theme-bg-set the stock
// picker uses, so it stays byte-for-byte consistent with Super+Ctrl+
// Space's own picker (same symlink write, same live shell notify) --
// this is a second front door onto the same state, not a parallel one.
Item {
  id: root

  property color textColor: "#ffffff"
  property color muted: Qt.rgba(1, 1, 1, 0.5)
  property color accent: "#3ecf5b"
  property string fontFamily: "JetBrainsMono Nerd Font"

  // Only visible/active while the tab itself is on screen -- refresh()
  // is cheap (two quick Processes) but no reason to run it while some
  // other tab is showing.
  property bool active: false

  property var wallpaperPaths: []
  property string currentBackground: ""
  property string searchText: ""

  // Filename substring match, same logic as ambxst's own WallpapersTab
  // filteredWallpapers (ported the rule, not the file -- their version
  // is bound up with per-screen/OLED/tint/scheme state this notch
  // doesn't have).
  readonly property var filteredPaths: {
    if (searchText.length === 0) return wallpaperPaths
    var needle = searchText.toLowerCase()
    return wallpaperPaths.filter(function(path) {
      var fileName = path.substring(path.lastIndexOf("/") + 1).toLowerCase()
      return fileName.indexOf(needle) !== -1
    })
  }

  function refresh() {
    if (!listProc.running) listProc.running = true
    if (!currentProc.running) currentProc.running = true
  }

  onActiveChanged: if (active) refresh()

  // Same directories/extensions omarchy-theme-bg-switcher passes to the
  // stock image-picker overlay -- verified by reading that script
  // directly. Skips its thumbnail-cache indirection (list.sh) since a
  // handful of wallpaper-sized images downscaled via Image.sourceSize
  // is cheap enough on its own, same cost class as the blurred-art
  // backgrounds already loaded elsewhere in this plugin.
  Process {
    id: listProc
    command: ["bash", "-c",
      "theme=$(cat \"$HOME/.local/state/omarchy/current/theme.name\" 2>/dev/null); " +
      "find -L \"$HOME/.local/state/omarchy/current/theme/backgrounds\" \"$HOME/.config/omarchy/backgrounds/$theme\" " +
      "-maxdepth 1 -type f \\( -iname \"*.jpg\" -o -iname \"*.jpeg\" -o -iname \"*.png\" -o -iname \"*.gif\" -o -iname \"*.bmp\" -o -iname \"*.webp\" \\) " +
      "2>/dev/null | sort"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.wallpaperPaths = String(text || "").split("\n").filter(function(line) { return line.length > 0 })
      }
    }
  }

  Process {
    id: currentProc
    command: ["bash", "-c", "readlink -f \"$HOME/.local/state/omarchy/current/background\" 2>/dev/null"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.currentBackground = String(text || "").trim()
    }
  }

  // Same real command the stock Super+Ctrl+Space picker's own selection
  // handler runs -- just symlinks current/background and notifies the
  // live shell, doesn't touch theme colors at all.
  Process {
    id: setProc
    stdout: StdioCollector { waitForEnd: true }
  }

  function select(path) {
    root.currentBackground = path
    setProc.command = ["omarchy-theme-bg-set", path]
    setProc.running = true
  }

  ColumnLayout {
    anchors.fill: parent
    spacing: 10

    // Search row -- plain TextInput + placeholder overlay, matching
    // this plugin's existing self-contained style (no qs.Ui.TextField
    // pulled in here, unlike ruixen.weather's location search -- that
    // one already has qs.Ui available; this plugin deliberately stays
    // on plain QML primitives throughout, see DashboardContent.qml).
    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: 40
      radius: 12
      color: Qt.rgba(1, 1, 1, 0.06)

      TextInput {
        id: searchInput
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        verticalAlignment: TextInput.AlignVCenter
        color: root.textColor
        font.family: root.fontFamily
        font.pixelSize: 12
        clip: true

        onTextChanged: root.searchText = text

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "Search wallpapers..."
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: 12
          visible: searchInput.text.length === 0
        }
      }
    }

    Text {
      Layout.fillWidth: true
      Layout.fillHeight: true
      visible: root.filteredPaths.length === 0
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
      text: root.wallpaperPaths.length === 0 ? "No wallpapers found for this theme" : "No wallpapers match “" + root.searchText + "”"
      color: root.muted
      font.family: root.fontFamily
      font.pixelSize: 12
    }

    Flickable {
      Layout.fillWidth: true
      Layout.fillHeight: true
      visible: root.filteredPaths.length > 0
      contentWidth: width
      contentHeight: grid.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds

      Flow {
        id: grid
        width: parent.width
        spacing: 10

        Repeater {
          model: root.filteredPaths

          // Structural rewrite per direct correction: the previous pass
          // copied ambxst's frame APPEARANCE without their actual
          // rendering structure. Ambxst never animates a border on the
          // image container itself -- the wallpaper image stays
          // geometrically static, and a separate highlight overlay
          // draws above it. Copying the frame onto the SAME
          // ClippingRectangle that holds the image (animated
          // border.width, a permanent Image margin, an idle
          // Behavior-driven fill color) is what caused the reported
          // zoom/flash/lingering-fade symptoms -- each one traced back
          // to the image container's own geometry or render layer
          // changing. Fixed by fully separating them: the image sits in
          // its own static, never-animated container; the ring, inner
          // line, and label are separate sibling overlays with fixed
          // geometry, toggled by plain `visible: tile.hovered` and
          // nothing else -- no Behaviors anywhere in this delegate, so
          // there's no lingering fade after the pointer leaves either.
          Item {
            id: tile
            required property string modelData
            readonly property bool hovered: tileMouse.containsMouse

            width: 160
            height: 100

            // Image container -- always exactly `width`x`height`, no
            // margins, no border, no animated properties at all. This
            // is the ONLY thing visible at rest.
            ClippingRectangle {
              anchors.fill: parent
              radius: 10
              color: "transparent"

              Image {
                anchors.fill: parent
                source: "file://" + tile.modelData
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize: Qt.size(160, 100)
              }
            }

            // Hover decoration only -- a separate overlay sibling, not
            // a property on the image's own container, so it can never
            // affect the image's geometry or force a clip rebuild.
            // Two directly-adjacent bands stacked outside-in: accent
            // ring at the very edge, then the black band starting
            // exactly where the ring ends (anchors.margins here MUST
            // equal the ring's own border.width, 2 -- anything bigger
            // leaves a transparent gap between them that the raw image
            // shows through, reading as a separate floating ring
            // instead of one continuous frame).
            Rectangle {
              anchors.fill: parent
              radius: 10
              color: "transparent"
              border.width: 2
              border.color: root.accent
              visible: tile.hovered
              z: 2

              Rectangle {
                anchors.fill: parent
                anchors.margins: 2
                radius: 8
                color: "transparent"
                border.width: 5
                border.color: "#000000"
              }
            }

            // Filename label -- also a separate overlay sibling, fixed
            // geometry, plain visible toggle.
            Rectangle {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              anchors.margins: 5
              height: 26
              color: Qt.rgba(0, 0, 0, 0.82)
              visible: tile.hovered
              z: 3

              Text {
                anchors.centerIn: parent
                width: parent.width - 12
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: tile.modelData.substring(tile.modelData.lastIndexOf("/") + 1)
                color: root.textColor
                font.family: root.fontFamily
                font.pixelSize: 10
              }
            }

            MouseArea {
              id: tileMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.select(tile.modelData)
              z: 4
            }
          }
        }
      }
    }
  }
}
