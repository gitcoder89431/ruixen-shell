import QtQuick
import QtQuick.Layouts

// Audio -- real Pipewire volume + output/input device
// pickers, per direct request ("should we start with the
// audio then... volume + output device picker", then
// "does it also shows the input? the omarchy has it
// showing"). Wi-Fi/Bluetooth stay on the generic
// placeholder below until their own real backends land.
ColumnLayout {
  id: root

  property var settingsRoot: null

  spacing: 16


  Rectangle {
    // Groups the whole Output/Input section (label +
    // slider + device list) into one card, same real
    // shape as the header pill (radius: 10, color:
    // "#000000") -- direct follow-up ("still feels a bit
    // off, can we try nesting few things like the black
    // card too Output and Input group"). Height tracks
    // the inner content's own implicitHeight (12px margin
    // top/bottom) instead of a fixed number, so it still
    // fits correctly as the device list grows/shrinks.
    Layout.fillWidth: true
    Layout.preferredHeight: outputCardContent.implicitHeight + 24
    radius: 10
    color: "#000000"

    ColumnLayout {
      id: outputCardContent
      anchors.fill: parent
      anchors.margins: 12
      spacing: 12

      Text {
        text: "Output"
        font.family: settingsRoot.fontFamily
        font.pixelSize: 11
        font.weight: Font.DemiBold
        color: settingsRoot.muted
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: 10

        Text {
          text: settingsRoot.outputMuted ? "" : ""
          font.family: settingsRoot.fontFamily
          font.pixelSize: 15
          color: settingsRoot.textColor

          MouseArea {
            anchors.fill: parent
            anchors.margins: -6
            cursorShape: Qt.PointingHandCursor
            onClicked: settingsRoot.toggleOutputMute()
          }
        }

        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: 6
          radius: 3
          color: Qt.rgba(1, 1, 1, 0.1)

          Rectangle {
            width: parent.width * Math.max(0, Math.min(1, settingsRoot.outputVolume))
            height: parent.height
            radius: 3
            color: settingsRoot.outputMuted ? settingsRoot.muted : settingsRoot.accent
            Behavior on width { NumberAnimation { duration: 120 } }
          }

          MouseArea {
            anchors.fill: parent
            anchors.topMargin: -8
            anchors.bottomMargin: -8
            onPressed: mouse => settingsRoot.setOutputVolume(mouse.x / width)
            onPositionChanged: mouse => { if (pressed) settingsRoot.setOutputVolume(mouse.x / width) }
            // Scroll to adjust -- direct request ("allow
            // the middle button to add or lower the
            // volume... when hovering it too"). 5% per
            // notch, same clamp the click/drag handlers
            // above already apply.
            onWheel: wheel => settingsRoot.setOutputVolume(Math.max(0, Math.min(1, settingsRoot.outputVolume + (wheel.angleDelta.y > 0 ? 0.05 : -0.05))))
          }
        }

        Text {
          text: Math.round(settingsRoot.outputVolume * 100) + "%"
          font.family: settingsRoot.fontFamily
          font.pixelSize: 12
          color: settingsRoot.muted
          Layout.preferredWidth: 32
          horizontalAlignment: Text.AlignRight
        }
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: 4

        Repeater {
          model: settingsRoot.outputDevices

          Rectangle {
            id: deviceRow
            required property var modelData
            readonly property bool isDefault: settingsRoot.outputSink && deviceRow.modelData && settingsRoot.outputSink.id === deviceRow.modelData.id

            Layout.fillWidth: true
            Layout.preferredHeight: 32
            radius: 8
            color: deviceRow.isDefault ? Qt.rgba(1, 1, 1, 0.08) : "transparent"

            RowLayout {
              anchors.fill: parent
              anchors.leftMargin: 8
              anchors.rightMargin: 8
              spacing: 8

              Text {
                text: ""
                font.family: settingsRoot.fontFamily
                font.pixelSize: 13
                color: deviceRow.isDefault ? settingsRoot.accent : settingsRoot.muted
              }

              Text {
                text: settingsRoot.deviceLabel(deviceRow.modelData)
                font.family: settingsRoot.fontFamily
                font.pixelSize: 12
                font.weight: deviceRow.isDefault ? Font.DemiBold : Font.Normal
                color: deviceRow.isDefault ? settingsRoot.textColor : settingsRoot.muted
                elide: Text.ElideRight
                Layout.fillWidth: true
              }
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: settingsRoot.setDefaultOutput(deviceRow.modelData)
            }
          }
        }
      }
    }
  }


  Rectangle {
    // Groups the whole Output/Input section (label +
    // slider + device list) into one card, same real
    // shape as the header pill (radius: 10, color:
    // "#000000") -- direct follow-up ("still feels a bit
    // off, can we try nesting few things like the black
    // card too Output and Input group"). Height tracks
    // the inner content's own implicitHeight (12px margin
    // top/bottom) instead of a fixed number, so it still
    // fits correctly as the device list grows/shrinks.
    Layout.fillWidth: true
    Layout.preferredHeight: inputCardContent.implicitHeight + 24
    radius: 10
    color: "#000000"

    ColumnLayout {
      id: inputCardContent
      anchors.fill: parent
      anchors.margins: 12
      spacing: 12

      Text {
        text: "Input"
        font.family: settingsRoot.fontFamily
        font.pixelSize: 11
        font.weight: Font.DemiBold
        color: settingsRoot.muted
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: 10

        Text {
          text: settingsRoot.inputMuted ? "" : ""
          font.family: settingsRoot.fontFamily
          font.pixelSize: 15
          color: settingsRoot.textColor

          MouseArea {
            anchors.fill: parent
            anchors.margins: -6
            cursorShape: Qt.PointingHandCursor
            onClicked: settingsRoot.toggleInputMute()
          }
        }

        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: 6
          radius: 3
          color: Qt.rgba(1, 1, 1, 0.1)

          Rectangle {
            width: parent.width * Math.max(0, Math.min(1, settingsRoot.inputVolume))
            height: parent.height
            radius: 3
            color: settingsRoot.inputMuted ? settingsRoot.muted : settingsRoot.accent
            Behavior on width { NumberAnimation { duration: 120 } }
          }

          MouseArea {
            anchors.fill: parent
            anchors.topMargin: -8
            anchors.bottomMargin: -8
            onPressed: mouse => settingsRoot.setInputVolume(mouse.x / width)
            onPositionChanged: mouse => { if (pressed) settingsRoot.setInputVolume(mouse.x / width) }
            // Scroll to adjust -- same real reasoning and
            // step as Output's own slider above.
            onWheel: wheel => settingsRoot.setInputVolume(Math.max(0, Math.min(1, settingsRoot.inputVolume + (wheel.angleDelta.y > 0 ? 0.05 : -0.05))))
          }
        }

        Text {
          text: Math.round(settingsRoot.inputVolume * 100) + "%"
          font.family: settingsRoot.fontFamily
          font.pixelSize: 12
          color: settingsRoot.muted
          Layout.preferredWidth: 32
          horizontalAlignment: Text.AlignRight
        }
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: 4

        Repeater {
          model: settingsRoot.inputDevices

          Rectangle {
            id: inputRow
            required property var modelData
            readonly property bool isDefault: settingsRoot.inputSource && inputRow.modelData && settingsRoot.inputSource.id === inputRow.modelData.id

            Layout.fillWidth: true
            Layout.preferredHeight: 32
            radius: 8
            color: inputRow.isDefault ? Qt.rgba(1, 1, 1, 0.08) : "transparent"

            RowLayout {
              anchors.fill: parent
              anchors.leftMargin: 8
              anchors.rightMargin: 8
              spacing: 8

              Text {
                text: ""
                font.family: settingsRoot.fontFamily
                font.pixelSize: 13
                color: inputRow.isDefault ? settingsRoot.accent : settingsRoot.muted
              }

              Text {
                text: settingsRoot.deviceLabel(inputRow.modelData)
                font.family: settingsRoot.fontFamily
                font.pixelSize: 12
                font.weight: inputRow.isDefault ? Font.DemiBold : Font.Normal
                color: inputRow.isDefault ? settingsRoot.textColor : settingsRoot.muted
                elide: Text.ElideRight
                Layout.fillWidth: true
              }
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: settingsRoot.setDefaultInput(inputRow.modelData)
            }
          }
        }
      }
    }
  }


  // No more trailing fillHeight spacer -- direct follow-up ("nothing
  // is sticky... everything in the page scroll"): this page's own
  // ColumnLayout is naturally sized inside Settings.qml's shared
  // Flickable now, not a fixed-height container to absorb leftover
  // space in, so this sink has nothing left to do.
}
