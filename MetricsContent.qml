import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io

// Real "Metrics" dashboard tab, replacing the "coming soon" stub.
// Left panel only for this pass -- per direct request, focus there
// first, the right side (ambxst's own historical usage line chart)
// becomes a grid of per-resource stat tiles in a follow-up, not a
// chart port.
//
// Left panel structure ported from ambxst's real MetricsTab.qml
// (avatar + 3 identity rows, a section-header separator, a scrollable
// resource list below it) but with the identity rows repurposed per
// direct request: row 1 stays Username (same as ambxst, real $USER),
// row 2 keeps ambxst's own "@" prefix but swaps hostname for the
// machine's real hardware/PC name, row 3 swaps the Linux distro name
// for the actual Omarchy version string ("Omarchy 4.0.0-1"). The
// section header itself becomes "CPUs" (was "System"), and holds a
// live per-core usage list instead of ambxst's mixed CPU/RAM/GPU/Disk
// list -- "we can get this from fastfetch" for the identity fields,
// confirmed fastfetch (`--format json -s Host:CPU`) gives exactly the
// hardware name and CPU model needed, not guessed.
Item {
  id: root

  property color textColor: "#ffffff"
  property color muted: Qt.rgba(1, 1, 1, 0.5)
  property color accent: "#3ecf5b"
  property string fontFamily: "JetBrainsMono Nerd Font"

  property bool active: false

  // Real $USER, no process needed -- same source ambxst's own
  // username row reads (Quickshell.env("USER")).
  readonly property string username: {
    var u = Quickshell.env("USER") || "user"
    return u.charAt(0).toUpperCase() + u.slice(1)
  }

  property string hardwareName: ""
  property string omarchyVersion: ""
  property string cpuModel: ""
  property real cpuUsage: 0
  property var prevCpuTotal: null
  property var coreUsages: []
  property var prevCpuTimes: null
  property real packageTemp: -1

  function refreshIdentity() {
    if (!identityProc.running) identityProc.running = true
    if (!versionProc.running) versionProc.running = true
  }

  onActiveChanged: if (active) refreshIdentity()

  // Hardware/PC name + CPU model -- fastfetch's real Host and CPU
  // modules, confirmed by running `fastfetch --format json -s Host:CPU`
  // on this machine directly ("NucBoxG5" / "Intel(R) N97"), not
  // guessed.
  Process {
    id: identityProc
    command: ["fastfetch", "--format", "json", "-s", "Host:CPU"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var data = JSON.parse(text)
          for (var i = 0; i < data.length; i++) {
            if (data[i].type === "Host") root.hardwareName = data[i].result.name || ""
            if (data[i].type === "CPU") root.cpuModel = data[i].result.cpu || ""
          }
        } catch (e) {}
      }
    }
  }

  // The real Omarchy version string ("4.0.0-1") -- same command `omarchy
  // version` prints, more direct/authoritative than reassembling it from
  // fastfetch's OS module (which only has the bare "4.0.0" buildID, not
  // the full pacman package version the user actually wants shown).
  Process {
    id: versionProc
    command: ["omarchy", "version"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.omarchyVersion = String(text || "").trim()
    }
  }

  // Aggregate + per-core CPU usage -- same delta-of-two-/proc/stat-
  // samples method top/htop use: each line's idle/total jiffy counts,
  // compared against the previous sample, gives that core's (or the
  // overall system's) real usage% since the last poll. No single read
  // can produce a percentage on its own. The bare "cpu " line (no
  // trailing digit) is the kernel's own pre-summed aggregate across all
  // cores -- used directly for the overall row instead of averaging
  // the per-core values ourselves, same source top/htop's own overall
  // gauge reads.
  Process {
    id: statProc
    command: ["cat", "/proc/stat"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text || "").split("\n")
        var samples = []
        var total_ = null
        for (var i = 0; i < lines.length; i++) {
          var agg = lines[i].match(/^cpu\s+(.*)$/)
          if (agg) {
            var aggParts = agg[1].trim().split(/\s+/).map(Number)
            total_ = { idle: aggParts[3] + (aggParts[4] || 0), total: aggParts.reduce(function(a, b) { return a + b }, 0) }
            continue
          }
          var m = lines[i].match(/^cpu(\d+)\s+(.*)$/)
          if (!m) continue
          var idx = parseInt(m[1], 10)
          var parts = m[2].trim().split(/\s+/).map(Number)
          var idle = parts[3] + (parts[4] || 0)
          var total = parts.reduce(function(a, b) { return a + b }, 0)
          samples[idx] = { idle: idle, total: total }
        }
        if (root.prevCpuTimes) {
          var usages = []
          for (var j = 0; j < samples.length; j++) {
            var prev = root.prevCpuTimes[j]
            var cur = samples[j]
            if (!prev || !cur) { usages.push(0); continue }
            var totalDelta = cur.total - prev.total
            var idleDelta = cur.idle - prev.idle
            usages.push(totalDelta > 0 ? Math.max(0, Math.min(1, 1 - idleDelta / totalDelta)) : 0)
          }
          root.coreUsages = usages
        }
        root.prevCpuTimes = samples

        if (root.prevCpuTotal && total_) {
          var tDelta = total_.total - root.prevCpuTotal.total
          var iDelta = total_.idle - root.prevCpuTotal.idle
          root.cpuUsage = tDelta > 0 ? Math.max(0, Math.min(1, 1 - iDelta / tDelta)) : 0
        }
        root.prevCpuTotal = total_
      }
    }
  }

  // Real per-core AND package (overall) temperature -- lm_sensors' own
  // coretemp driver ("Core 0".."Core N" plus a "Package id 0" key
  // under coretemp-isa-0000), confirmed by running `sensors -j` on
  // this machine directly, not guessed. fastfetch's own CPU.
  // temperature field is null on this machine (aggregate-only, and not
  // populated here anyway), so this is a separate real source, not
  // something fastfetch already provided.
  property var coreTemps: []

  Process {
    id: sensorsProc
    command: ["sensors", "-j"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var data = JSON.parse(text)
          var temps = []
          var pkgTemp = -1
          for (var chip in data) {
            var fields = data[chip]
            for (var key in fields) {
              var reading = fields[key]
              if (typeof reading !== "object") continue
              var coreMatch = key.match(/^Core (\d+)$/)
              var isPackage = /^Package id \d+$/.test(key)
              if (!coreMatch && !isPackage) continue
              for (var field in reading) {
                if (field.endsWith("_input")) {
                  if (coreMatch) temps[parseInt(coreMatch[1], 10)] = reading[field]
                  else pkgTemp = reading[field]
                  break
                }
              }
            }
          }
          root.coreTemps = temps
          root.packageTemp = pkgTemp
        } catch (e) {}
      }
    }
  }

  Timer {
    interval: 2000
    running: root.active
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      if (!statProc.running) statProc.running = true
      if (!sensorsProc.running) sensorsProc.running = true
    }
  }

  RowLayout {
    anchors.fill: parent
    spacing: 8

    // Left panel -- identity block + per-core CPU list.
    // Layout.fillWidth explicitly false -- ColumnLayout/RowLayout
    // default fillWidth to true even when unset (unlike plain Item/
    // Rectangle, which default it false), so without this the left
    // panel competed with the right panel's own fillWidth:true for
    // space instead of staying fixed at preferredWidth. Real bug: the
    // right panel and everything in it (the "Stat tiles" placeholder)
    // ended up squeezed into a sliver at the very edge, overlapping
    // the CPU list visually.
    ColumnLayout {
      Layout.preferredWidth: 240
      Layout.fillWidth: false
      Layout.fillHeight: true
      spacing: 10

      RowLayout {
        Layout.fillWidth: true
        spacing: 14

        // Avatar -- same gradient-placeholder + ~/.face.icon +
        // circular-mask pattern as the collapsed notch's own
        // UserAvatar (Overlay.qml), just bigger and without that
        // one's click-to-open-dashboard handler (irrelevant here,
        // already inside the open dashboard).
        Item {
          id: avatar
          Layout.preferredWidth: 64
          Layout.preferredHeight: 64

          Rectangle {
            anchors.fill: parent
            radius: width / 2
            gradient: Gradient {
              GradientStop { position: 0.0; color: "#5b6ee8" }
              GradientStop { position: 1.0; color: "#8a4fd6" }
            }
          }

          Image {
            id: avatarImage
            anchors.fill: parent
            source: "file://" + Quickshell.env("HOME") + "/.face.icon"
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            visible: false
          }

          Rectangle {
            id: avatarMask
            anchors.fill: parent
            radius: width / 2
            color: "#ffffff"
            visible: false
            layer.enabled: true
          }

          MultiEffect {
            anchors.fill: parent
            source: avatarImage
            maskEnabled: true
            maskSource: avatarMask
            maskThresholdMin: 0.5
            maskThresholdMax: 1.0
          }
        }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: 4

          RowLayout {
            Layout.fillWidth: true
            spacing: 6
            Text {
              text: ""
              font.family: root.fontFamily
              font.pixelSize: 14
              color: root.accent
            }
            Text {
              Layout.fillWidth: true
              text: root.username
              font.family: root.fontFamily
              font.pixelSize: 13
              color: root.textColor
              elide: Text.ElideRight
            }
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: 6
            Text {
              text: "@"
              font.family: root.fontFamily
              font.pixelSize: 14
              color: root.accent
            }
            Text {
              Layout.fillWidth: true
              text: root.hardwareName || "Hardware"
              font.family: root.fontFamily
              font.pixelSize: 13
              color: root.textColor
              elide: Text.ElideRight
            }
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: 6
            Text {
              text: ""
              font.family: root.fontFamily
              font.pixelSize: 14
              color: root.accent
            }
            Text {
              Layout.fillWidth: true
              text: root.omarchyVersion ? ("Omarchy " + root.omarchyVersion) : "Omarchy"
              font.family: root.fontFamily
              font.pixelSize: 13
              color: root.textColor
              elide: Text.ElideRight
            }
          }
        }
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: 8

        Rectangle { Layout.preferredHeight: 1; Layout.fillWidth: true; color: root.muted }
        Text {
          text: "CPUs"
          font.family: root.fontFamily
          font.pixelSize: 10
          color: root.muted
        }
        Rectangle { Layout.preferredHeight: 1; Layout.fillWidth: true; color: root.muted }
      }

      Flickable {
        Layout.fillWidth: true
        Layout.fillHeight: true
        contentWidth: width
        contentHeight: coreColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: coreColumn
          width: parent.width
          spacing: 8

          // Aggregate CPU row -- goes first, above the per-core list,
          // per direct request ("is there a separate thing for the CPU
          // itself that goes first in the order before the cores?").
          // Same two-row shape as each core below it: row 1 icon + the
          // kernel's own pre-summed overall usage (the bare "cpu " line
          // in /proc/stat, not an average of the per-core values) +
          // percentage; row 2 the real CPU model name (fastfetch) +
          // the real package temperature (sensors' "Package id 0"),
          // right-aligned.
          Column {
            id: cpuAggregate
            width: coreColumn.width
            spacing: 2

            RowLayout {
              width: cpuAggregate.width
              spacing: 8

              Text {
                text: ""
                font.family: root.fontFamily
                font.pixelSize: 13
                color: root.textColor
                Layout.preferredWidth: 18
              }

              Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 14
                radius: 4
                color: Qt.rgba(1, 1, 1, 0.08)

                Rectangle {
                  width: parent.width * Math.max(0, Math.min(1, root.cpuUsage))
                  height: parent.height
                  radius: 4
                  color: root.accent
                  Behavior on width { NumberAnimation { duration: 200 } }
                }
              }

              Text {
                text: Math.round(root.cpuUsage * 100) + "%"
                font.family: root.fontFamily
                font.pixelSize: 11
                color: root.muted
                Layout.preferredWidth: 32
                horizontalAlignment: Text.AlignRight
              }
            }

            RowLayout {
              width: cpuAggregate.width
              spacing: 8

              Text {
                text: root.cpuModel || "CPU"
                font.family: root.fontFamily
                font.pixelSize: 11
                color: root.textColor
                elide: Text.ElideRight
                Layout.fillWidth: true
              }

              Text {
                text: root.packageTemp >= 0 ? Math.round(root.packageTemp) + "\u00b0C" : ""
                font.family: root.fontFamily
                font.pixelSize: 11
                color: root.muted
                horizontalAlignment: Text.AlignRight
              }
            }
          }

          Repeater {
            model: root.coreUsages

            // Two rows per core, matching ambxst's own CPU section
            // shape (a ResourceItem row, then a details row below it)
            // -- per direct request: row 1 is icon + bar + percentage,
            // row 2 is the core's name on the left and its real
            // temperature (from sensorsProc above) right-aligned.
            Column {
              id: coreItem
              required property int index
              required property real modelData
              width: coreColumn.width
              spacing: 2

              readonly property var temp: root.coreTemps[coreItem.index]

              RowLayout {
                width: coreItem.width
                spacing: 8

                Text {
                  text: ""
                  font.family: root.fontFamily
                  font.pixelSize: 13
                  color: root.textColor
                  Layout.preferredWidth: 18
                }

                Rectangle {
                  Layout.fillWidth: true
                  Layout.preferredHeight: 14
                  radius: 4
                  color: Qt.rgba(1, 1, 1, 0.08)

                  Rectangle {
                    width: parent.width * Math.max(0, Math.min(1, coreItem.modelData))
                    height: parent.height
                    radius: 4
                    color: root.accent
                    Behavior on width { NumberAnimation { duration: 200 } }
                  }
                }

                Text {
                  text: Math.round(coreItem.modelData * 100) + "%"
                  font.family: root.fontFamily
                  font.pixelSize: 11
                  color: root.muted
                  Layout.preferredWidth: 32
                  horizontalAlignment: Text.AlignRight
                }
              }

              RowLayout {
                width: coreItem.width
                spacing: 8

                Text {
                  text: "Core " + coreItem.index
                  font.family: root.fontFamily
                  font.pixelSize: 11
                  color: root.textColor
                  Layout.fillWidth: true
                }

                Text {
                  text: coreItem.temp !== undefined ? Math.round(coreItem.temp) + "°C" : ""
                  font.family: root.fontFamily
                  font.pixelSize: 11
                  color: root.muted
                  horizontalAlignment: Text.AlignRight
                }
              }
            }
          }
        }
      }
    }

    // Right panel -- stat tiles (GPU etc.), next up. Placeholder for
    // now, matching this dashboard's existing stub-pane convention.
    Item {
      Layout.fillWidth: true
      Layout.fillHeight: true

      Text {
        anchors.centerIn: parent
        text: "Stat tiles -- coming soon"
        color: root.muted
        font.family: root.fontFamily
        font.pixelSize: 12
      }
    }
  }
}
