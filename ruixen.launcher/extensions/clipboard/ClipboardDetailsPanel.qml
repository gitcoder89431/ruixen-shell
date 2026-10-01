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
        visible: root.entry && (root.entry.type === "text" || root.entry.type === "link")
        radius: 12
        color: Qt.rgba(0, 0, 0, 0.18)
        clip: true

        Text {
          anchors.fill: parent
          anchors.margins: 12
          text: root.entry ? ClipboardHistory.previewText(root.entry.text) : ""
          color: root.textColor
          font.family: root.fontFamily
          font.pixelSize: 12
          lineHeight: 1.15
          wrapMode: Text.Wrap
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

    Row {
      width: parent.width
      spacing: 8

      ClipboardActionButton {
        label: "Paste"
        icon: "\uf0ea"
        textColor: root.textColor
        muted: root.muted
        accent: root.accent
        fontFamily: root.fontFamily
        onClicked: root.pasteRequested()
      }

      ClipboardActionButton {
        label: "Copy"
        icon: "\uf0c5"
        textColor: root.textColor
        muted: root.muted
        accent: root.accent
        fontFamily: root.fontFamily
        onClicked: root.copyRequested()
      }

      ClipboardActionButton {
        label: "Open"
        icon: "\uf35d"
        textColor: root.textColor
        muted: root.muted
        accent: root.accent
        fontFamily: root.fontFamily
        onClicked: root.openRequested()
      }

      ClipboardActionButton {
        visible: root.entry && root.entry.type === "image"
        label: "Path"
        icon: "\uf101"
        textColor: root.textColor
        muted: root.muted
        accent: root.accent
        fontFamily: root.fontFamily
        onClicked: root.pastePathRequested()
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

    Repeater {
      model: root.entry ? (function() {
        var fields = [
          { label: "Type", value: root.entry.kind },
          { label: "Captured", value: root.entry.capturedAt || "Unknown" },
          { label: root.entry.type === "link" ? "URL" : "Mime", value: root.entry.type === "link" ? root.entry.text : (root.entry.mime || "Unknown") }
        ]
        if (root.entry.type === "image") {
          fields.push({ label: "Dimensions", value: root.imageDimensions || "Loading..." })
          fields.push({ label: "Size", value: root.imageSize || "Loading..." })
        } else {
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
    anchors.centerIn: parent
    visible: root.entry === null
    text: "Clipboard history is empty"
    color: root.muted
    font.family: root.fontFamily
    font.pixelSize: 13
  }
}
