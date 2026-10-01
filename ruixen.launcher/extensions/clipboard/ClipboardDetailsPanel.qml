import QtQuick
import Quickshell
import "ClipboardHistory.js" as ClipboardHistory

Rectangle {
  id: root

  property var row: null
  readonly property var entry: row && row.clipboardEntry ? row.clipboardEntry : null
  property string imageDimensions: ""
  property string imageSize: ""
  property color textColor: "#ffffff"
  property color muted: Qt.rgba(1, 1, 1, 0.5)
  property color accent: "#3ecf5b"
  property string fontFamily: "JetBrainsMono Nerd Font"

  signal pasteRequested()
  signal copyRequested()
  signal openRequested()
  signal pastePathRequested()
  signal deleteRequested()

  property bool deleteArmed: false
  property bool filtered: false
  property bool revealed: false
  property string pathStatus: ""
  readonly property bool masked: !!root.entry && root.entry.secret === true && !root.revealed
  readonly property bool isTextual: !!root.entry && root.entry.type !== "image"

  signal revealRequested()

  function characterCount(text) {
    return String(text || "").length
  }

  function wordCount(text) {
    var trimmed = String(text || "").trim()
    return trimmed === "" ? 0 : trimmed.split(/\s+/).length
  }

  color: "transparent"
  radius: 12
  clip: true

  Column {
    anchors.fill: parent
    anchors.leftMargin: 24
    anchors.rightMargin: 24
    spacing: 12
    visible: root.entry !== null

    Item {
      width: parent.width
      height: 210

      Rectangle {
        anchors.fill: parent
        visible: root.isTextual
        radius: 12
        color: Qt.rgba(0, 0, 0, 0.18)
        clip: true

        // Color entries: a large swatch (checkerboard-free; alpha shows
        // the panel through it) above the value text.
        Rectangle {
          visible: !!root.entry && root.entry.subtype === "color"
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: 12
          height: 96
          radius: 8
          color: root.entry && root.entry.swatch ? root.entry.swatch : "transparent"
          border.width: 1
          border.color: Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.2)
        }

        Text {
          anchors.fill: parent
          anchors.margins: 12
          anchors.topMargin: root.entry && root.entry.subtype === "color" ? 120 : 12
          text: !root.entry ? ""
            : root.masked ? ("\u2022".repeat(Math.min(String(root.entry.text).trim().length, 32)) + "\n\nHidden \u2014 Alt+R to reveal")
            : ClipboardHistory.previewText(root.entry.preview || root.entry.text)
          color: root.textColor
          font.family: root.fontFamily
          font.pixelSize: 12
          lineHeight: 1.15
          wrapMode: root.entry && root.entry.subtype === "json" ? Text.NoWrap : Text.Wrap
          elide: Text.ElideRight
        }
      }

      Image {
        anchors.fill: parent
        visible: root.entry && root.entry.type === "image"
        source: root.entry && root.entry.path ? ("file://" + root.entry.path) : ""
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        cache: false
        smooth: true
        sourceSize.width: width
        sourceSize.height: height
      }

      Text {
        anchors.centerIn: parent
        visible: !root.entry
        text: "\uf0ea"
        color: root.muted
        font.family: root.fontFamily
        font.pixelSize: 96
      }
    }

    Text {
      text: "Metadata"
      color: root.muted
      font.family: root.fontFamily
      font.pixelSize: 10
      font.capitalization: Font.AllUppercase
      font.bold: true
    }

    Column {
      width: parent.width
      spacing: 8

      Repeater {
        model: root.entry ? (function() {
          var fields = [
            { label: "Type", value: root.entry.kind },
            { label: "Captured", value: root.entry.capturedAt || "Unknown" }
          ]
          var facts = root.entry.facts || []
          for (var f = 0; f < facts.length; f++) fields.push(facts[f])
          if (root.entry.subtype === "path") fields.push({ label: "Status", value: root.pathStatus || "Checking..." })
          if (root.entry.type === "link") fields.push({ label: "URL", value: root.entry.text })
          else if (root.entry.type === "image") fields.push({ label: "Mime", value: root.entry.mime || "Unknown" })
          if (root.entry.type === "image") {
            fields.push({ label: "Dimensions", value: root.imageDimensions || "Loading..." })
            fields.push({ label: "Size", value: root.imageSize || "Loading..." })
          } else if (!root.entry.secret) {
            fields.push({ label: "Characters", value: String(root.characterCount(root.entry.text)) })
            fields.push({ label: "Words", value: String(root.wordCount(root.entry.text)) })
          }
          return fields
        })() : []

        Item {
          required property var modelData
          required property int index
          width: parent.width
          height: 19

          Rectangle {
            anchors.fill: parent
            anchors.leftMargin: -10
            anchors.rightMargin: -10
            anchors.topMargin: -4
            anchors.bottomMargin: -4
            radius: 4
            color: index % 2 === 0 ? Qt.rgba(0, 0, 0, 0.18) : "transparent"
          }

          Text {
            id: fieldLabel
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: modelData.label
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: 11
            font.capitalization: Font.AllUppercase
          }

          Text {
            anchors.left: fieldLabel.right
            anchors.leftMargin: 12
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideMiddle
            text: modelData.value
            color: root.textColor
            font.family: root.fontFamily
            font.pixelSize: 13
          }
        }
      }
    }

    Text {
      topPadding: 6
      text: "Actions"
      color: root.muted
      font.family: root.fontFamily
      font.pixelSize: 10
      font.capitalization: Font.AllUppercase
      font.bold: true
    }

    Column {
      width: parent.width
      spacing: 8

      ClipboardActionRow {
        striped: true
        label: "Paste"
        icon: "\uf0ea"
        hint: "\u21b5"
        textColor: root.textColor; muted: root.muted; accent: root.accent; fontFamily: root.fontFamily
        onClicked: root.pasteRequested()
      }

      ClipboardActionRow {
        label: "Copy"
        icon: "\uf0c5"
        hint: "Alt+C"
        textColor: root.textColor; muted: root.muted; accent: root.accent; fontFamily: root.fontFamily
        onClicked: root.copyRequested()
      }

      ClipboardActionRow {
        striped: true
        label: "Open"
        icon: "\uf35d"
        hint: "Alt+O"
        textColor: root.textColor; muted: root.muted; accent: root.accent; fontFamily: root.fontFamily
        onClicked: root.openRequested()
      }

      ClipboardActionRow {
        visible: !!root.entry && root.entry.type === "image"
        label: "Paste path"
        icon: "\uf101"
        hint: "Alt+P"
        textColor: root.textColor; muted: root.muted; accent: root.accent; fontFamily: root.fontFamily
        onClicked: root.pastePathRequested()
      }

      ClipboardActionRow {
        visible: !!root.entry && root.entry.secret === true
        label: root.revealed ? "Hide" : "Reveal"
        icon: "\uf06e"
        hint: "Alt+R"
        textColor: root.textColor; muted: root.muted; accent: root.accent; fontFamily: root.fontFamily
        onClicked: root.revealRequested()
      }

      ClipboardActionRow {
        striped: !!root.entry && root.entry.type !== "image"
        danger: true
        label: root.deleteArmed ? "Press again to delete" : "Delete"
        icon: "\uf1f8"
        hint: "Alt+D"
        textColor: root.textColor; muted: root.muted; accent: root.accent; fontFamily: root.fontFamily
        onClicked: root.deleteRequested()
      }
    }
  }

  Text {
    anchors.centerIn: parent
    visible: root.entry === null
    text: root.filtered ? "No matching clipboard entries" : "Clipboard history is empty"
    color: root.muted
    font.family: root.fontFamily
    font.pixelSize: 13
  }
}
