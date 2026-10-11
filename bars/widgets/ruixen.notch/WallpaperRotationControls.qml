import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import Quickshell
import Quickshell.Io

Rectangle {
  id: root
  property bool active: false
  property bool expanded: false
  property bool available: false
  property color accent: "#3ecf5b"
  property color textColor: "white"
  property color muted: "#999999"
  readonly property color hintColor:Qt.rgba(textColor.r,textColor.g,textColor.b,.7)
  property string fontFamily: "JetBrainsMono Nerd Font"
  property var settings: ({})
  property string pending: ""
  visible: available
  implicitHeight: expanded ? content.implicitHeight + 20 : 50
  color: Qt.rgba(textColor.r,textColor.g,textColor.b,.05)
  radius: 12
  border.width: 0
  function refresh() { if(active && !probe.running) probe.running=true }
  function change(key,value) {
    settings=Object.assign({},settings,{[key]:value})
    pending=JSON.stringify({enabled:settings.enabled === true, shuffle:settings.shuffle === true, folder:settings.folder, intervalMinutes:settings.intervalMinutes})
    debounce.restart()
  }
  function send() {
    if (writer.running || !pending) return
    writer.command=["omarchy-shell","ruixen-wallpaper-rotation","configure",pending]
    pending=""
    writer.running=true
  }
  onActiveChanged: refresh()
  Component.onCompleted: refresh()
  Timer { id: debounce; interval: 200; onTriggered: root.send() }
  Timer { interval: 1000; running: root.active && root.expanded; repeat: true; onTriggered: root.refresh() }
  Process {
    id: probe
    command: ["omarchy-shell","ruixen-wallpaper-rotation","status"]
    stdout: StdioCollector {
      waitForEnd:true
      onStreamFinished: {
        if(root.pending || writer.running || (folderInput.activeFocus || intervalInput.activeFocus)) return
        try { root.settings=JSON.parse(text); root.available=true } catch(e) { root.available=false }
      }
    }
  }
  Process { id: writer; onExited: (code,status) => { if(root.pending) debounce.restart(); else root.refresh() } }
  Process { id: advance; command:["omarchy-shell","ruixen-wallpaper-rotation","next"]; onExited: root.refresh() }
  ColumnLayout {
    id: content
    anchors.left: parent.left; anchors.right: parent.right; anchors.top: parent.top
    anchors.margins: 10
    spacing: 8
    WallpaperSectionHeader {
      Layout.fillWidth: true
      title: "Artwork rotation"
      glyph: "\uf021"
      summary: root.settings.paused ? "Paused for video" : root.settings.enabled ? (root.settings.shuffle ? "Shuffle · " : "") + "Every " + root.settings.intervalMinutes + " min" : "Off"
      expanded: root.expanded
      accent: root.accent; textColor: root.textColor; muted: root.hintColor; fontFamily: root.fontFamily
      onClicked: root.expanded = !root.expanded
    }
    ColumnLayout {
      visible: root.expanded
      Layout.fillWidth: true
      spacing: 8
      RowLayout {
        Layout.fillWidth: true
        WallpaperToggle {
          text: "Rotate artwork"; checked: root.settings.enabled === true
          accent: root.accent; textColor: root.textColor; font.family: root.fontFamily
          onClicked: root.change("enabled", checked)
        }
        WallpaperToggle {
          text: "Shuffle"; checked: root.settings.shuffle === true
          accent: root.accent; textColor: root.textColor; font.family: root.fontFamily
          onClicked: root.change("shuffle", checked)
        }
        Item { Layout.fillWidth: true }
        WallpaperAction {
          text: "Next artwork  →"
          primary: true
          accent: root.accent; textColor: root.textColor; font.family: root.fontFamily
          enabled: !root.settings.paused && !advance.running && !writer.running && !root.pending
          onClicked: advance.running = true
        }
      }
      RowLayout {
        Layout.fillWidth: true
        Text { text: "Interval"; color: root.hintColor; font.family: root.fontFamily; font.pixelSize: 11; Layout.preferredWidth: 70 }
        Repeater {
          model: [5, 15, 30, 60]
          WallpaperAction {
            required property int modelData
            text: modelData + " min"
            selected: root.settings.intervalMinutes === modelData
            accent: root.accent; textColor: root.textColor; font.family: root.fontFamily
            onClicked: root.change("intervalMinutes", modelData)
          }
        }
        Item { Layout.fillWidth: true }
        WallpaperField {
          id: intervalInput
          Layout.preferredWidth: 65
          text: String(root.settings.intervalMinutes || 15)
          validator: IntValidator { bottom: 1; top: 1440 }
          inputMethodHints: Qt.ImhDigitsOnly
          accent: root.accent; textColor: root.textColor; font.family: root.fontFamily
          onEditingFinished: if (acceptableInput && Number(text) !== root.settings.intervalMinutes) root.change("intervalMinutes", Number(text))
        }
        Text { text: "min"; color: root.hintColor; font.family: root.fontFamily; font.pixelSize: 11 }
      }
      RowLayout {
        Layout.fillWidth: true
        Text { text: "Artwork folder"; color: root.hintColor; font.family: root.fontFamily; font.pixelSize: 11; Layout.preferredWidth: 110 }
        WallpaperField {
          id: folderInput
          Layout.fillWidth: true
          text: root.settings.folder || ""
          placeholderText: "~/Pictures/ruixen-wallpapers"
          accent: root.accent; textColor: root.textColor; font.family: root.fontFamily
          onEditingFinished: if (text !== root.settings.folder) root.change("folder", text)
        }
      }
      Text {
        Layout.fillWidth: true
        text: root.settings.error || (root.settings.paused ? "Rotation resumes after video/GIF playback." : (root.settings.shuffle ? "Images play randomly without immediate repeats." : "Images play in filename order.") + " Video and GIF playback pauses rotation.")
        color: root.settings.error ? "#ff8080" : root.hintColor
        font.family: root.fontFamily; font.pixelSize: 10
        wrapMode: Text.Wrap
      }
    }
  }
}
