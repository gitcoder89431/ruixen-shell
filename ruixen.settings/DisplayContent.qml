import QtQuick
import QtQuick.Layouts

// Display -- real brightness slider, ported directly
// from ruixen-notch's own proven mechanism (see the
// brightnessPercent/setBrightness block above) rather
// than reading Omarchy's own Panel.qml, per direct
// request ("can we do a display one too, the omarchy one
// has it, looks pretty simple?").
ColumnLayout {
  id: root

  property var settingsRoot: null

  spacing: 16


  // Brightness -- own card, same treatment (radius: 10,
  // color: "#000000") as every other section's groups
  // (Output/Input, Known/Available Networks, Paired/
  // Available Devices), and the same content-driven
  // height as Audio's own Output/Input cards. Dropped
  // the old "No controllable display found" empty state
  // entirely per direct follow-up -- it was never a
  // coherent thing to show in the first place: if there
  // really were no display, there'd be no way to see
  // this settings panel to read that message on.
  Rectangle {
    visible: settingsRoot.brightnessAvailable
    Layout.fillWidth: true
    Layout.preferredHeight: brightnessCardContent.implicitHeight + 24
    radius: 10
    color: "#000000"

    ColumnLayout {
      id: brightnessCardContent
      anchors.fill: parent
      anchors.margins: 12
      spacing: 12

      Text {
        text: "Brightness"
        font.family: settingsRoot.fontFamily
        font.pixelSize: 11
        font.weight: Font.DemiBold
        color: settingsRoot.muted
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: 10

        Text {
          text: ""
          font.family: settingsRoot.fontFamily
          font.pixelSize: 15
          color: settingsRoot.textColor
        }

        // Same track/fill/tip language as ruixen.notch's own sliders
        // (the dashboard's vertical brightness bar, the collapsed
        // notch's horizontal wave slider) -- direct request ("can we
        // use the same design as from the notch, no waves, but it can
        // have a tip or head"). No WavyLine here (this isn't a media
        // position, nothing to animate) -- just the plain solid fill
        // half of that same design, ported from the vertical
        // brightness bar's own gap+tip treatment since it already has
        // no wave either, just flipped horizontal.
        Rectangle {
          id: brightnessBarTrack
          Layout.fillWidth: true
          Layout.preferredHeight: 6
          radius: 3
          color: "transparent"

          readonly property real value: Math.max(0, Math.min(1, settingsRoot.brightnessPercent / 100))
          // Point along the bar the tip sits centered on -- track and
          // fill both stop short of it by gapPx, same split-point
          // convention as the wave slider's splitX.
          readonly property real valueX: width * value
          // Half the bar's own thickness (3) + half the tip's own
          // width (2) + 2px real clearance -- same derivation the wave
          // slider's own gapPx used, not a flat guess.
          readonly property real gapPx: 7

          Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: Math.max(0, parent.valueX - parent.gapPx)
            radius: 3
            color: settingsRoot.accent
            Behavior on width { NumberAnimation { duration: 120 } }
          }

          Rectangle {
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: Math.max(0, parent.width - parent.valueX - parent.gapPx)
            radius: 3
            color: Qt.rgba(1, 1, 1, 0.1)
          }

          // Tip -- sticks out past the bar's own top/bottom edges,
          // same "reads clearer than the bar alone" reasoning as the
          // vertical brightness bar and wave slider's own playhead.
          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            x: parent.valueX - width / 2
            width: 4
            height: parent.height + 8
            radius: 2
            color: "#ffffff"
            Behavior on x { NumberAnimation { duration: 120 } }
          }

          MouseArea {
            anchors.fill: parent
            anchors.topMargin: -8
            anchors.bottomMargin: -8
            onPressed: mouse => settingsRoot.setBrightness(100 * mouse.x / width)
            onPositionChanged: mouse => { if (pressed) settingsRoot.setBrightness(100 * mouse.x / width) }
          }
        }

        Text {
          text: Math.round(settingsRoot.brightnessPercent) + "%"
          font.family: settingsRoot.fontFamily
          font.pixelSize: 12
          color: settingsRoot.muted
          Layout.preferredWidth: 32
          horizontalAlignment: Text.AlignRight
        }
      }
    }
  }

  // Display Scale -- own card.
  Rectangle {
    visible: settingsRoot.brightnessAvailable
    Layout.fillWidth: true
    Layout.preferredHeight: scaleCardContent.implicitHeight + 24
    radius: 10
    color: "#000000"

    ColumnLayout {
      id: scaleCardContent
      anchors.fill: parent
      anchors.margins: 12
      spacing: 12

      Text {
        text: "Display Scale"
        font.family: settingsRoot.fontFamily
        font.pixelSize: 11
        font.weight: Font.DemiBold
        color: settingsRoot.muted
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: 6

        Repeater {
          model: settingsRoot.scalePresets

          Rectangle {
            id: scaleBtn
            required property string modelData
            readonly property bool isCurrent: settingsRoot.displayScale === scaleBtn.modelData

            Layout.fillWidth: true
            Layout.preferredHeight: 28
            radius: 6
            color: scaleBtn.isCurrent ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
            border.width: 1
            border.color: scaleBtn.isCurrent ? settingsRoot.accent : Qt.rgba(1, 1, 1, 0.12)

            Text {
              anchors.centerIn: parent
              text: scaleBtn.modelData + "x"
              font.family: settingsRoot.fontFamily
              font.pixelSize: 11
              font.weight: scaleBtn.isCurrent ? Font.DemiBold : Font.Normal
              color: scaleBtn.isCurrent ? settingsRoot.textColor : settingsRoot.muted
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: settingsRoot.setDisplayScale(scaleBtn.modelData)
            }
          }
        }
      }
    }
  }

  // Absorbs all leftover vertical space, exactly like
  // Audio's own trailing spacer (and like the fillHeight
  // Flickable that Wi-Fi/Bluetooth/Plugins each have).
  // This is what actually fixed the long-standing gap
  // between the Brightness and Display Scale cards: this
  // page column is fillHeight, so when active it's
  // stretched to the full panel height, but neither card
  // can grow (both fixed-size, fillHeight defaults false).
  // Qt's layout engine does NOT leave that surplus at the
  // bottom -- with nothing able to consume it, it spreads
  // the children apart instead, which reads as a gap
  // between the two cards. Audio never showed the same
  // symptom because this spacer eats 100% of the surplus,
  // not because its content happened to be taller.
  // No more trailing fillHeight spacer -- direct follow-up ("nothing
  // is sticky... everything in the page scroll"): this page's own
  // ColumnLayout is naturally sized inside Settings.qml's shared
  // Flickable now, not a fixed-height container to absorb leftover
  // space in, so this sink has nothing left to do.
}
