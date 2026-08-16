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
//
// Per-core rows were briefly swapped out for a GPU row (both didn't
// fit the original plan), then restored -- per direct correction:
// "i still feel like people wanna see the CPU cores if possible, like
// this guys got 16 cores and 1 or 2 cpu... just bring back the CPU
// cores like we had before than we can tile everything else so CPU
// core has its own section like it did." GPU/RAM/Disk now belong in
// the right panel's stat tiles instead (still a stub below), not this
// list -- this section stays CPU-only, aggregate + per-core.
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

  // Right-panel stat tiles -- GPU, memory, network, disk. Only the
  // FIRST detected GPU gets a tile even on multi-GPU machines ("people
  // have more than 1 GPU?" -- yes, a real gap, but one tile is enough
  // for now; a proper multi-GPU layout is follow-up work, not silently
  // guessed at here).
  property string gpuName: ""
  property real gpuUsage: 0
  property var prevGpuSample: null

  property real memUsedPercent: 0
  property real memUsedGB: 0
  property real memTotalGB: 0

  property string netInterface: ""
  property real netRxRate: 0
  property real netTxRate: 0
  property var prevNetSample: null

  // One entry per real, distinct block device (deduped -- btrfs
  // subvolumes like /, /home, /var/log on this machine all share the
  // same underlying /dev/mapper/root, confirmed via `df` directly, not
  // guessed): { name, percent, usedGB, totalGB }.
  property var disks: []

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

  // GPU usage -- same standard non-privileged Intel iGPU method used
  // (and later removed, then needed again for this tile) earlier in
  // this file's history: i915 exposes no plain "busy %" file without
  // root, but RC6 idle-residency compared between two samples against
  // real wall-clock time gives busy% = 1 - (Δrc6 / Δwall). Confirmed
  // directly on this machine, not guessed.
  Process {
    id: gpuProc
    command: ["cat", "/sys/class/drm/card1/power/rc6_residency_ms"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var rc6Ms = Number(String(text || "").trim())
        var nowMs = Date.now()
        if (root.prevGpuSample) {
          var wallDelta = nowMs - root.prevGpuSample.wallMs
          var rc6Delta = rc6Ms - root.prevGpuSample.rc6Ms
          root.gpuUsage = wallDelta > 0 ? Math.max(0, Math.min(1, 1 - rc6Delta / wallDelta)) : 0
        }
        root.prevGpuSample = { rc6Ms: rc6Ms, wallMs: nowMs }
      }
    }
  }

  // Memory -- /proc/meminfo's MemAvailable (not MemFree) is the real
  // "how much could a new process actually get" figure the kernel
  // itself computes (accounts for reclaimable cache/buffers), same
  // value top/htop/free use for their own "used" calculation -- used =
  // total - available, not total - free.
  Process {
    id: memProc
    command: ["cat", "/proc/meminfo"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var t = String(text || "")
        var totalM = t.match(/^MemTotal:\s+(\d+)/m)
        var availM = t.match(/^MemAvailable:\s+(\d+)/m)
        if (!totalM || !availM) return
        var totalKb = Number(totalM[1])
        var availKb = Number(availM[1])
        var usedKb = Math.max(0, totalKb - availKb)
        root.memTotalGB = totalKb / 1024 / 1024
        root.memUsedGB = usedKb / 1024 / 1024
        root.memUsedPercent = totalKb > 0 ? usedKb / totalKb : 0
      }
    }
  }

  // Network -- real default-route interface (`ip route show default`,
  // confirmed "wlp1s0" on this machine, not hardcoded) plus
  // /proc/net/dev's own cumulative RX/TX byte counters, compared
  // between two samples against real wall-clock time for a genuine
  // throughput rate -- same delta-over-time shape as the CPU/GPU calcs
  // above, different counters.
  Process {
    id: netProc
    command: ["sh", "-c", "ip route show default; echo ---; cat /proc/net/dev"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parts = String(text || "").split("---\n")
        var routeLine = parts[0] || ""
        var devText = parts[1] || ""
        var ifaceMatch = routeLine.match(/\bdev\s+(\S+)/)
        var iface = ifaceMatch ? ifaceMatch[1] : ""
        root.netInterface = iface
        if (!iface) return
        var lineMatch = devText.match(new RegExp("^\\s*" + iface + ":\\s*(.*)$", "m"))
        if (!lineMatch) return
        var fields = lineMatch[1].trim().split(/\s+/).map(Number)
        var rxBytes = fields[0]
        var txBytes = fields[8]
        var nowMs = Date.now()
        if (root.prevNetSample) {
          var wallDeltaS = (nowMs - root.prevNetSample.wallMs) / 1000
          if (wallDeltaS > 0) {
            root.netRxRate = Math.max(0, (rxBytes - root.prevNetSample.rxBytes) / wallDeltaS)
            root.netTxRate = Math.max(0, (txBytes - root.prevNetSample.txBytes) / wallDeltaS)
          }
        }
        root.prevNetSample = { rxBytes: rxBytes, txBytes: txBytes, wallMs: nowMs }
      }
    }
  }

  // Disk -- real per-device usage via `df`, deduped by SOURCE device
  // (not mount point): this machine's btrfs root is bind-mounted at
  // /, /home, /var/log, /var/cache/pacman/pkg all at once, confirmed
  // directly via `df` -- without deduping, that's the same disk shown
  // 4 times. Keeps whichever mount point is shortest for each unique
  // device (typically the real mount root, e.g. "/" over "/home").
  // -B1 for exact byte counts, not human-suffixed strings to parse.
  Process {
    id: diskProc
    command: ["df", "-B1", "--output=source,target,size,used"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text || "").split("\n").slice(1)
        var bySource = {}
        for (var i = 0; i < lines.length; i++) {
          var fields = lines[i].trim().split(/\s+/)
          if (fields.length < 4) continue
          var source = fields[0]
          if (source.indexOf("/dev/") !== 0) continue
          var target = fields[1]
          var size = Number(fields[2])
          var used = Number(fields[3])
          if (!size) continue
          var existing = bySource[source]
          if (!existing || target.length < existing.target.length) {
            bySource[source] = { target: target, size: size, used: used }
          }
        }
        var result = []
        for (var src in bySource) {
          var entry = bySource[src]
          result.push({
            name: entry.target,
            percent: entry.used / entry.size,
            usedGB: entry.used / 1024 / 1024 / 1024,
            totalGB: entry.size / 1024 / 1024 / 1024
          })
        }
        result.sort(function(a, b) { return a.name < b.name ? -1 : 1 })
        root.disks = result
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
      if (!memProc.running) memProc.running = true
      if (!netProc.running) netProc.running = true
      if (!diskProc.running) diskProc.running = true
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

    // Right panel -- stat tiles. Per direct spec: row 1 CPU + GPU, row
    // 2 Network + Memory, row 3 storage tiles (one per real disk).
    ColumnLayout {
      Layout.fillWidth: true
      Layout.fillHeight: true
      spacing: 8

      // Shared tile shape -- icon + title top, big value, thin usage
      // bar + subtext at the bottom. Plain QML primitives, matching
      // this whole plugin's own established style (no qs.Ui pulled in
      // here either, same as DashboardContent.qml/WallpapersContent.qml).
      component StatTile: Rectangle {
        id: tile
        property string glyph: ""
        property string title: ""
        property string valueText: ""
        property string subText: ""
        property real barValue: 0

        radius: 10
        color: Qt.rgba(1, 1, 1, 0.05)

        ColumnLayout {
          anchors.fill: parent
          anchors.margins: 10
          spacing: 4

          RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Text {
              text: tile.glyph
              font.family: root.fontFamily
              font.pixelSize: 13
              color: root.muted
            }

            Text {
              text: tile.title
              font.family: root.fontFamily
              font.pixelSize: 10
              color: root.muted
              elide: Text.ElideRight
              Layout.fillWidth: true
            }
          }

          Text {
            text: tile.valueText
            font.family: root.fontFamily
            font.pixelSize: 20
            font.weight: Font.DemiBold
            color: root.textColor
            Layout.fillWidth: true
          }

          Item { Layout.fillHeight: true }

          Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 6
            radius: 3
            color: Qt.rgba(1, 1, 1, 0.08)

            Rectangle {
              width: parent.width * Math.max(0, Math.min(1, tile.barValue))
              height: parent.height
              radius: 3
              color: root.accent
              Behavior on width { NumberAnimation { duration: 200 } }
            }
          }

          Text {
            text: tile.subText
            font.family: root.fontFamily
            font.pixelSize: 9
            color: root.muted
            elide: Text.ElideRight
            Layout.fillWidth: true
          }
        }
      }

      // Dial variant -- CPU/GPU per direct request ("can you core icon
      // and then a full dial around it that shows the percentage usage
      // aggregate in it... gonna do the same for GPU"). Ported the
      // exact ring/tip math from DashboardContent.qml's own Dial
      // component (the speaker/mic volume dials) rather than inventing
      // a new circular gauge -- same 270deg sweep with a 45deg gap at
      // the bottom (ambxst's own CircularControl.qml proportions),
      // same handleSpacing-based gap-before-the-tip math, same thick
      // white tip. Read-only here (no click/mute signal, nothing to
      // toggle for a CPU/GPU usage reading), and adds the actual
      // percentage as text since a stats tile needs the exact number,
      // not just the ring's fill level the way a volume control does.
      component DialTile: Rectangle {
        id: tile
        property string glyph: ""
        // Re-added per direct follow-up ("we need to know its the
        // CPU too maybe CPU Usage and GPU usage") -- folded into the
        // same "Usage" line instead of its own row this time, so the
        // identifying label is back without the extra height a
        // separate title row cost before.
        property string title: ""
        property real value: 0
        property string subText: ""
        // Temperature -- per direct request ("for the tempture for
        // CPU and GPU we can put this in the card below the section
        // we just made but full width bar inside its cpu or gpu
        // card"). -1 hides the row entirely (used nowhere currently,
        // but keeps this component honest about "no reading" instead
        // of silently drawing a 0% bar).
        property real tempC: -1
        // 105 -- this CPU's own real throttle point (`sensors`'
        // temp1_max/temp1_crit on coretemp-isa-0000, confirmed
        // directly, not guessed), used as the bar's "full" reference.
        property real tempMaxC: 105

        radius: 10
        color: Qt.rgba(1, 1, 1, 0.05)

        property color ringAccent: root.accent
        onRingAccentChanged: dialCanvas.requestPaint()
        onValueChanged: dialCanvas.requestPaint()

        ColumnLayout {
          anchors.fill: parent
          anchors.margins: 10
          spacing: 6

          RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Item {
              id: dialItem
              // 46 -> 60, per direct request to make the dial/icon
              // bigger. Ring radius (width/2-6) and the tip/arc math
              // below both scale off this automatically.
              Layout.preferredWidth: 60
              Layout.preferredHeight: 60
              Layout.alignment: Qt.AlignVCenter

              Canvas {
                id: dialCanvas
                anchors.fill: parent
                onPaint: {
                  var ctx = getContext("2d")
                  ctx.reset()
                  var cx = width / 2, cy = height / 2, r = width / 2 - 6
                  var startAngle = Math.PI / 2 + Math.PI / 4
                  var totalSweep = Math.PI * 2 - Math.PI / 2
                  var endAngle = startAngle + Math.max(0, Math.min(1, tile.value)) * totalSweep
                  var handleSpacing = 5
                  var gapRad = handleSpacing / r
                  ctx.lineWidth = 4
                  ctx.lineCap = "round"
                  ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.15)
                  ctx.beginPath()
                  ctx.arc(cx, cy, r, endAngle + gapRad, startAngle + totalSweep)
                  ctx.stroke()

                  ctx.strokeStyle = tile.ringAccent
                  ctx.beginPath()
                  var progressEnd = Math.max(startAngle, endAngle - gapRad)
                  ctx.arc(cx, cy, r, startAngle, progressEnd)
                  ctx.stroke()

                  var tipR1 = r - 2
                  var tipR2 = r + 3
                  var tx1 = cx + tipR1 * Math.cos(endAngle)
                  var ty1 = cy + tipR1 * Math.sin(endAngle)
                  var tx2 = cx + tipR2 * Math.cos(endAngle)
                  var ty2 = cy + tipR2 * Math.sin(endAngle)
                  ctx.lineWidth = 5
                  ctx.lineCap = "round"
                  ctx.strokeStyle = "#ffffff"
                  ctx.beginPath()
                  ctx.moveTo(tx1, ty1)
                  ctx.lineTo(tx2, ty2)
                  ctx.stroke()
                }
              }

              Text {
                anchors.centerIn: parent
                text: tile.glyph
                font.family: root.fontFamily
                font.pixelSize: 18
                color: root.textColor
              }
            }

            // Beside the dial, not stacked under it -- per direct
            // feedback the all-vertical layout made the whole tile too
            // tall. "Usage 10%" then the CPU/GPU name below it.
            ColumnLayout {
              Layout.fillWidth: true
              Layout.alignment: Qt.AlignVCenter
              spacing: 2

              Text {
                text: (tile.title ? tile.title + " " : "") + "Usage " + Math.round(tile.value * 100) + "%"
                font.family: root.fontFamily
                font.pixelSize: 13
                font.weight: Font.DemiBold
                color: root.textColor
                elide: Text.ElideRight
                Layout.fillWidth: true
              }

              Text {
                text: tile.subText
                font.family: root.fontFamily
                font.pixelSize: 10
                color: root.muted
                elide: Text.ElideRight
                Layout.fillWidth: true
              }
            }
          }

          // Full-width temperature bar, below the dial+usage row, per
          // direct request -- same visual language as the per-core CPU
          // list's own bars (thin rounded track + accent fill), just
          // full-width instead of sharing a row with an icon/label.
          RowLayout {
            Layout.fillWidth: true
            visible: tile.tempC >= 0
            spacing: 6

            Rectangle {
              Layout.fillWidth: true
              Layout.preferredHeight: 6
              radius: 3
              color: Qt.rgba(1, 1, 1, 0.08)

              Rectangle {
                width: parent.width * Math.max(0, Math.min(1, tile.tempC / tile.tempMaxC))
                height: parent.height
                radius: 3
                color: root.accent
                Behavior on width { NumberAnimation { duration: 200 } }
              }
            }

            Text {
              text: Math.round(tile.tempC) + "\u00b0C"
              font.family: root.fontFamily
              font.pixelSize: 10
              color: root.muted
              Layout.preferredWidth: 32
              horizontalAlignment: Text.AlignRight
            }
          }
        }
      }

      // Memory's own dial variant -- per direct request ("it should be
      // a dial too 45% Used in it instead of the logo... the bar seems
      // redundant though... feature the amount 5.1 / 11 GiB"). No icon
      // (memory has no identifying logo/name the way CPU/GPU do) --
      // the percentage itself sits centered inside the ring instead,
      // and the used/total amount is the featured, centered text below
      // it rather than a small subtext line. The old StatTile's linear
      // bar is dropped entirely for this one -- the ring already is
      // the usage indicator, a second one was redundant.
      component MemoryDialTile: Rectangle {
        id: tile
        property real value: 0
        property string amountText: ""

        radius: 10
        color: Qt.rgba(1, 1, 1, 0.05)

        property color ringAccent: root.accent
        onRingAccentChanged: dialCanvas.requestPaint()
        onValueChanged: dialCanvas.requestPaint()

        ColumnLayout {
          anchors.fill: parent
          anchors.margins: 10
          spacing: 4

          Text {
            text: "Memory"
            font.family: root.fontFamily
            font.pixelSize: 10
            color: root.muted
            Layout.fillWidth: true
          }

          Item { Layout.fillHeight: true }

          Item {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 60
            Layout.preferredHeight: 60

            Canvas {
              id: dialCanvas
              anchors.fill: parent
              onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                var cx = width / 2, cy = height / 2, r = width / 2 - 6
                var startAngle = Math.PI / 2 + Math.PI / 4
                var totalSweep = Math.PI * 2 - Math.PI / 2
                var endAngle = startAngle + Math.max(0, Math.min(1, tile.value)) * totalSweep
                var handleSpacing = 5
                var gapRad = handleSpacing / r
                ctx.lineWidth = 4
                ctx.lineCap = "round"
                ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.15)
                ctx.beginPath()
                ctx.arc(cx, cy, r, endAngle + gapRad, startAngle + totalSweep)
                ctx.stroke()

                ctx.strokeStyle = tile.ringAccent
                ctx.beginPath()
                var progressEnd = Math.max(startAngle, endAngle - gapRad)
                ctx.arc(cx, cy, r, startAngle, progressEnd)
                ctx.stroke()

                var tipR1 = r - 2
                var tipR2 = r + 3
                var tx1 = cx + tipR1 * Math.cos(endAngle)
                var ty1 = cy + tipR1 * Math.sin(endAngle)
                var tx2 = cx + tipR2 * Math.cos(endAngle)
                var ty2 = cy + tipR2 * Math.sin(endAngle)
                ctx.lineWidth = 5
                ctx.lineCap = "round"
                ctx.strokeStyle = "#ffffff"
                ctx.beginPath()
                ctx.moveTo(tx1, ty1)
                ctx.lineTo(tx2, ty2)
                ctx.stroke()
              }
            }

            Text {
              anchors.centerIn: parent
              text: Math.round(tile.value * 100) + "%"
              font.family: root.fontFamily
              font.pixelSize: 13
              font.weight: Font.DemiBold
              color: root.textColor
            }
          }

          Text {
            text: tile.amountText
            font.family: root.fontFamily
            font.pixelSize: 12
            font.weight: Font.DemiBold
            color: root.textColor
            horizontalAlignment: Text.AlignHCenter
            Layout.alignment: Qt.AlignHCenter
          }

          Item { Layout.fillHeight: true }
        }
      }
      RowLayout {
        Layout.fillWidth: true
        // 66 -> 92 (temperature bar row) -> 106 (bigger dial, 46 -> 60,
        // per direct request).
        Layout.preferredHeight: 106
        spacing: 8

        DialTile {
          Layout.fillWidth: true
          Layout.fillHeight: true
          glyph: ""
          title: "CPU"
          value: root.cpuUsage
          subText: root.cpuModel || ""
          tempC: root.packageTemp
        }

        DialTile {
          Layout.fillWidth: true
          Layout.fillHeight: true
          glyph: "󰢮"
          title: "GPU"
          value: root.gpuUsage
          subText: root.gpuName || ""
          // Same real sensor as the CPU tile -- this iGPU shares
          // the CPU package's die/thermal zone, confirmed directly (no
          // separate hwmon/thermal-zone entry exists for it anywhere
          // under /sys/class/drm/card1 on this machine), not a
          // fallback/guess.
          tempC: root.packageTemp
        }
      }

      RowLayout {
        Layout.fillWidth: true
        // 92 -> 106, matching the CPU/GPU row -- Memory's own dial
        // needs the same extra room theirs did.
        Layout.preferredHeight: 106
        spacing: 8

        StatTile {
          Layout.fillWidth: true
          Layout.fillHeight: true
          glyph: ""
          title: "Network"
          valueText: {
            var total = root.netRxRate + root.netTxRate
            return (total / 1024 / 1024).toFixed(1) + " MB/s"
          }
          barValue: 0
          subText: root.netInterface ? ("↓ " + (root.netRxRate / 1024).toFixed(0) + " KB/s  ↑ " + (root.netTxRate / 1024).toFixed(0) + " KB/s") : "No connection"
        }

        MemoryDialTile {
          Layout.fillWidth: true
          Layout.fillHeight: true
          value: root.memUsedPercent
          amountText: root.memUsedGB.toFixed(1) + " / " + root.memTotalGB.toFixed(1) + " GiB"
        }
      }

      // Storage -- grouped into one full-width panel instead of square
      // tiles, per direct request ("group them together so that panel
      // is full width... 45/117 GB and then right align is the
      // percentage"): one row per real disk, name+used/total on the
      // left, percentage right-aligned in its own fixed-width column
      // so multiple disks' percentages line up vertically.
      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: Math.max(40, disksColumn.implicitHeight + 20)
        radius: 10
        color: Qt.rgba(1, 1, 1, 0.05)

        ColumnLayout {
          id: disksColumn
          anchors.fill: parent
          anchors.margins: 10
          spacing: 6

          Repeater {
            model: root.disks

            RowLayout {
              id: diskRow
              required property var modelData
              Layout.fillWidth: true
              spacing: 8

              Text {
                text: "󰋊"
                font.family: root.fontFamily
                font.pixelSize: 13
                color: root.muted
              }

              Text {
                text: diskRow.modelData.name
                font.family: root.fontFamily
                font.pixelSize: 11
                color: root.textColor
                elide: Text.ElideRight
              }

              Text {
                text: diskRow.modelData.usedGB.toFixed(0) + " / " + diskRow.modelData.totalGB.toFixed(0) + " GB"
                font.family: root.fontFamily
                font.pixelSize: 11
                color: root.muted
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignRight
              }

              Text {
                text: Math.round(diskRow.modelData.percent * 100) + "%"
                font.family: root.fontFamily
                font.pixelSize: 11
                font.weight: Font.DemiBold
                color: root.textColor
                Layout.preferredWidth: 32
                horizontalAlignment: Text.AlignRight
              }
            }
          }
        }
      }

      Item { Layout.fillHeight: true }
    }
  }
}
