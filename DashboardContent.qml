import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Networking
import Quickshell.Bluetooth

// Pure-frontend port of ambxst's WidgetsTab.qml (the actual content of
// their dashboard's default tab -- what most people mean by "the
// ambxst dashboard"). Four columns: player | quick controls + calendar
// | notification history | volume/brightness/mic dials. Deliberately
// NOT wired to real backends beyond what's trivial (the calendar is
// just Date math, genuinely correct) -- everything else here is a
// static visual reference for deciding what's worth actually hooking
// up later. Plain QML primitives throughout (Rectangle/Text/Canvas),
// not ambxst's own StyledRect/Styling/Colors design-token system,
// which doesn't exist in this project.
//
// Source layout reference: quickshell-ambxst/modules/widgets/dashboard/
// widgets/WidgetsTab.qml (their own implicitWidth/Height: 600x750 --
// ours is compressed to fit the notch's 900x344 dashboard size instead
// of a straight port).
Item {
  id: root

  property var shell: null
  property color textColor: "#ffffff"
  property color muted: Qt.rgba(1, 1, 1, 0.5)
  property color accent: "#3ecf5b"
  property string fontFamily: "JetBrainsMono Nerd Font"

  // Media passthrough -- reads the same root-level properties Overlay.qml
  // itself already computes from ruixen.media, just handed down instead
  // of recomputed here.
  property var mediaService: null
  property var activePlayer: null
  property bool hasMedia: false
  property bool isPlaying: false
  property string playIcon: ""
  property string title: ""
  property string artist: ""
  property string artUrl: ""
  property real progressRatio: 0
  property real trackPosition: 0
  property real trackLength: 0
  property string userHost: ""
  property string displayedTitle: ""

  // Quick-controls backends -- wifi/bluetooth are real global Quickshell
  // singletons (not gated behind Omarchy's plugin registry at all);
  // nightlight/idle are Omarchy first-party "service" kind plugins, same
  // shell.firstPartyServiceFor() pattern mediaService above already uses.
  readonly property var bluetoothAdapter: Bluetooth.defaultAdapter
  readonly property var nightlightService: root.shell ? root.shell.firstPartyServiceFor("omarchy.nightlight") : null
  readonly property var idleService: root.shell ? root.shell.firstPartyServiceFor("omarchy.idle") : null

  function formatTime(seconds) {
    var value = Math.max(0, Math.floor(Number(seconds) || 0))
    var minutes = Math.floor(value / 60)
    var rest = value % 60
    return minutes + ":" + String(rest).padStart(2, "0")
  }

  // Shared "pane" look -- OLED-black fill (transparent over the notch's
  // own black background) with a visible grey outline, instead of a
  // filled tonal card. Reads as a thick border framing each column
  // rather than a lighter grey block sitting on black -- per direct
  // feedback that this looked cleaner than the earlier filled version.
  component Pane: Rectangle {
    radius: 10
    color: "transparent"
    border.color: Qt.rgba(1, 1, 1, 0.14)
    border.width: 1.5
    clip: true
  }

  // Quick-control toggle button -- accent-filled with black text/glyph
  // when on (same "primary" treatment the calendar's today-cell and the
  // active tab already use), grey tonal when off. The agent glyph is the
  // one exception left non-interactive (see below) -- active always
  // false, no onActivated wired.
  component QuickToggle: Rectangle {
    id: qt
    property string glyph: ""
    property bool active: false
    signal activated()

    width: 32
    height: 32
    radius: 8
    color: active ? root.accent : Qt.rgba(1, 1, 1, 0.06)
    Behavior on color { ColorAnimation { duration: 120 } }

    Text {
      anchors.centerIn: parent
      text: qt.glyph
      color: qt.active ? "#000000" : root.textColor
      font.family: root.fontFamily
      font.pixelSize: 13
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: qt.activated()
    }
  }

  // Kept as the original filled tonal card -- notifications stays grey
  // per direct feedback, the one column that didn't switch to Pane's
  // black+border look above.
  component PaneFilled: Rectangle {
    radius: 10
    color: Qt.rgba(1, 1, 1, 0.05)
    clip: true
  }

  RowLayout {
    anchors.fill: parent
    // 8px, matching ambxst's own WidgetsTab.qml RowLayout spacing --
    // we were at 12, looser than their real column rhythm.
    spacing: 8

    // ---- Column 1: player -------------------------------------------
    Pane {
      Layout.preferredWidth: 210
      Layout.maximumWidth: 210
      Layout.fillHeight: true

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 8

        Item {
          Layout.preferredWidth: 64
          Layout.preferredHeight: 64
          Layout.alignment: Qt.AlignHCenter
          visible: root.artUrl !== ""

          Rectangle {
            anchors.fill: parent
            radius: 10
            color: "transparent"
            clip: true

            Image {
              anchors.fill: parent
              source: root.artUrl
              sourceSize: Qt.size(128, 128)
              fillMode: Image.PreserveAspectCrop
              asynchronous: true
            }
          }
        }

        Text {
          Layout.fillWidth: true
          text: root.displayedTitle
          color: root.textColor
          font.family: root.fontFamily
          font.pixelSize: 12
          font.bold: true
          horizontalAlignment: Text.AlignHCenter
          elide: Text.ElideRight
        }

        Item { Layout.fillHeight: true }

        // Progress track -- reuses the same dim/accent split as the
        // collapsed and expanded media views, just no wave animation
        // here (static bar, keeps this column simple).
        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: 3
          radius: 1.5
          color: Qt.rgba(1, 1, 1, 0.15)

          Rectangle {
            width: parent.width * root.progressRatio
            height: parent.height
            radius: height / 2
            color: root.hasMedia ? root.accent : root.muted
          }
        }

        Row {
          Layout.fillWidth: true
          Layout.alignment: Qt.AlignHCenter
          spacing: 22

          Text {
            text: "󰒮"
            color: root.textColor
            font.family: root.fontFamily
            font.pixelSize: 14
            MouseArea {
              anchors.fill: parent
              anchors.margins: -6
              cursorShape: Qt.PointingHandCursor
              onClicked: if (root.mediaService) root.mediaService.runAction("previous", false)
            }
          }

          Text {
            text: root.playIcon
            color: root.textColor
            font.family: root.fontFamily
            font.pixelSize: 18
            MouseArea {
              anchors.fill: parent
              anchors.margins: -6
              cursorShape: Qt.PointingHandCursor
              onClicked: if (root.mediaService) root.mediaService.runAction("playPause", false)
            }
          }

          Text {
            text: "󰒭"
            color: root.textColor
            font.family: root.fontFamily
            font.pixelSize: 14
            MouseArea {
              anchors.fill: parent
              anchors.margins: -6
              cursorShape: Qt.PointingHandCursor
              onClicked: if (root.mediaService) root.mediaService.runAction("next", false)
            }
          }
        }
      }
    }

    // ---- Column 2: quick controls + calendar -------------------------
    ColumnLayout {
      Layout.preferredWidth: 220
      Layout.maximumWidth: 220
      Layout.fillHeight: true
      spacing: 8

      // Quick controls -- 5 toggle buttons. 4 are real: wifi/bluetooth
      // are global Quickshell singletons, nightlight/stayawake are
      // Omarchy first-party services (same shell.firstPartyServiceFor
      // pattern mediaService uses). The 5th (Omarchy's own Agents
      // widget glyph, U+F16A3) stays non-interactive -- that widget
      // only declares kinds: ["bar-widget"] in its manifest, no
      // "service" kind, so its `alarming` (>=90% of a rate limit)
      // state isn't reachable via shell.firstPartyServiceFor() here.
      Pane {
        Layout.fillWidth: true
        Layout.preferredHeight: 44

        Row {
          anchors.centerIn: parent
          spacing: 8

          QuickToggle {
            glyph: "󰖩"
            active: Networking.wifiEnabled
            onActivated: Networking.wifiEnabled = !Networking.wifiEnabled
          }

          QuickToggle {
            glyph: "󰂯"
            active: root.bluetoothAdapter ? root.bluetoothAdapter.enabled : false
            // Not adapter.enabled = !adapter.enabled: that writes BlueZ's
            // Powered directly, which nothing persists, so it comes back
            // on at next boot. omarchy-bluetooth-power moves the rfkill
            // soft block instead (same helper omarchy.bluetooth's own
            // panel uses) -- systemd-rfkill restores that across reboots.
            onActivated: {
              if (!root.bluetoothAdapter) return
              Quickshell.execDetached(["omarchy-bluetooth-power", root.bluetoothAdapter.enabled ? "off" : "on"])
            }
          }

          QuickToggle {
            glyph: "󰖨"
            active: root.nightlightService ? root.nightlightService.enabled : false
            onActivated: if (root.nightlightService) root.nightlightService.toggle()
          }

          QuickToggle {
            glyph: "󰛊"
            active: root.idleService ? root.idleService.stayAwake : false
            // setIdleEnabled(current stayAwake value) IS the toggle --
            // see ruixen.stayawake's own StayAwake.qml for the same
            // pattern: stayAwake and idleEnabled are semantic opposites,
            // so passing the about-to-be-old stayAwake value in flips it.
            onActivated: if (root.idleService) root.idleService.setIdleEnabled(active)
          }

          QuickToggle {
            glyph: "󱚣"
          }
        }
      }

      // Calendar -- genuinely functional (plain Date math, no backend
      // needed), unlike everything else in this file. Prev/next month
      // arrows work; today's cell is highlighted.
      //
      // Structure ported literally from ambxst's own Calendar.qml this
      // time (checked directly, not guessed): outer frame is grey
      // ("pane"), with the title text, each chevron, and the whole
      // day-grid as their own separate BLACK ("internalbg") sub-panels
      // nested inside it -- the grey only ever shows as the gutter
      // around/between those black panels, never as a fill behind text
      // itself. The current week row gets a grey ("pane") highlight
      // inside the black day-grid, same as ambxst's currentWeekRow.
      Rectangle {
        id: calendarPane
        Layout.fillWidth: true
        Layout.fillHeight: true
        radius: 10
        color: Qt.rgba(1, 1, 1, 0.08)
        clip: true

        property int monthShift: 0
        readonly property date viewingDate: {
          var base = new Date()
          return new Date(base.getFullYear(), base.getMonth() + monthShift, 1)
        }
        readonly property date today: new Date()

        // Monday-first 6x7 grid, padded with leading/trailing days from
        // the adjacent months so every week row stays full. currentWeekRow
        // mirrors ambxst's own field of the same name -- which row (if
        // any) contains today, -1 when viewing a different month.
        readonly property var calendarData: {
          var first = viewingDate
          var year = first.getFullYear()
          var month = first.getMonth()
          var firstWeekday = (first.getDay() + 6) % 7 // 0=Mon
          var daysInMonth = new Date(year, month + 1, 0).getDate()
          var cells = []
          for (var i = 0; i < firstWeekday; i++) cells.push({ day: "", inMonth: false, isToday: false })
          for (var d = 1; d <= daysInMonth; d++) {
            var isToday = monthShift === 0 && d === today.getDate()
            cells.push({ day: String(d), inMonth: true, isToday: isToday })
          }
          while (cells.length % 7 !== 0) cells.push({ day: "", inMonth: false, isToday: false })
          var rows = []
          var currentWeekRow = -1
          for (var r = 0; r < cells.length; r += 7) {
            var row = cells.slice(r, r + 7)
            if (row.some(function(c) { return c.isToday })) currentWeekRow = rows.length
            rows.push(row)
          }
          return { weeks: rows, currentWeekRow: currentWeekRow }
        }
        readonly property var weeks: calendarData.weeks
        readonly property int currentWeekRow: calendarData.currentWeekRow

        ColumnLayout {
          id: calendarColumn
          anchors.fill: parent
          anchors.margins: 4
          spacing: 4

          // Header row -- title pill fills the remaining width, each
          // chevron is its own fixed-width pill, all black, all the
          // same height. Matches ambxst's titleRect/leftButton/
          // rightButton trio exactly (just without their hover/press
          // accent-color swap).
          RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 22
            Layout.maximumHeight: 22
            spacing: 4

            Rectangle {
              Layout.fillWidth: true
              Layout.fillHeight: true
              radius: 6
              color: "#000000"

              Text {
                anchors.centerIn: parent
                text: calendarPane.viewingDate.toLocaleDateString(Qt.locale(), "MMMM yyyy")
                color: root.textColor
                font.family: root.fontFamily
                font.pixelSize: 11
                font.bold: true
              }
            }

            Rectangle {
              Layout.preferredWidth: 22
              Layout.fillHeight: true
              radius: 6
              color: "#000000"

              Text {
                anchors.centerIn: parent
                text: "󰅁"
                color: root.textColor
                font.family: root.fontFamily
                font.pixelSize: 11
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: calendarPane.monthShift -= 1
              }
            }

            Rectangle {
              Layout.preferredWidth: 22
              Layout.fillHeight: true
              radius: 6
              color: "#000000"

              Text {
                anchors.centerIn: parent
                text: "󰅂"
                color: root.textColor
                font.family: root.fontFamily
                font.pixelSize: 11
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: calendarPane.monthShift += 1
              }
            }
          }

          // Day-grid -- one black sub-panel holding the weekday labels
          // and all 6 week rows, matching ambxst's own second
          // "internalbg" StyledRect.
          Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 6
            color: "#000000"

            ColumnLayout {
              anchors.fill: parent
              anchors.margins: 6
              spacing: 2

              // Weekday labels and every week row below both use
              // RowLayout with 7 fillWidth columns now, instead of a
              // plain Row of fixed-20px cells centered in the panel --
              // the fixed-width version left big empty gutters on both
              // sides once the day-grid panel became as wide as the
              // rest of this card (looked like the calendar itself was
              // "skinny" inside a wider black panel).
              RowLayout {
                Layout.fillWidth: true
                spacing: 2

                Repeater {
                  model: ["M", "T", "W", "T", "F", "S", "S"]
                  Text {
                    required property string modelData
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: modelData
                    color: root.muted
                    font.family: root.fontFamily
                    font.pixelSize: 9
                  }
                }
              }

              Repeater {
                model: calendarPane.weeks

                Rectangle {
                  required property var modelData
                  required property int index
                  Layout.fillWidth: true
                  Layout.preferredHeight: 20
                  radius: 8
                  color: index === calendarPane.currentWeekRow ? Qt.rgba(1, 1, 1, 0.08) : "transparent"

                  RowLayout {
                    anchors.fill: parent
                    spacing: 2

                    Repeater {
                      model: parent.parent.modelData

                      // fillWidth on the column keeps all 7 days evenly
                      // spread across the full row width; the "today"
                      // highlight stays a fixed 20x20 circle centered
                      // inside its (now wider) column instead of
                      // stretching into an ellipse.
                      Item {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        Rectangle {
                          anchors.centerIn: parent
                          width: 20
                          height: 20
                          radius: 10
                          color: parent.modelData.isToday ? root.accent : "transparent"

                          Text {
                            anchors.centerIn: parent
                            text: parent.parent.modelData.day
                            color: parent.parent.modelData.isToday ? "#000000" : (parent.parent.modelData.inMonth ? root.textColor : root.muted)
                            font.family: root.fontFamily
                            font.pixelSize: 9
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }

    // ---- Column 3: notification history (static placeholder) --------
    PaneFilled {
      Layout.fillWidth: true
      Layout.fillHeight: true

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10
        // Trimmed independently of the other 3 sides -- the header row
        // (title/bell/broom) sat too far from the card's own top edge.
        anchors.topMargin: 6
        spacing: 8

        RowLayout {
          Layout.fillWidth: true
          // 32px, matching ambxst's own header RowLayout
          // (Layout.maximumHeight: 32 in NotificationHistory.qml) --
          // we were at 26, visibly smaller than their real proportions.
          Layout.preferredHeight: 32
          Layout.maximumHeight: 32
          spacing: 6

          // Fills the remaining width instead of hugging the text --
          // matches ambxst's own titleRect (Layout.fillWidth: true
          // inside the same header RowLayout), not a snug-fit pill.
          Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: height / 2
            color: "#000000"

            Text {
              anchors.centerIn: parent
              text: "Notifications"
              color: root.textColor
              font.family: root.fontFamily
              font.pixelSize: 14
              font.bold: true
            }
          }

          // DND bell -- decorative for now, mirrors the collapsed
          // notch's own bell glyph. Not wired to omarchy.notifications
          // here (ruixen.dnd already owns that toggle, see the bar).
          Rectangle {
            Layout.preferredWidth: 32
            Layout.fillHeight: true
            radius: height / 2
            color: "#000000"

            Text {
              anchors.centerIn: parent
              text: "󰂛"
              color: root.textColor
              font.family: root.fontFamily
              font.pixelSize: 16
            }
          }

          // Clear-all "broom" -- ambxst's own NotificationHistory.qml
          // header has the same bell + broom pair. Decorative, no real
          // history to clear yet.
          Rectangle {
            Layout.preferredWidth: 32
            Layout.fillHeight: true
            radius: height / 2
            color: "#000000"

            Text {
              anchors.centerIn: parent
              text: "󰃢"
              color: root.textColor
              font.family: root.fontFamily
              font.pixelSize: 16
            }
          }
        }

        // No real history service wired here yet -- this is the "does
        // it fit, does it look right" placeholder ambxst's own
        // NotificationHistory.qml occupies.
        Item {
          Layout.fillWidth: true
          Layout.fillHeight: true

          Text {
            anchors.centerIn: parent
            text: "No notifications"
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: 10
          }
        }
      }
    }

    // ---- Column 4: volume / brightness / mic dials (static) ---------
    ColumnLayout {
      Layout.preferredWidth: 70
      Layout.maximumWidth: 70
      Layout.fillHeight: true
      // 8px, matching ambxst's own circular-controls column spacing.
      spacing: 8

      component Dial: Item {
        property string glyph: ""
        property real value: 0.7
        Layout.preferredWidth: 48
        Layout.preferredHeight: 48
        Layout.alignment: Qt.AlignHCenter

        Canvas {
          anchors.fill: parent
          onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            var cx = width / 2, cy = height / 2, r = width / 2 - 3
            ctx.lineWidth = 3
            ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.15)
            ctx.beginPath()
            ctx.arc(cx, cy, r, 0, Math.PI * 2)
            ctx.stroke()
            ctx.strokeStyle = root.accent
            ctx.beginPath()
            ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + value * Math.PI * 2)
            ctx.stroke()
          }
        }

        Text {
          anchors.centerIn: parent
          text: parent.glyph
          color: root.textColor
          font.family: root.fontFamily
          font.pixelSize: 14
        }
      }

      Item { Layout.fillHeight: true }
      Dial { glyph: "󰕾"; value: 0.65 }
      Dial { glyph: "󰍬"; value: 0.4 }
      Dial { glyph: "󰃟"; value: 0.8 }
      Item { Layout.fillHeight: true }
    }
  }
}
