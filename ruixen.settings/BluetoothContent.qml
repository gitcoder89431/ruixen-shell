import QtQuick
import QtQuick.Layouts

// Bluetooth -- known/paired devices with connect/disconnect/
// forget, plus an "Other Devices" accordion for pairing a
// brand-new one, same known/other split as Wi-Fi. Simpler
// than Wi-Fi's own version turned out to be: no inline
// password field needed at all -- see the pairing-
// mechanism comment above (btAdapter block) for why.
ColumnLayout {
  id: root

  property var settingsRoot: null

  spacing: 12


  // No more Layout.fillHeight: true here -- direct follow-up ("nothing
  // is sticky... everything in the page scroll"): this page's own
  // ColumnLayout is naturally sized inside Settings.qml's shared
  // Flickable now, not a fixed-height container, so a lone fillHeight
  // child has no real "available leftover space" to fill anymore.
  // Layout.topMargin gives it simple breathing room instead of trying
  // to vertically center it.
  Text {
    visible: settingsRoot.knownBtRows.length === 0 && settingsRoot.otherBtRows.length === 0
    Layout.alignment: Qt.AlignHCenter
    Layout.topMargin: 24
    text: !settingsRoot.btEnabled ? "Turn on Bluetooth to see nearby devices" : "No devices found"
    font.family: settingsRoot.fontFamily
    font.pixelSize: 12
    color: settingsRoot.muted
  }

  // No inner Flickable of its own anymore -- direct follow-up
  // ("should we just scroll with the header too, so put the fade on
  // top and everything in the page scroll, nothing is sticky"): the
  // whole detail panel scrolls as one unit now (see Settings.qml's own
  // Flickable wrapping headerPill + the active page together), so a
  // second, nested Flickable in here would just fight it over scroll
  // gestures. These cards now render at their own natural height, same
  // as every other page.
  ColumnLayout {
      id: btCards
      Layout.fillWidth: true
      visible: settingsRoot.knownBtRows.length > 0 || settingsRoot.otherBtRows.length > 0
      spacing: 12

      // Paired Devices -- same card treatment as Wi-Fi's
      // Known Networks (radius: 10, color: "#000000"),
      // but keeping the label this time per direct
      // follow-up ("i think we needed a Paired Device
      // group") -- unlike Wi-Fi's card, there's no stats
      // block above the list here to make the card's
      // purpose obvious without one.
      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: pairedCardContent.implicitHeight + 24
        radius: 10
        color: "#000000"

        ColumnLayout {
          id: pairedCardContent
          anchors.fill: parent
          anchors.margins: 12
          spacing: 12

          // Accordion, same shape as Available Devices'
          // own header below -- direct follow-up ("put
          // paired device into an accordian too, so it
          // lines up the text nicely with avalable
          // device"): was a plain DemiBold Text before,
          // which didn't line up with the other card's
          // RowLayout-based header (fillWidth text +
          // chevron, own hover tint). Open by default.
          Rectangle {
            id: pairedBtHeader
            Layout.fillWidth: true
            Layout.preferredHeight: 24
            radius: 6
            color: pairedBtHeaderMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent"

            RowLayout {
              anchors.fill: parent
              anchors.leftMargin: 8
              anchors.rightMargin: 8
              spacing: 6

              Text {
                text: "Paired Devices"
                font.family: settingsRoot.fontFamily
                font.pixelSize: 11
                color: settingsRoot.muted
                Layout.fillWidth: true
              }

              Text {
                text: settingsRoot.showPairedBtDevices ? "" : ""
                font.family: settingsRoot.fontFamily
                font.pixelSize: 9
                color: settingsRoot.muted
              }
            }

            MouseArea {
              id: pairedBtHeaderMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: settingsRoot.showPairedBtDevices = !settingsRoot.showPairedBtDevices
            }
          }

          ColumnLayout {
            // visible, not a conditionally-emptied Repeater
            // model -- direct follow-up ("its not
            // collapsing, its just hides the bluetooth
            // stuff i have paired, the collapse and
            // expand doesnt effect the card"): swapping
            // the Repeater's own model to [] didn't shrink
            // the card's own Layout.preferredHeight
            // binding (pairedCardContent.implicitHeight)
            // reliably. Items with visible: false are
            // fully excluded from a Layout's own size
            // calculation (documented Qt Quick Layouts
            // behavior), so toggling visibility on this
            // whole wrapper is the more deterministic way
            // to actually collapse it.
            Layout.fillWidth: true
            visible: settingsRoot.showPairedBtDevices
            spacing: 4

            Repeater {
              model: settingsRoot.knownBtRows

              Rectangle {
                id: btRow
                required property var modelData
                readonly property bool busy: settingsRoot.btBusyAddress === btRow.modelData.address

                Layout.fillWidth: true
                Layout.preferredHeight: 32
                radius: 8
                color: btRow.modelData.connected ? Qt.rgba(1, 1, 1, 0.08)
                  : (btRowMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.04) : "transparent")

                RowLayout {
                // z above btRowMouse below -- same mistake as
                // Wi-Fi's own row above: a z set on an element
                // nested INSIDE this RowLayout (the forget icon
                // further down) only ranks it against OTHER
                // CHILDREN OF THIS ROWLAYOUT -- it has no effect
                // on btRowMouse, which is a sibling of this
                // RowLayout itself, not of anything inside it.
                // Real report: "the trash button to forget
                // doesnt do anything, its trying to connect" --
                // the inner z:1 (still present below) never
                // reached the comparison that mattered.
                z: 1
                  anchors.fill: parent
                  anchors.leftMargin: 8
                  anchors.rightMargin: 8
                  spacing: 8

                  Text {
                    text: ""
                    font.family: settingsRoot.fontFamily
                    font.pixelSize: 13
                    color: btRow.modelData.connected ? settingsRoot.accent : settingsRoot.muted
                  }

                  // Row-wide click still does connect/disconnect
                  // (see btRowMouse below) -- but the "no label
                  // at all, just click the row" version of this
                  // left users with nothing to actually notice:
                  // direct report was "i can only forget it?
                  // theres no reconnect" once the hover-only
                  // forget icon became the only visible thing on
                  // the row. Brought back a real status/hint
                  // label, just not sharing the forget icon's
                  // slot this time (see below) so nothing swaps
                  // away right as you aim a click.
                  Text {
                    text: btRow.modelData.name
                      + (!btRow.modelData.connected && !btRow.modelData.pairedFormally ? "  (unpaired)" : "")
                    font.family: settingsRoot.fontFamily
                    font.pixelSize: 12
                    font.weight: btRow.modelData.connected ? Font.DemiBold : Font.Normal
                    color: btRow.modelData.connected ? settingsRoot.textColor : settingsRoot.muted
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                  }

                  // Icon instead of text -- direct follow-up,
                  // matching the trash icon's own treatment
                  // rather than a text label. Busy state swaps
                  // to a spinner glyph with a running rotation
                  // instead of "Connecting..." text.
                  Text {
                    visible: !btRow.modelData.connected
                    text: btRow.busy ? "" : ""
                    font.family: settingsRoot.fontFamily
                    font.pixelSize: 13
                    color: settingsRoot.muted
                    // rotation is forced to 0 whenever not busy
                    // (see spinAngle below) rather than bound
                    // straight to a RotationAnimation -- that
                    // animation never resets rotation when it
                    // stops, so the plug glyph could land at
                    // whatever crooked angle the spin was mid-
                    // cycle at instead of upright. Real report:
                    // "the plug spin is too much".
                    rotation: btRow.busy ? spinAngle : 0
                    property real spinAngle: 0

                    NumberAnimation on spinAngle {
                      running: btRow.busy
                      loops: Animation.Infinite
                      from: 0
                      to: 360
                      duration: 900
                    }
                  }

                  // Red X -- passive "you can click the row to
                  // disconnect" indicator, not its own click
                  // target (the row itself handles that, same
                  // as Omarchy's own rowMouse.onClicked
                  // branching on isConnected).
                  Text {
                    visible: btRow.modelData.connected
                    text: ""
                    font.family: settingsRoot.fontFamily
                    font.pixelSize: 12
                    color: "#e05252"
                  }

                  // Forget -- its own dedicated slot, excluding
                  // the connected device per direct follow-up
                  // (disconnect first, then forget, rather than
                  // a one-step forget that disconnects as a
                  // side effect -- Omarchy's own panel allows
                  // the one-step version, this one deliberately
                  // doesn't). No longer hover-gated: it used to
                  // swap in over the "Connect" label on hover,
                  // meaning the exact thing you were aiming at
                  // disappeared right as the cursor arrived.
                  // Always shown now (dim by default, same as
                  // Wi-Fi's known-network trash icon), just
                  // brightens on its own hover.
                  Text {
                    // The real fix for forget-clicks getting
                    // swallowed by the row-wide click-to-connect
                    // handler lives on the RowLayout itself above
                    // (z: 1, see its comment) -- z only compares
                    // siblings sharing the same immediate parent,
                    // so a z set here would only rank this
                    // against its OWN RowLayout siblings, never
                    // against btRowMouse below (a sibling of the
                    // whole RowLayout, not of this Text). Real
                    // report this cost: "the trash button to
                    // forget doesnt do anything, its trying to
                    // connect" -- confirmed the CLI itself
                    // (omarchy-bluetooth-device forget) works
                    // fine when run directly, so this was purely
                    // a UI hit-testing bug both times.
                    visible: !btRow.modelData.connected
                    text: ""
                    font.family: settingsRoot.fontFamily
                    font.pixelSize: 13
                    color: btForgetMouse.containsMouse ? "#e05252" : settingsRoot.muted

                    MouseArea {
                      id: btForgetMouse
                      anchors.fill: parent
                      anchors.margins: -4
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: settingsRoot.forgetBtDevice(btRow.modelData)
                    }
                  }
                }

                MouseArea {
                  id: btRowMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: settingsRoot.toggleBtConnection(btRow.modelData)
                }
              }
            }
            Text {
              visible: settingsRoot.showPairedBtDevices && settingsRoot.knownBtRows.length === 0
              text: "No paired devices"
              font.family: settingsRoot.fontFamily
              font.pixelSize: 11
              color: settingsRoot.muted
            }
          }
        }
      }

      // Available Devices -- same rename reasoning as
      // Wi-Fi's own "Other Networks" -> "Available
      // Networks": "Other" only reads sensibly relative
      // to a device you're already paired with.
      Rectangle {
        Layout.fillWidth: true
        visible: settingsRoot.otherBtRows.length > 0
        Layout.preferredHeight: availableCardContent.implicitHeight + 24
        radius: 10
        color: "#000000"

        ColumnLayout {
          id: availableCardContent
          anchors.fill: parent
          anchors.margins: 12
          spacing: 12

          // "Other Devices" -- accordion, open by default,
          // same shape as Wi-Fi's own "Other Networks". No
          // inline password field on click here (see the
          // pairing-mechanism comment above) -- a tap just
          // fires pair+trust+connect via
          // omarchy-bluetooth-device directly.
          Rectangle {
            id: otherBtHeader
            Layout.fillWidth: true
            Layout.preferredHeight: 24
            Layout.topMargin: 4
            radius: 6
            color: otherBtHeaderMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent"
            visible: settingsRoot.otherBtRows.length > 0

            RowLayout {
              anchors.fill: parent
              anchors.leftMargin: 8
              anchors.rightMargin: 8
              spacing: 6

              Text {
                // "Available", not "Other" -- same rename
                // reasoning as Wi-Fi's own "Available
                // Networks" (see the card comment above).
                text: "Available Devices"
                font.family: settingsRoot.fontFamily
                font.pixelSize: 11
                color: settingsRoot.muted
                Layout.fillWidth: true
              }

              Text {
                text: settingsRoot.showOtherBtDevices ? "" : ""
                font.family: settingsRoot.fontFamily
                font.pixelSize: 9
                color: settingsRoot.muted
              }
            }

            MouseArea {
              id: otherBtHeaderMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: settingsRoot.showOtherBtDevices = !settingsRoot.showOtherBtDevices
            }
          }
          ColumnLayout {
            // visible, not a conditionally-emptied
            // Repeater model -- same fix as Paired
            // Devices' own list wrapper above, applied
            // here too for consistency (see its comment).
            Layout.fillWidth: true
            visible: settingsRoot.showOtherBtDevices
            spacing: 4

            Repeater {
              model: settingsRoot.otherBtRows

              Rectangle {
                id: otherBtRow
                required property var modelData
                readonly property bool armed: settingsRoot.btPairArmedAddress === otherBtRow.modelData.address

                Layout.fillWidth: true
                Layout.preferredHeight: otherBtContent.implicitHeight + 16
                radius: 8
                color: otherBtRow.armed ? Qt.rgba(1, 1, 1, 0.06) : "transparent"
                clip: true
                Behavior on Layout.preferredHeight { NumberAnimation { duration: 120 } }

                ColumnLayout {
                  id: otherBtContent
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.top: parent.top
                  anchors.margins: 8
                  spacing: 6

                  RowLayout {
                    id: otherBtHeaderRow
                    Layout.fillWidth: true
                    Layout.preferredHeight: 16
                    spacing: 8

                    Text {
                      text: ""
                      font.family: settingsRoot.fontFamily
                      font.pixelSize: 13
                      color: settingsRoot.muted
                    }

                    Text {
                      text: otherBtRow.modelData.name
                      font.family: settingsRoot.fontFamily
                      font.pixelSize: 12
                      color: settingsRoot.muted
                      elide: Text.ElideRight
                      Layout.fillWidth: true
                    }

                    // Icon instead of text, same treatment as
                    // the known-row connect icon above.
                    Text {
                      readonly property bool busy: settingsRoot.btBusyAddress === otherBtRow.modelData.address
                      // Link icon, not the same plug used for
                      // Connect above -- direct follow-up:
                      // "the reconnect and pair with the plug
                      // looks weird, maybe another one for
                      // pair so its not too many plugs".
                      text: busy ? "" : ""
                      font.family: settingsRoot.fontFamily
                      font.pixelSize: 13
                      color: settingsRoot.muted
                      // Same rotation-reset fix as the known-row
                      // connect icon above -- see its comment.
                      rotation: busy ? spinAngle : 0
                      property real spinAngle: 0

                      NumberAnimation on spinAngle {
                        running: parent.busy
                        loops: Animation.Infinite
                        from: 0
                        to: 360
                        duration: 900
                      }
                    }
                  }

                  // Real confirmation step -- direct report: a
                  // bare single click here used to pair
                  // immediately, no confirmation, and unlike
                  // Wi-Fi (picking a network you already
                  // recognize as yours) a nearby Bluetooth
                  // device can easily belong to someone else in
                  // a shared space. First click arms the row
                  // (see toggleBtConnection); only this explicit
                  // second click actually pairs.
                  Rectangle {
                    visible: otherBtRow.armed
                    Layout.fillWidth: true
                    Layout.preferredHeight: 32
                    radius: 10
                    color: confirmPairMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.06)

                    Text {
                      anchors.centerIn: parent
                      text: "Confirm Pair"
                      font.family: settingsRoot.fontFamily
                      font.pixelSize: 12
                      font.weight: Font.DemiBold
                      color: settingsRoot.textColor
                    }

                    MouseArea {
                      id: confirmPairMouse
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: settingsRoot.confirmPairBtDevice(otherBtRow.modelData)
                    }
                  }
                }

                // Height arithmetic instead of anchoring into
                // otherBtHeaderRow directly -- same fix (and the
                // same reason) as Wi-Fi's own otherRow header
                // MouseArea: a cross-hierarchy anchors.bottom
                // binding into a ColumnLayout child stopped
                // clicks from registering entirely when tried
                // there.
                MouseArea {
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.top: parent.top
                  height: 8 + otherBtHeaderRow.height
                  cursorShape: Qt.PointingHandCursor
                  onClicked: settingsRoot.toggleBtConnection(otherBtRow.modelData)
                }
              }
            }
          }
        }
      }
    }
}
