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
// section header itself becomes "CPUs" (was "System"), and holds
// aggregate CPU then GPU rows instead of ambxst's mixed CPU/RAM/GPU/
// Disk list -- "we can get this from fastfetch" for the identity
// fields, confirmed fastfetch (`--format json -s Host:CPU:GPU`) gives
// exactly the hardware name, CPU model, and GPU name needed, not
// guessed. (Per-core CPU rows were tried and then dropped -- once the
// aggregate CPU row existed they were redundant and added real per-
// tick cost, see this file's own git history/README for that
// round-trip.)
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
  property real packageTemp: -1

  // GPU -- per direct follow-up: per-core CPU rows were "kinda in the
  // way" once the aggregate CPU row already covered the overview, and
  // were "taking some time to load" too (a Repeater + two extra
  // per-core parse loops on every 2s tick), so dropped entirely in
  // favor of showing the GPU next, right after the aggregate CPU row.
  property string gpuName: ""
  property real gpuUsage: 0
  property real gpuFreqMhz: 0
  property var prevGpuSample: null

  function refreshIdentity() {
    if (!identityProc.running) identityProc.running = true
    if (!versionProc.running) versionProc.running = true
  }

  onActiveChanged: if (active) refreshIdentity()

  // Hardware/PC name + CPU model + GPU name -- fastfetch's real Host,
  // CPU, and GPU modules, confirmed by running `fastfetch --format
  // json -s Host:CPU:GPU` on this machine directly ("NucBoxG5" /
  // "Intel(R) N97" / vendor "Intel" + name "UHD Graphics"), not
  // guessed.
  Process {
    id: identityProc
    command: ["fastfetch", "--format", "json", "-s", "Host:CPU:GPU"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var data = JSON.parse(text)
          for (var i = 0; i < data.length; i++) {
            if (data[i].type === "Host") root.hardwareName = data[i].result.name || ""
            if (data[i].type === "CPU") root.cpuModel = data[i].result.cpu || ""
            if (data[i].type === "GPU" && data[i].result.length > 0) {
              var gpu = data[i].result[0]
              root.gpuName = ((gpu.vendor || "") + " " + (gpu.name || "")).trim()
            }
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

  // Aggregate CPU usage -- same delta-of-two-/proc/stat-samples method
  // top/htop use: the bare "cpu " line's idle/total jiffy counts (no
  // trailing digit -- the kernel's own pre-summed aggregate across all
  // cores), compared against the previous sample, gives the real
  // overall usage% since the last poll. No single read can produce a
  // percentage on its own. Per-core parsing dropped per direct
  // follow-up (the per-core rows themselves were removed as redundant
  // once this aggregate existed, and were adding real per-tick cost).
  Process {
    id: statProc
    command: ["cat", "/proc/stat"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var m = String(text || "").match(/^cpu\s+(.*)$/m)
        if (!m) return
        var parts = m[1].trim().split(/\s+/).map(Number)
        var cur = { idle: parts[3] + (parts[4] || 0), total: parts.reduce(function(a, b) { return a + b }, 0) }
        if (root.prevCpuTotal) {
          var tDelta = cur.total - root.prevCpuTotal.total
          var iDelta = cur.idle - root.prevCpuTotal.idle
          root.cpuUsage = tDelta > 0 ? Math.max(0, Math.min(1, 1 - iDelta / tDelta)) : 0
        }
        root.prevCpuTotal = cur
      }
    }
  }

  // Real package (overall CPU) temperature -- lm_sensors' own coretemp
  // driver's "Package id 0" key under coretemp-isa-0000, confirmed by
  // running `sensors -j` on this machine directly, not guessed.
  // fastfetch's own CPU.temperature field is null on this machine, so
  // this is a separate real source. Per-core temps dropped along with
  // the per-core rows themselves.
  Process {
    id: sensorsProc
    command: ["sensors", "-j"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var data = JSON.parse(text)
          var pkgTemp = -1
          for (var chip in data) {
            var fields = data[chip]
            for (var key in fields) {
              if (!/^Package id \d+$/.test(key)) continue
              var reading = fields[key]
              for (var field in reading) {
                if (field.endsWith("_input")) { pkgTemp = reading[field]; break }
              }
            }
          }
          root.packageTemp = pkgTemp
        } catch (e) {}
      }
    }
  }

  // Real GPU usage -- i915 exposes no plain "busy %" file without root
  // (intel_gpu_top needs elevated perf access, not installed here
  // anyway), but its RC6 idle-residency counter is plain-readable and
  // is the standard non-privileged way lightweight monitors derive
  // Intel iGPU usage: busy% = 1 - (Δ time spent idle in RC6 / Δ real
  // wall-clock time) between two samples. Confirmed both sysfs paths
  // are readable directly on this machine, not guessed. gt_act_freq_mhz
  // (current GPU clock) read alongside it for the row's own right-
  // aligned stat, since this iGPU has no distinct thermal zone from
  // the CPU package (fastfetch's GPU.temperature is null here too).
  Process {
    id: gpuProc
    command: ["cat", "/sys/class/drm/card1/power/rc6_residency_ms", "/sys/class/drm/card1/gt_act_freq_mhz"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text || "").trim().split("\n")
        var rc6Ms = Number(lines[0])
        var nowMs = Date.now()
        root.gpuFreqMhz = Number(lines[1]) || 0
        if (root.prevGpuSample) {
          var wallDelta = nowMs - root.prevGpuSample.wallMs
          var rc6Delta = rc6Ms - root.prevGpuSample.rc6Ms
          root.gpuUsage = wallDelta > 0 ? Math.max(0, Math.min(1, 1 - rc6Delta / wallDelta)) : 0
        }
        root.prevGpuSample = { rc6Ms: rc6Ms, wallMs: nowMs }
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
      if (!gpuProc.running) gpuProc.running = true
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

          // GPU row -- goes right after the aggregate CPU row, per
          // direct follow-up ("the cores are taking some time to load
          // too... i think we can just show the GPU next after the
          // aggregate CPU"). Same two-row shape as the CPU row above:
          // row 1 icon + real usage bar + percentage, row 2 GPU name +
          // current clock speed (right-aligned) -- this iGPU has no
          // separate thermal zone from the CPU package, so a real
          // frequency reading stands in for temperature here rather
          // than duplicating the CPU package temp on an unrelated row.
          Column {
            id: gpuAggregate
            width: coreColumn.width
            spacing: 2

            RowLayout {
              width: gpuAggregate.width
              spacing: 8

              Text {
                text: "󰢮"
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
                  width: parent.width * Math.max(0, Math.min(1, root.gpuUsage))
                  height: parent.height
                  radius: 4
                  color: root.accent
                  Behavior on width { NumberAnimation { duration: 200 } }
                }
              }

              Text {
                text: Math.round(root.gpuUsage * 100) + "%"
                font.family: root.fontFamily
                font.pixelSize: 11
                color: root.muted
                Layout.preferredWidth: 32
                horizontalAlignment: Text.AlignRight
              }
            }

            RowLayout {
              width: gpuAggregate.width
              spacing: 8

              Text {
                text: root.gpuName || "GPU"
                font.family: root.fontFamily
                font.pixelSize: 11
                color: root.textColor
                elide: Text.ElideRight
                Layout.fillWidth: true
              }

              Text {
                text: root.gpuFreqMhz > 0 ? Math.round(root.gpuFreqMhz) + " MHz" : ""
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
