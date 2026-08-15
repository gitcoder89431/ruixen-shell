import QtQuick
import QtQuick.Layouts

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

  function formatTime(seconds) {
    var value = Math.max(0, Math.floor(Number(seconds) || 0))
    var minutes = Math.floor(value / 60)
    var rest = value % 60
    return minutes + ":" + String(rest).padStart(2, "0")
  }

  // Shared "pane" look -- a slightly-lighter-than-notch tonal card, used
  // for every column's own background. Mirrors ambxst's StyledRect
  // variant:"pane" without needing their theming system.
  component Pane: Rectangle {
    radius: 10
    color: Qt.rgba(1, 1, 1, 0.05)
    clip: true
  }

  RowLayout {
    anchors.fill: parent
    spacing: 12

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

      // Quick controls -- 5 toggle-style buttons, static/decorative for
      // now (ambxst's own versions read WiFi/Bluetooth/night-light/etc.
      // services we don't have wired here yet). Glyphs picked to at
      // least gesture at the same 5 concepts (wifi, bluetooth, night
      // light, caffeine/keep-awake, game mode).
      Pane {
        Layout.fillWidth: true
        Layout.preferredHeight: 44

        Row {
          anchors.centerIn: parent
          spacing: 8

          Repeater {
            model: ["󰤨", "󰂯", "󰖨", "󰛊", "󰊴"]

            Rectangle {
              required property string modelData
              width: 32
              height: 32
              radius: 8
              color: Qt.rgba(1, 1, 1, 0.06)

              Text {
                anchors.centerIn: parent
                text: parent.modelData
                color: root.textColor
                font.family: root.fontFamily
                font.pixelSize: 13
              }
            }
          }
        }
      }

      // Calendar -- genuinely functional (plain Date math, no backend
      // needed), unlike everything else in this file. Prev/next month
      // arrows work; today's cell is highlighted.
      Pane {
        id: calendarPane
        Layout.fillWidth: true
        Layout.fillHeight: true

        property int monthShift: 0
        readonly property date viewingDate: {
          var base = new Date()
          return new Date(base.getFullYear(), base.getMonth() + monthShift, 1)
        }
        readonly property date today: new Date()

        // Monday-first 6x7 grid, padded with leading/trailing days from
        // the adjacent months so every week row stays full.
        readonly property var weeks: {
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
          for (var r = 0; r < cells.length; r += 7) rows.push(cells.slice(r, r + 7))
          return rows
        }

        ColumnLayout {
          id: calendarColumn
          anchors.fill: parent
          anchors.margins: 8
          spacing: 6

          RowLayout {
            Layout.fillWidth: true
            spacing: 4

            Text {
              Layout.fillWidth: true
              text: calendarPane.viewingDate.toLocaleDateString(Qt.locale(), "MMMM yyyy")
              color: root.textColor
              font.family: root.fontFamily
              font.pixelSize: 11
              font.bold: true
            }

            Text {
              text: "󰅁"
              color: root.textColor
              font.family: root.fontFamily
              font.pixelSize: 11
              MouseArea {
                anchors.fill: parent
                anchors.margins: -4
                cursorShape: Qt.PointingHandCursor
                onClicked: calendarPane.monthShift -= 1
              }
            }

            Text {
              text: "󰅂"
              color: root.textColor
              font.family: root.fontFamily
              font.pixelSize: 11
              MouseArea {
                anchors.fill: parent
                anchors.margins: -4
                cursorShape: Qt.PointingHandCursor
                onClicked: calendarPane.monthShift += 1
              }
            }
          }

          Row {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignHCenter
            spacing: 2

            Repeater {
              model: ["M", "T", "W", "T", "F", "S", "S"]
              Text {
                required property string modelData
                width: 20
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

            Row {
              required property var modelData
              Layout.alignment: Qt.AlignHCenter
              spacing: 2

              Repeater {
                model: parent.modelData

                Rectangle {
                  required property var modelData
                  width: 20
                  height: 20
                  radius: 10
                  color: modelData.isToday ? root.accent : "transparent"

                  Text {
                    anchors.centerIn: parent
                    text: modelData.day
                    color: modelData.isToday ? "#000000" : (modelData.inMonth ? root.textColor : root.muted)
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

    // ---- Column 3: notification history (static placeholder) --------
    Pane {
      Layout.fillWidth: true
      Layout.fillHeight: true

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 8

        Text {
          text: "Notifications"
          color: root.textColor
          font.family: root.fontFamily
          font.pixelSize: 11
          font.bold: true
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
      spacing: 10

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
