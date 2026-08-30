import QtQuick
import QtQuick.Layouts
import Quickshell.Networking

// Wi-Fi -- real Quickshell.Networking status + network
// list + connect to open/known networks, per direct
// request ("wifi next") and scope confirmation (status +
// list + connect to open/known only, no new-password
// flow yet).
ColumnLayout {
  id: root

  property var settingsRoot: null

  spacing: 12


  // Status row removed -- its own job (icon + SSID/"Not
  // connected"/"Wi-Fi off") is now the collapsed header
  // title above (see the shared title Text's own
  // comment), saving a row per direct follow-up.


  // Real connection stats -- IP/Gateway/Ping -- per direct
  // follow-up ("what about the other stats, the omarchy
  // one has way better. it shows ping ip all that stuff i
  // dont think it shows the % wifi strenght too"). The
  // raw signal % above is gone -- confirmed directly that
  // Omarchy's own header treats signal as a 5-tier bar
  // icon (wifiIconFor() in their Model.js), never a
  // number, so dropping it here actually matches their
  // real behavior, not a guess.
  Flickable {
    Layout.fillWidth: true
    Layout.fillHeight: true
    visible: Networking.wifiEnabled
    contentWidth: width
    contentHeight: wifiCards.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    ColumnLayout {
      id: wifiCards
      width: parent.width
      spacing: 12

      // Known Networks -- direct follow-up ("do we need
      // to group Known Network in its own black card and
      // then Other Networks, we dont have a Known network
      // group"): same card treatment (radius: 10, color:
      // "#000000") as Output/Input and the header pill.
      // No label text here (tried one, direct follow-up
      // said drop it -- "Other Networks" below still has
      // its own since that one's an interactive accordion
      // toggle, not just a group boundary). Connection
      // stats (IP/Gateway/Ping) live inside this card too,
      // above the switcher list, since they describe
      // whichever known network is currently active.
      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: knownCardContent.implicitHeight + 24
        radius: 10
        color: "#000000"

        ColumnLayout {
          id: knownCardContent
          anchors.fill: parent
          anchors.margins: 12
          spacing: 12

          GridLayout {
            Layout.fillWidth: true
            visible: settingsRoot.connectedWifiNetwork !== null
            columns: 2
            columnSpacing: 12
            rowSpacing: 2

            Text {
              text: "IP Address"
              font.family: settingsRoot.fontFamily
              font.pixelSize: 11
              color: settingsRoot.muted
            }
            Text {
              Layout.fillWidth: true
              text: settingsRoot.netInfo.ip || "--"
              font.family: settingsRoot.fontFamily
              font.pixelSize: 11
              color: settingsRoot.textColor
              horizontalAlignment: Text.AlignRight
              elide: Text.ElideLeft
            }

            Text {
              text: "Gateway"
              font.family: settingsRoot.fontFamily
              font.pixelSize: 11
              color: settingsRoot.muted
            }
            Text {
              Layout.fillWidth: true
              text: settingsRoot.netInfo.gateway || "--"
              font.family: settingsRoot.fontFamily
              font.pixelSize: 11
              color: settingsRoot.textColor
              horizontalAlignment: Text.AlignRight
              elide: Text.ElideLeft
            }

            Text {
              text: "Ping"
              font.family: settingsRoot.fontFamily
              font.pixelSize: 11
              color: settingsRoot.muted
            }
            Text {
              Layout.fillWidth: true
              text: settingsRoot.netInfo.internet_ping_ms ? Math.round(parseFloat(settingsRoot.netInfo.internet_ping_ms)) + " ms" : "--"
              font.family: settingsRoot.fontFamily
              font.pixelSize: 11
              color: settingsRoot.textColor
              horizontalAlignment: Text.AlignRight
            }
          }
          ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            Repeater {
              // Known networks only -- per direct follow-up
              // ("it showing all wifi spot available to join and
              // its overflowing... were we gonna show just the
              // one[s] we already connected to so they can
              // switch"). Every scanned nearby AP was the actual
              // overflow cause; this list is meant to be a
              // switcher between networks this device already
              // knows, not a full site-survey. Discovering/
              // joining brand-new networks stays out of scope
              // for this pass either way (no passphrase UI yet).
              model: settingsRoot.knownWifiRows

              Rectangle {
                id: wifiRow
                required property var modelData

                Layout.fillWidth: true
                Layout.preferredHeight: 32
                radius: 8
                color: wifiRow.modelData.connected ? Qt.rgba(1, 1, 1, 0.08) : "transparent"

                RowLayout {
                  // z above wifiRowMouse below -- a z set on an
                  // element nested INSIDE this RowLayout (like the
                  // forget icon further down) only ranks it against
                  // OTHER CHILDREN OF THIS ROWLAYOUT -- it has no
                  // effect on wifiRowMouse, which is a sibling of
                  // this RowLayout itself, not of anything inside
                  // it. z comparisons only happen between items
                  // that share the same immediate parent. Real
                  // report this caused: forget's own z:1 (still
                  // present below) looked like a fix but the click
                  // still landed on wifiRowMouse regardless -- this
                  // is the level that actually needed it.
                  z: 1
                  anchors.fill: parent
                  anchors.leftMargin: 8
                  anchors.rightMargin: 8
                  spacing: 8

                  Text {
                    text: ""
                    font.family: settingsRoot.fontFamily
                    font.pixelSize: 13
                    color: wifiRow.modelData.connected ? settingsRoot.accent : settingsRoot.muted
                  }

                  Text {
                    text: wifiRow.modelData.ssid
                    font.family: settingsRoot.fontFamily
                    font.pixelSize: 12
                    font.weight: wifiRow.modelData.connected ? Font.DemiBold : Font.Normal
                    color: wifiRow.modelData.connected ? settingsRoot.textColor : settingsRoot.muted
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                  }

                  Text {
                    visible: !settingsRoot.isOpenNetwork(wifiRow.modelData.security)
                    text: ""
                    font.family: settingsRoot.fontFamily
                    font.pixelSize: 10
                    color: settingsRoot.muted
                  }

                  // Swaps to a "forget" icon on hover -- direct
                  // follow-up after a couple of test-password
                  // attempts left stray known networks with no way
                  // to remove them short of asking nmcli directly.
                  // Excludes the connected network, same rule
                  // Omarchy's own real panel uses (canForgetNetwork:
                  // known && !connected) -- forgetting the network
                  // you're actively on would disconnect you as a
                  // side effect of what reads like a cleanup click.
                  Text {
                    visible: !(wifiRowMouse.containsMouse && !wifiRow.modelData.connected)
                    text: wifiRow.modelData.signal + "%"
                    font.family: settingsRoot.fontFamily
                    font.pixelSize: 11
                    color: settingsRoot.muted
                    Layout.preferredWidth: 28
                    horizontalAlignment: Text.AlignRight
                  }

                  Text {
                    // The real fix for forget-clicks getting
                    // swallowed by the row-wide click-to-connect
                    // handler lives on the RowLayout itself above
                    // (z: 1, see its comment) -- z only compares
                    // siblings sharing the same immediate parent,
                    // so a z set here would only rank this against
                    // its OWN RowLayout siblings, never against
                    // wifiRowMouse below (a sibling of the whole
                    // RowLayout, not of this Text).
                    visible: wifiRowMouse.containsMouse && !wifiRow.modelData.connected
                    text: ""
                    font.family: settingsRoot.fontFamily
                    font.pixelSize: 13
                    color: forgetMouse.containsMouse ? "#e05252" : settingsRoot.muted
                    Layout.preferredWidth: 28
                    horizontalAlignment: Text.AlignRight

                    MouseArea {
                      id: forgetMouse
                      anchors.fill: parent
                      anchors.margins: -4
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: settingsRoot.forgetWifi(wifiRow.modelData)
                    }
                  }
                }

                MouseArea {
                  id: wifiRowMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: settingsRoot.connectToWifi(wifiRow.modelData)
                }
              }
            }
            Text {
              visible: settingsRoot.knownWifiRows.length === 0
              text: "No known networks"
              font.family: settingsRoot.fontFamily
              font.pixelSize: 11
              color: settingsRoot.muted
            }
          }
        }
      }

      // Other Networks -- same card treatment, own
      // accordion header unchanged (see its own comment).
      Rectangle {
        Layout.fillWidth: true
        visible: settingsRoot.otherWifiRows.length > 0
        Layout.preferredHeight: otherCardContent.implicitHeight + 24
        radius: 10
        color: "#000000"

        ColumnLayout {
          id: otherCardContent
          anchors.fill: parent
          anchors.margins: 12
          spacing: 12

          // "Other Networks" -- accordion, open by default (see
          // showOtherNetworks above). Clicking the header toggles
          // it; chevron rotates to show state. Each row still
          // expands in place for its own password field (see
          // otherRow below) rather than a single shared prompt --
          // that part is unrelated to this collapse/expand and
          // stays exactly as it was.
          Rectangle {
            id: otherNetworksHeader
            Layout.fillWidth: true
            Layout.preferredHeight: 24
            Layout.topMargin: 4
            radius: 6
            color: otherHeaderMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent"
            visible: settingsRoot.otherWifiRows.length > 0

            RowLayout {
              anchors.fill: parent
              anchors.leftMargin: 8
              anchors.rightMargin: 8
              spacing: 6

              Text {
                // "Available", not "Other" -- direct
                // follow-up ("does it show this section
                // when im not connected, should we call it
                // available networks instead"): "Other"
                // only reads sensibly relative to a
                // network you're already on, which breaks
                // down exactly when disconnected -- the
                // one state this section matters most.
                // Internal names (otherWifiRows,
                // showOtherNetworks, etc.) stay as-is,
                // this is just the visible label.
                text: "Available Networks"
                font.family: settingsRoot.fontFamily
                font.pixelSize: 11
                color: settingsRoot.muted
                Layout.fillWidth: true
              }

              Text {
                text: settingsRoot.showOtherNetworks ? "" : ""
                font.family: settingsRoot.fontFamily
                font.pixelSize: 9
                color: settingsRoot.muted
              }
            }

            MouseArea {
              id: otherHeaderMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: settingsRoot.showOtherNetworks = !settingsRoot.showOtherNetworks
            }
          }
          ColumnLayout {
            // visible, not a conditionally-emptied
            // Repeater model -- same fix as Bluetooth's
            // Paired/Available Devices list wrappers (see
            // their comment): a Rectangle's height bound
            // to another Layout's implicitHeight didn't
            // reliably shrink when the model driving it
            // went from populated to [] via a Repeater.
            Layout.fillWidth: true
            visible: settingsRoot.showOtherNetworks
            spacing: 4

            Repeater {
              model: settingsRoot.otherWifiRows

              Rectangle {
                id: otherRow
                required property var modelData
                readonly property bool expanded: settingsRoot.wifiPasswordSsid === otherRow.modelData.ssid

                Layout.fillWidth: true
                Layout.preferredHeight: otherContent.implicitHeight + 16
                radius: 8
                color: otherRow.expanded ? Qt.rgba(1, 1, 1, 0.06) : "transparent"
                clip: true
                Behavior on Layout.preferredHeight { NumberAnimation { duration: 120 } }

                ColumnLayout {
                  id: otherContent
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.top: parent.top
                  anchors.margins: 8
                  spacing: 6

                  RowLayout {
                    id: otherHeaderRow
                    Layout.fillWidth: true
                    Layout.preferredHeight: 16
                    spacing: 8

                    Text {
                      text: ""
                      font.family: settingsRoot.fontFamily
                      font.pixelSize: 13
                      color: settingsRoot.muted
                    }

                    Text {
                      text: otherRow.modelData.ssid
                      font.family: settingsRoot.fontFamily
                      font.pixelSize: 12
                      color: settingsRoot.muted
                      elide: Text.ElideRight
                      Layout.fillWidth: true
                    }

                    Text {
                      visible: !settingsRoot.isOpenNetwork(otherRow.modelData.security)
                      text: ""
                      font.family: settingsRoot.fontFamily
                      font.pixelSize: 10
                      color: settingsRoot.muted
                    }

                    Text {
                      text: otherRow.modelData.signal + "%"
                      font.family: settingsRoot.fontFamily
                      font.pixelSize: 11
                      color: settingsRoot.muted
                      Layout.preferredWidth: 28
                      horizontalAlignment: Text.AlignRight
                    }
                  }

                  // Inline passphrase field -- same plain-primitive
                  // search-box style ruixen.notch's own launcher/
                  // wallpaper search boxes use (Rectangle radius
                  // 12, Qt.rgba(1,1,1,0.06) background, TextInput +
                  // placeholder Text overlay), not a new visual
                  // language. Submit button is icon-only (arrow) on
                  // the right per direct request ("with enter on
                  // the right"), Enter key on the field does the
                  // same thing.
                  RowLayout {
                    visible: otherRow.expanded
                    Layout.fillWidth: true
                    spacing: 6

                    Rectangle {
                      Layout.fillWidth: true
                      Layout.preferredHeight: 32
                      radius: 10
                      color: Qt.rgba(1, 1, 1, 0.06)

                      TextInput {
                        id: wifiPasswordInput
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        verticalAlignment: TextInput.AlignVCenter
                        echoMode: TextInput.Password
                        enabled: !settingsRoot.wifiConnecting
                        color: settingsRoot.textColor
                        font.family: settingsRoot.fontFamily
                        font.pixelSize: 12
                        clip: true
                        focus: otherRow.expanded
                        text: settingsRoot.wifiPasswordAttempt
                        onTextChanged: settingsRoot.wifiPasswordAttempt = text
                        Keys.onPressed: function(event) {
                          if (event.key === Qt.Key_Escape) {
                            settingsRoot.closeWifiPasswordPrompt()
                            event.accepted = true
                          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            settingsRoot.submitWifiPassword()
                            event.accepted = true
                          }
                        }

                        Text {
                          anchors.verticalCenter: parent.verticalCenter
                          text: settingsRoot.wifiConnecting ? "Connecting…" : "Enter password..."
                          color: settingsRoot.muted
                          font.family: settingsRoot.fontFamily
                          font.pixelSize: 12
                          visible: wifiPasswordInput.text.length === 0
                        }
                      }
                    }

                    Rectangle {
                      Layout.preferredWidth: 32
                      Layout.preferredHeight: 32
                      radius: 10
                      color: connectMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.06)
                      opacity: settingsRoot.wifiConnecting ? 0.5 : 1

                      Text {
                        anchors.centerIn: parent
                        text: ""
                        font.family: settingsRoot.fontFamily
                        font.pixelSize: 13
                        color: settingsRoot.textColor
                      }

                      MouseArea {
                        id: connectMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: !settingsRoot.wifiConnecting
                        cursorShape: Qt.PointingHandCursor
                        onClicked: settingsRoot.submitWifiPassword()
                      }
                    }
                  }

                  Text {
                    visible: otherRow.expanded && settingsRoot.wifiConnectError !== ""
                    text: settingsRoot.wifiConnectError
                    font.family: settingsRoot.fontFamily
                    font.pixelSize: 10
                    color: "#e05252"
                    Layout.leftMargin: 4
                  }
                }

                // Stops at the header row's real bottom edge, not
                // the password field below it once expanded -- an
                // anchors.fill MouseArea here would sit on top of
                // (and swallow clicks meant for) the TextInput/
                // submit button once the row grows. Direct follow-
                // up fix: this used to be anchors.top: parent.top +
                // a fixed height approximating otherHeaderRow's
                // size, but otherContent (the header's real parent)
                // has its own 8px top margin the approximation
                // didn't account for -- the hit region sat 8px
                // above where the header actually rendered, so only
                // the text's own top edge was clickable. Tried
                // anchoring directly to otherHeaderRow.bottom next
                // (cross-hierarchy anchor into a ColumnLayout
                // child), but that made clicks stop registering
                // entirely -- reverted to plain height arithmetic
                // instead: otherContent's own top margin (8, see
                // its anchors.margins above) plus the header's live
                // height covers exactly the same region without
                // relying on anchoring into a Layout's internals.
                MouseArea {
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.top: parent.top
                  height: 8 + otherHeaderRow.height
                  cursorShape: Qt.PointingHandCursor
                  onClicked: settingsRoot.connectToWifi(otherRow.modelData)
                }
              }
            }
          }
        }
      }
    }
  }

  Text {
    visible: !Networking.wifiEnabled
    Layout.alignment: Qt.AlignHCenter
    Layout.fillHeight: true
    verticalAlignment: Text.AlignVCenter
    text: "Turn on Wi-Fi to see nearby networks"
    font.family: settingsRoot.fontFamily
    font.pixelSize: 12
    color: settingsRoot.muted
  }
}
