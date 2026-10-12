import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io

Rectangle {
  id: root
  property string kind: ""
  property bool active: false
  property color textColor: "white"
  property color accent: "#8aadf4"
  property string fontFamily: "monospace"
  property var rows: []
  property var summaries: []
  property bool relativeBars: false
  readonly property real largestShare: rows.reduce(function (value, row) {
    return Math.max(value, row.fraction || 0);
  }, 0)
  readonly property bool resourcePage: ["cpu", "memory", "gpu"].indexOf(kind) >= 0
  property string note: ""
  property string errorText: ""
  property string checkedAt: ""
  property string requestedKind: ""
  property int generation: 0
  property int requestedGeneration: -1
  property string queuedKind: ""
  signal back
  visible: kind !== ""
  color: "transparent"
  function refresh() {
    if (!active || !visible)
      return;
    if (reader.running) {
      queuedKind = kind;
      return;
    }
    requestedKind = kind;
    requestedGeneration = generation;
    reader.command = ["python3", decodeURIComponent(Qt.resolvedUrl("metric-details.py").toString().replace(/^file:\/\//, "")), kind];
    reader.running = true;
  }
  onKindChanged: {
    generation++;
    relativeBars = false;
    rows = [];
    summaries = [];
    note = "";
    errorText = "";
    checkedAt = "";
    queuedKind = "";
    Qt.callLater(refresh);
  }
  onActiveChanged: if (active)
    Qt.callLater(refresh)
  Timer {
    interval: 3000
    repeat: true
    running: root.active && root.visible
    onTriggered: root.refresh()
  }
  Process {
    id: reader
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (!root.active || root.kind !== root.requestedKind || root.generation !== root.requestedGeneration)
          return;
        try {
          var result = JSON.parse(text);
          root.rows = result.rows || [];
          root.summaries = result.summaries || [];
          root.note = result.note || "";
          root.errorText = result.error || "";
          root.checkedAt = Qt.formatTime(new Date(), "hh:mm:ss");
        } catch (e) {
          root.errorText = "Unable to read system details";
        }
      }
    }
    onExited: (code, status) => {
      if (code !== 0 && root.active && root.kind === root.requestedKind && root.generation === root.requestedGeneration)
        root.errorText = "Details helper failed";
      if (root.queuedKind) {
        root.queuedKind = "";
        root.refresh();
      }
    }
  }
  component DetailAction: Button {
    font.family: root.fontFamily
    font.pixelSize: 11
    padding: 8
    contentItem: Text {
      text: parent.text
      font: parent.font
      color: root.accent
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
    }
    background: Rectangle {
      radius: 6
      color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, parent.hovered || parent.activeFocus ? .2 : .1)
    }
  }
  ColumnLayout {
    anchors.fill: parent
    spacing: 12
    RowLayout {
      Layout.fillWidth: true
      DetailAction {
        text: "‹ Back"
        onClicked: root.back()
        Accessible.name: "Back to metrics overview"
      }
      Text {
        text: root.kind.toUpperCase() + " details"
        color: root.accent
        font.family: root.fontFamily
        font.pixelSize: 16
        Layout.fillWidth: true
      }
      Text {
        text: root.checkedAt ? "Updated " + root.checkedAt : "Loading…"
        color: root.textColor
        opacity: .65
        font.pixelSize: 11
      }
      DetailAction {
        visible: root.resourcePage
        text: root.relativeBars ? "Bars: compare" : "Bars: capacity"
        onClicked: root.relativeBars = !root.relativeBars
      }
      DetailAction {
        text: "Refresh"
        onClicked: root.refresh()
      }
    }
    Text {
      text: root.errorText || (root.note + (root.resourcePage && root.relativeBars ? " Process bars scale to the largest shown; labels show actual usage." : ""))
      color: root.errorText ? "#ff8080" : root.textColor
      opacity: .8
      wrapMode: Text.Wrap
      Layout.fillWidth: true
      font.pixelSize: 11
    }
    RowLayout {
      visible: root.summaries.length > 0
      Layout.fillWidth: true
      spacing: 8
      Repeater {
        model: root.summaries
        Rectangle {
          required property var modelData
          Layout.fillWidth: true
          Layout.preferredHeight: summaryContent.implicitHeight + 16
          radius: 8
          color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, .1)
          ColumnLayout {
            id: summaryContent
            anchors.fill: parent
            anchors.margins: 8
            spacing: 6
            RowLayout {
              Layout.fillWidth: true
              Text {
                text: modelData.label
                color: root.textColor
                font.family: root.fontFamily
                font.pixelSize: 11
                Layout.fillWidth: true
                elide: Text.ElideRight
              }
              Text {
                text: modelData.value
                color: root.accent
                font.family: root.fontFamily
                font.pixelSize: 18
                font.bold: true
              }
            }
            Rectangle {
              Layout.fillWidth: true
              Layout.preferredHeight: 5
              radius: 2
              color: Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, .1)
              Rectangle {
                width: parent.width * Math.max(0, Math.min(1, modelData.fraction))
                height: parent.height
                radius: 2
                color: root.accent
              }
            }
            Text {
              visible: !!modelData.detail
              text: modelData.detail || ""
              color: root.textColor
              opacity: .75
              font.family: root.fontFamily
              font.pixelSize: 10
              Layout.fillWidth: true
              wrapMode: Text.Wrap
            }
          }
        }
      }
    }
    ScrollView {
      Layout.fillWidth: true
      Layout.fillHeight: true
      clip: true
      contentWidth: availableWidth
      ScrollBar.vertical.policy: ScrollBar.AsNeeded
      Column {
        width: parent.width
        spacing: 4
        Repeater {
          model: root.rows
          Rectangle {
            required property var modelData
            required property int index
            readonly property bool hasBar: modelData.fraction !== undefined && modelData.fraction !== null
            width: parent.width
            height: modelData.detail ? 60 : (hasBar ? 42 : 34)
            radius: 6
            color: Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, .05)
            ColumnLayout {
              anchors.fill: parent
              anchors.margins: 8
              spacing: 4
              RowLayout {
                Layout.fillWidth: true
                spacing: 16
                Text {
                  text: (modelData.detail || modelData.fraction !== undefined ? (index + 1) + ". " : "") + modelData.label
                  color: root.textColor
                  font.family: root.fontFamily
                  font.pixelSize: 12
                  Layout.fillWidth: true
                  elide: Text.ElideRight
                }
                Text {
                  text: modelData.value
                  color: root.accent
                  font.family: root.fontFamily
                  font.pixelSize: 12
                  font.bold: true
                  Layout.maximumWidth: root.width * .6
                  horizontalAlignment: Text.AlignRight
                  elide: Text.ElideRight
                }
              }
              Text {
                visible: !!modelData.detail
                text: modelData.detail || ""
                color: root.textColor
                opacity: .65
                font.family: root.fontFamily
                font.pixelSize: 10
                Layout.fillWidth: true
                elide: Text.ElideRight
              }
              Rectangle {
                visible: parent.parent.hasBar
                Layout.fillWidth: true
                Layout.preferredHeight: 5
                radius: 2
                color: Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, .08)
                Rectangle {
                  width: parent.width * Math.max(0, Math.min(1, (modelData.fraction || 0) / (root.relativeBars ? (root.largestShare || 1) : 1)))
                  height: parent.height
                  radius: 2
                  color: root.accent
                }
              }
            }
          }
        }
      }
    }
  }
}
