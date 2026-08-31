import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Widgets

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

  // Bumped by Overlay.qml's own refreshAvatar IPC handler -- direct
  // follow-up ("on the expanded notch, health page, the avatar needs
  // to be updated there too same way the notch is getting the
  // updates"). This page's own avatar block was still the pre-fix
  // version entirely (hardcoded gradient colors, no cache-bust at all
  // -- its Image source string never changed, so it could never pick
  // up a new ~/.face.icon without a full restart even though the
  // collapsed row's own UserAvatar already could).
  property int avatarCacheBust: 0

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
  // Real bug report: a friend's machine showed a stuck 100% GPU usage
  // while btop showed 0%. Root cause, confirmed directly -- the rc6
  // path below used to be hardcoded to /sys/class/drm/card1, which is
  // this machine's real Intel iGPU (there's no card0 here at all), but
  // that's this machine's own enumeration, not a guarantee. On a
  // machine where the iGPU is card0 instead (or any non-Intel GPU,
  // which never exposes an rc6_residency_ms file), `cat` on the wrong
  // path fails silently -- stdout is empty, and JS's Number("") is 0,
  // not NaN, so rc6Delta stayed permanently 0 while wallDelta kept
  // climbing, making 1 - 0/wallDelta = 1 forever. Fixed by discovering
  // the real path at runtime (gpuDiscoveryProc below) instead of
  // assuming card1, and by never computing a percentage at all when no
  // path was found or a read comes back empty -- gpuAvailable gates the
  // DialTile into an explicit "Unavailable" state instead.
  property string gpuRc6Path: ""
  property bool gpuAvailable: false
  property bool gpuDiscoveryAttempted: false

  property real memUsedPercent: 0
  property real memUsedGB: 0
  property real memTotalGB: 0

  property string netInterface: ""
  property real netRxRate: 0
  property real netTxRate: 0
  property var prevNetSample: null
  // Cumulative lifetime bytes -- the raw /proc/net/dev counter itself,
  // not a delta. Same "Total" btop's own network widget shows
  // (confirmed by reading it directly on this machine: "Total: 2.47
  // GiB" under download, "Total: 16.2 GiB" under upload) -- per direct
  // request to match that exact three-field shape (rate + lifetime
  // total, for each direction).
  property real netRxTotalBytes: 0
  property real netTxTotalBytes: 0

  // Auto-scaling B/s -> KB/s -> MB/s, per direct request ("download
  // speed the MB/s thats there or in B/s") -- picks whichever unit
  // keeps the number readable instead of a fixed one that reads as
  // "0.0 MB/s" for anything under ~100KB/s (most of the time on an
  // idle connection).
  function formatRate(bytesPerSec) {
    if (bytesPerSec < 1024) return Math.round(bytesPerSec) + " B/s"
    if (bytesPerSec < 1024 * 1024) return (bytesPerSec / 1024).toFixed(1) + " KB/s"
    return (bytesPerSec / 1024 / 1024).toFixed(1) + " MB/s"
  }

  // Same auto-scaling idea, no "/s" -- for the cumulative totals.
  // "GiB" naming (binary/1024-based) to match btop's own labeling
  // exactly, not guessed.
  function formatBytes(bytes) {
    if (bytes < 1024) return Math.round(bytes) + " B"
    if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + " KiB"
    if (bytes < 1024 * 1024 * 1024) return (bytes / 1024 / 1024).toFixed(1) + " MiB"
    return (bytes / 1024 / 1024 / 1024).toFixed(2) + " GiB"
  }

  // Download's share of current total throughput -- per direct
  // request for a split progress bar (green = download, red = upload)
  // showing which direction dominates RIGHT NOW, not an absolute
  // 0-100% scale (network speed has no fixed ceiling the way CPU/RAM
  // do). 0.5 (even split) when both are 0 -- an idle connection
  // shouldn't render as all-one-color.
  readonly property real netDownloadShare: {
    var total = netRxRate + netTxRate
    return total > 0 ? netRxRate / total : 0.5
  }

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

  // Real package (overall) temperature -- lm_sensors' own coretemp
  // driver's "Package id 0" key under coretemp-isa-0000, confirmed by
  // running `sensors -j` on this machine directly, not guessed.
  // fastfetch's own CPU.temperature field is null on this machine
  // (aggregate-only, and not populated here anyway), so this is a
  // separate real source, not something fastfetch already provided.
  // Per-core temps were dropped along with the per-core details row
  // below -- per direct feedback ("it all gets hot at similar rate")
  // nothing reads a per-core reading anymore.
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
              var reading = fields[key]
              if (typeof reading !== "object") continue
              if (!/^Package id \d+$/.test(key)) continue
              for (var field in reading) {
                if (field.endsWith("_input")) {
                  pkgTemp = reading[field]
                  break
                }
              }
            }
          }
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
  //
  // The card index is NOT hardcoded (used to be card1, this machine's
  // real path since there's no card0 here -- but that's this machine's
  // own PCI enumeration, not a rule). gpuDiscoveryProc finds whichever
  // /sys/class/drm/card* actually has an rc6_residency_ms file --
  // connectors (card1-HDMI-A-1 etc) never have one (confirmed directly:
  // they expose autosuspend_delay_ms/control/runtime_* instead), and
  // neither does any non-Intel GPU, so file existence alone is a
  // reliable enough filter without also needing to grep each card's
  // uevent for DRIVER=i915.
  Process {
    id: gpuDiscoveryProc
    command: ["bash", "-c", "for d in /sys/class/drm/card*; do [ -f \"$d/power/rc6_residency_ms\" ] && echo \"$d/power/rc6_residency_ms\" && break; done"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var path = String(text || "").trim()
        root.gpuRc6Path = path
        root.gpuAvailable = path !== ""
      }
    }
  }

  Process {
    id: gpuProc
    command: ["cat", root.gpuRc6Path]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var raw = String(text || "").trim()
        // Empty on a transient read failure (sysfs hiccup, permissions)
        // even though discovery found a real path -- skip the update
        // rather than let Number("") coerce to 0 and poison the delta
        // calc below into reading as 100% busy (the exact reported bug:
        // "100 gpu usage" while btop showed 0%, traced to this coercion
        // firing every single poll against a permanently-wrong path).
        if (raw === "") return
        var rc6Ms = Number(raw)
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
        // Raw counters, not a delta -- this IS the lifetime total
        // already (since the interface came up), no separate tracking
        // needed.
        root.netRxTotalBytes = rxBytes
        root.netTxTotalBytes = txBytes
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
      // Runs once (gpuDiscoveryAttempted latches it) rather than every
      // 2s -- the real GPU's sysfs path can't change mid-session, and a
      // machine with no rc6-capable GPU at all (AMD/NVIDIA-only) would
      // otherwise re-fork this forever for nothing.
      if (!root.gpuDiscoveryAttempted && !gpuDiscoveryProc.running) {
        root.gpuDiscoveryAttempted = true
        gpuDiscoveryProc.running = true
      }
      if (!statProc.running) statProc.running = true
      if (!sensorsProc.running) sensorsProc.running = true
      if (root.gpuRc6Path !== "" && !gpuProc.running) gpuProc.running = true
      if (!memProc.running) memProc.running = true
      if (!netProc.running) netProc.running = true
      if (!diskProc.running) diskProc.running = true
    }
  }

  RowLayout {
    anchors.fill: parent
    // 8 -> 16 -- per direct feedback the stat-tiles section sat too
    // close to the CPU list beside it.
    spacing: 16

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
        // Extra top padding above the avatar/identity block, per
        // direct feedback ("the User Profile stuff, the card doesnt
        // have enough top and bottom padding", then "a bit more...it
        // looks cramped" -- 8 -> 16) -- on top of the panel's own 20px
        // outer topMargin (Overlay.qml's expandedContent), which felt
        // too tight for this block specifically.
        Layout.topMargin: 16
        spacing: 14

        // Avatar -- same gradient-placeholder + ~/.face.icon +
        // rounded-square-mask pattern as the collapsed notch's own
        // UserAvatar (Overlay.qml), just bigger and without that
        // one's click-to-open-dashboard handler (irrelevant here,
        // already inside the open dashboard). Brought up to parity
        // with UserAvatar's own fixes -- theme-aware gradient, hidden
        // once a real image loads, cache-bust so a new avatar actually
        // shows up live, rounded-square (not circular) real-avatar
        // clip -- see UserAvatar's own comments for the full reasoning
        // on each.
        Item {
          id: avatar
          Layout.preferredWidth: 64
          Layout.preferredHeight: 64

          Rectangle {
            anchors.fill: parent
            radius: width / 2
            visible: avatarImage.status !== Image.Ready
            gradient: Gradient {
              GradientStop { position: 0.0; color: Qt.lighter(root.accent, 1.6) }
              GradientStop { position: 1.0; color: Qt.darker(root.accent, 1.4) }
            }
          }

          Image {
            id: avatarImage
            anchors.fill: parent
            source: "file://" + Quickshell.env("HOME") + "/.face.icon#" + root.avatarCacheBust
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: false
            visible: false
          }

          Rectangle {
            id: avatarMask
            anchors.fill: parent
            radius: width * 0.2
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
              // Arch Linux logo (linux-archlinux, U+F303), not the
              // generic fa-linux penguin it used to be -- direct
              // follow-up ("switch the penguin on the health bar to
              // the arch linux icon, i think the penguin is ubuntu
              // right? so arch kinda makes more sense here? or
              // actually, can you use the omarchy icon"). Checked for
              // a real compact Omarchy icon asset first (not
              // guessed): /usr/share/omarchy/logo.svg and the sddm/
              // plymouth logo.png are both wide ~4:1 wordmark
              // logotypes (1215x285 / 800x188), not a square mark that
              // fits a small inline row icon -- so Arch (what Omarchy
              // actually is, per this row's own real Omarchy-version
              // text next to it) is the practical choice here, same
              // glyph already used for the app launcher's own icon
              // (ruixen.applauncher/AppLauncher.qml).
              text: ""
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
        // Extra bottom padding under the avatar/identity block, same
        // follow-up as the topMargin above (8 -> 16) -- widens the gap
        // before the "CPUs" separator instead of just the base
        // ColumnLayout spacing (10).
        Layout.topMargin: 16
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

      // Item wrapper, not the Flickable directly in the layout slot --
      // direct follow-up ("can we add the top and buttom here as well
      // for people that have alot of cpus?"). Same scroll-aware fade
      // design as ruixen.settings' own detail panel (Settings.qml):
      // opacity bound directly to real scroll overflow (0 at rest,
      // ramps in over a short 16px drag distance), not a static
      // always-on overlay -- a machine with few cores (nothing to
      // scroll) never shows a fade it has no business showing. The
      // Flickable's own bounds don't move during scrolling (only its
      // contentY does), so anchoring the fades to this wrapper Item's
      // edges is safe and needs no extra margin/gap handling the way
      // Settings.qml's shared-scroll header did.
      Item {
        Layout.fillWidth: true
        Layout.fillHeight: true

        Flickable {
          id: cpuFlickable
          anchors.fill: parent
          contentWidth: width
          contentHeight: coreColumn.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          Column {
            id: coreColumn
            width: parent.width
            spacing: 8

            Repeater {
              model: root.coreUsages

              // One row per core now, not two -- per direct feedback
              // ("people dont really need individual cores, it all gets
              // hot at similar rate") the details row (name + per-core
              // temp) was dropped entirely. The icon column that used to
              // hold just the CPU glyph now shows the glyph plus the
              // core's own 1-indexed number ("CPU icon 1 for Core 1")
              // instead of a separate "Core 0" text label.
              RowLayout {
                id: coreItem
                required property int index
                required property real modelData
                width: coreColumn.width
                spacing: 8

                Text {
                  text: " " + (coreItem.index + 1)
                  font.family: root.fontFamily
                  font.pixelSize: 11
                  color: root.textColor
                  Layout.preferredWidth: 26
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
            }
          }
        }

        Rectangle {
          readonly property real fadeRun: 16
          readonly property real overflowAbove: cpuFlickable.contentY
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          height: 20
          opacity: Math.max(0, Math.min(1, overflowAbove / fadeRun))
          gradient: Gradient {
            GradientStop { position: 0.0; color: "#000000" }
            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0) }
          }
        }

        Rectangle {
          readonly property real fadeRun: 16
          readonly property real overflowBelow: cpuFlickable.contentHeight - cpuFlickable.height - cpuFlickable.contentY
          anchors.bottom: parent.bottom
          anchors.left: parent.left
          anchors.right: parent.right
          height: 20
          opacity: Math.max(0, Math.min(1, overflowBelow / fadeRun))
          gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0) }
            GradientStop { position: 1.0; color: "#000000" }
          }
        }
      }
    }

    // Right panel -- stat tiles. Per direct spec: row 1 CPU + GPU, row
    // 2 Network + Memory, row 3 storage tiles (one per real disk).
    ColumnLayout {
      Layout.fillWidth: true
      Layout.fillHeight: true
      // Per direct feedback the stat tiles sat too close to the
      // notch's own right edge -- the expanded panel's outer
      // anchors.rightMargin (12, see Overlay.qml's expandedContent)
      // wasn't enough breathing room on its own for this dense a grid.
      Layout.rightMargin: 10
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
              // Matches MemoryDialTile's own header size now, per
              // direct request ("match the header size so its like
              // Memories") -- this StatTile only has one instance left
              // (Network), so bumping it here directly is safe.
              font.pixelSize: 15
              color: root.muted
            }

            Text {
              text: tile.title
              font.family: root.fontFamily
              font.pixelSize: 13
              font.weight: Font.DemiBold
              color: root.textColor
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
        // True for tiles with no meaningful "unavailable" state (CPU
        // usage reads /proc/stat, always present on Linux). GPU sets
        // this to root.gpuAvailable -- same "be honest about no
        // reading" philosophy as tempC's -1 sentinel below, after a
        // real bug (a stuck 100% reading on a machine where the
        // hardcoded sysfs path didn't exist) made silently drawing a
        // plausible-looking percentage the actual problem.
        property bool available: true
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
        onAvailableChanged: dialCanvas.requestPaint()

        ColumnLayout {
          anchors.fill: parent
          anchors.margins: 8
          spacing: 4

          // No separate header row -- per direct follow-up, the
          // icon+title row (matching Network/Memory's own shape) took
          // space this tile didn't need: the icon already lives inside
          // the dial (see dialItem's own Text below) and the title now
          // folds into the "Usage X%" line instead ("CPU Usage 5%"),
          // freeing that height for the dial+usage row and temp bar to
          // actually be the featured content instead of centering the
          // group.
          //
          // Centering: an earlier version used two separate
          // Item { Layout.fillHeight: true } spacers, one before this
          // content and one after, expecting them to split the tile's
          // leftover height evenly (Network/Memory's own tiles use that
          // exact pattern). Confirmed directly with debug-colored
          // Rectangles in place of each spacer that they don't split
          // evenly here -- the first stayed a sliver, the second
          // absorbed nearly everything, pushing the real content to the
          // top instead of centering it (the reported "squeezed"
          // look). Root cause not fully chased down; fixed by dropping
          // the two-spacer approach for this tile in favor of one
          // fillHeight wrapper Item with anchors.centerIn, which
          // doesn't depend on ColumnLayout's fill distribution at all.
          Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Column {
              id: contentBlock
              anchors.centerIn: parent
              width: parent.width
              spacing: 4

              RowLayout {
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: 10

              Item {
                id: dialItem
                // 46 -> 60 (bigger dial, per direct request), then
                // trimmed to 52 (storage headroom), then 46 -- per direct
                // follow-up asking specifically to shave more off just
                // the CPU/GPU row (Network/Memory's own row height is
                // untouched this time). Ring radius (width/2-6) and the
                // tip/arc math below both scale off this automatically.
                Layout.preferredWidth: 46
                Layout.preferredHeight: 46
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
                    // No reading -> empty track only, no progress arc or
                    // tip marker at all (not just a 0%-looking dial) --
                    // same "don't draw something that looks like real data
                    // when it isn't" reasoning as the Usage text above.
                    var endAngle = startAngle + (tile.available ? Math.max(0, Math.min(1, tile.value)) : 0) * totalSweep
                    var handleSpacing = 5
                    var gapRad = handleSpacing / r
                    ctx.lineWidth = 4
                    ctx.lineCap = "round"
                    ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.15)
                    ctx.beginPath()
                    ctx.arc(cx, cy, r, endAngle + gapRad, startAngle + totalSweep)
                    ctx.stroke()

                    if (!tile.available) return

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
                  font.pixelSize: 15
                  color: root.textColor
                }
              }

              // Beside the dial, not stacked under it -- per direct
              // feedback the all-vertical layout made the whole tile too
              // tall. "Usage 10%" then the CPU/GPU name below it. No
              // longer Layout.fillWidth:true -- sized to its own natural
              // content width instead (with a maximumWidth safety cap
              // for real GPU names longer than this machine's own), so
              // the RowLayout above it centers as a compact unit instead
              // of stretching this column all the way to the tile edge.
              ColumnLayout {
                Layout.alignment: Qt.AlignVCenter
                spacing: 2

                Text {
                  // Title prefix back (was dropped when a separate header
                  // row said "CPU"/"GPU" above this) -- now that the
                  // header's gone, this is the only place the tile
                  // identifies itself.
                  text: tile.available
                    ? (tile.title + " Usage " + Math.round(tile.value * 100) + "%")
                    : (tile.title + " Unavailable")
                  font.family: root.fontFamily
                  font.pixelSize: 13
                  font.weight: Font.DemiBold
                  color: root.textColor
                  elide: Text.ElideRight
                  Layout.maximumWidth: 140
                }

                Text {
                  text: tile.subText
                  font.family: root.fontFamily
                  font.pixelSize: 10
                  color: root.muted
                  elide: Text.ElideRight
                  Layout.maximumWidth: 140
                }
              }
            }

            // Temperature bar, below the dial+usage row, per direct
            // request -- same visual language as the per-core CPU list's
            // own bars (thin rounded track + accent fill), just sharing
            // a row with a temperature label instead of an icon/name.
            // Side margins added per direct follow-up ("maybe center the
            // progress bar too, so like that means some side padding to
            // it?") -- matches the dial+usage row above it, which reads
            // as centered/inset now rather than running edge-to-edge.
            // width/anchors instead of Layout.fillWidth+margins now that
            // the immediate parent is a plain Column, not a Layout (see
            // contentBlock above) -- Layout.* properties are silently
            // ignored outside an actual Layout parent.
            RowLayout {
              width: contentBlock.width - 16
              anchors.horizontalCenter: parent.horizontalCenter
              visible: tile.tempC >= 0
              spacing: 6

              // Same track/fill/tip design as ruixen.settings' own
              // sliders -- direct request ("the gpu usage and cpu
              // usage temperator progress bar, lets add the tip head
              // design there to stay more consistence"). gapPx (7)
              // and tip proportions (width 4, height +8 over the 6px
              // bar) are the exact same values ported from Settings.
              // qml's own Output/Input/Brightness sliders, not re-
              // derived.
              Rectangle {
                id: tempBarTrack
                Layout.fillWidth: true
                Layout.preferredHeight: 6
                radius: 3
                color: "transparent"

                readonly property real value: Math.max(0, Math.min(1, tile.tempC / tile.tempMaxC))
                readonly property real valueX: width * value
                readonly property real gapPx: 7

                Rectangle {
                  anchors.left: parent.left
                  anchors.top: parent.top
                  anchors.bottom: parent.bottom
                  width: Math.max(0, parent.valueX - parent.gapPx)
                  radius: 3
                  color: root.accent
                  Behavior on width { NumberAnimation { duration: 200 } }
                }

                Rectangle {
                  anchors.right: parent.right
                  anchors.top: parent.top
                  anchors.bottom: parent.bottom
                  width: Math.max(0, parent.width - parent.valueX - parent.gapPx)
                  radius: 3
                  color: Qt.rgba(1, 1, 1, 0.08)
                }

                Rectangle {
                  anchors.verticalCenter: parent.verticalCenter
                  x: parent.valueX - width / 2
                  width: 4
                  height: parent.height + 8
                  radius: 2
                  color: "#ffffff"
                  Behavior on x { NumberAnimation { duration: 200 } }
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

          RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Text {
              text: ""
              font.family: root.fontFamily
              font.pixelSize: 15
              color: root.muted
            }

            Text {
              text: "Memory"
              font.family: root.fontFamily
              font.pixelSize: 13
              font.weight: Font.DemiBold
              color: root.textColor
              Layout.fillWidth: true
            }
          }

          Item { Layout.fillHeight: true }

          Item {
            Layout.alignment: Qt.AlignHCenter
            // 60 -> 52 (matching CPU/GPU's own trim, see DialTile) ->
            // 68 -- per direct follow-up ("too much room in memory"),
            // this tile's own row height was never trimmed the way
            // CPU/GPU's was, so the smaller dial just left visible
            // empty space above/below it instead of buying anything.
            Layout.preferredWidth: 68
            Layout.preferredHeight: 68

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
              font.pixelSize: 16
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
        // 66 -> 92 (temperature bar row) -> 106 (bigger dial, 46 -> 60)
        // -> 94 (dial trimmed 60 -> 52) -> 84 (dial trimmed further,
        // 52 -> 46, margins 10 -> 8, spacing 6 -> 4) -- per direct
        // follow-up specifically asking to shave more off just this
        // row (storage now has its own scoped Flickable, see the
        // "Storage section scoped into its own internal scroll"
        // section below, so this is no longer about clip-avoidance --
        // just a tighter, more compact CPU/GPU row on its own merits).
        Layout.preferredHeight: 84
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
          available: root.gpuAvailable
          // Same real sensor as the CPU tile -- this iGPU shares
          // the CPU package's die/thermal zone, confirmed directly (no
          // separate hwmon/thermal-zone entry exists for it anywhere
          // under this machine's own GPU card path), not a
          // fallback/guess. Independent of gpuAvailable above -- this
          // comes from `sensors` (coretemp), not the rc6 sysfs path, so
          // it still shows even if usage discovery found nothing.
          tempC: root.packageTemp
        }
      }

      RowLayout {
        Layout.fillWidth: true
        // 92 -> 106 -> 94, matching the CPU/GPU row's own trim.
        Layout.preferredHeight: 94
        spacing: 8

        // Custom layout instead of StatTile -- per direct request to
        // match btop's own three-field shape ("download total 2.47
        // GiB and around 307 Byte/s and then upload is 500 Byte/s and
        // Total 16.2 GiB"), a rate + a lifetime total for EACH
        // direction (4 numbers), more than StatTile's single value+
        // subtext slot could hold. Same row shape as the storage
        // panel below (label left, stat right-aligned) for both
        // Download and Upload.
        Rectangle {
          Layout.fillWidth: true
          Layout.fillHeight: true
          radius: 10
          color: Qt.rgba(1, 1, 1, 0.05)

          ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            // 6 -> 8 -- per direct follow-up to space Download/Upload/
            // the bar/the rate caption out evenly ("measure it so...
            // download upload and bar and speed is spaced out so it
            // matches with the progress bar and its buttom row"). The
            // one-off Layout.topMargin: 3 added to just the bar in the
            // previous pass is gone too -- every gap between these
            // rows is this same uniform value now, not a mix of base
            // spacing plus an extra one-off bump on a single gap. 10,
            // not 8 -- measured against MemoryDialTile's own content
            // bottom (both tiles center their content the same way,
            // via matching top+bottom fillHeight spacers) and nudged
            // up so this tile's own content block ends closer to the
            // same height, per direct request ("kinda end it at the
            // same height if possible").
            spacing: 10

            RowLayout {
              Layout.fillWidth: true
              spacing: 6

              Text {
                text: ""
                font.family: root.fontFamily
                font.pixelSize: 15
                color: root.muted
              }

              Text {
                text: "Network"
                font.family: root.fontFamily
                font.pixelSize: 13
                font.weight: Font.DemiBold
                color: root.textColor
                Layout.fillWidth: true
              }
            }

            Item { Layout.fillHeight: true }

            // Icon + "Download"/"Upload" label instead of the rate
            // number here, per direct follow-up ("the previous spot
            // where the same speed was put text and icon for Download
            // and Upload") -- the rate itself moved to the color-
            // matched caption under the bar below, so repeating it
            // here was redundant; this row's job is now identifying
            // WHICH direction the total on the right belongs to.
            RowLayout {
              Layout.fillWidth: true
              spacing: 6
              visible: root.netInterface !== ""

              Text {
                text: ""
                font.family: root.fontFamily
                font.pixelSize: 12
                color: root.muted
              }

              Text {
                text: "Download"
                font.family: root.fontFamily
                font.pixelSize: 12
                color: root.textColor
                Layout.fillWidth: true
                elide: Text.ElideRight
              }

              Text {
                text: root.formatBytes(root.netRxTotalBytes)
                font.family: root.fontFamily
                font.pixelSize: 11
                color: root.muted
                horizontalAlignment: Text.AlignRight
              }
            }

            RowLayout {
              Layout.fillWidth: true
              spacing: 6
              visible: root.netInterface !== ""

              Text {
                text: ""
                font.family: root.fontFamily
                font.pixelSize: 12
                color: root.muted
              }

              Text {
                text: "Upload"
                font.family: root.fontFamily
                font.pixelSize: 12
                color: root.textColor
                Layout.fillWidth: true
                elide: Text.ElideRight
              }

              Text {
                text: root.formatBytes(root.netTxTotalBytes)
                font.family: root.fontFamily
                font.pixelSize: 11
                color: root.muted
                horizontalAlignment: Text.AlignRight
              }
            }

            Text {
              visible: root.netInterface === ""
              text: "No connection"
              font.family: root.fontFamily
              font.pixelSize: 12
              color: root.muted
              Layout.fillWidth: true
            }

            // Split bar -- moved to the card's own footer, below the
            // rate/total rows, per direct follow-up ("put the progress
            // bar on the footer of the card the upload and download
            // above it"). Green (download) / red (upload), widths are
            // each direction's SHARE of current total throughput, not
            // an absolute percentage -- network speed has no natural
            // 0-100% ceiling the way CPU/RAM do, so this reads as
            // "which direction dominates right now" rather than "how
            // full is the pipe". Hidden alongside the rows when
            // there's no connection -- a meaningless 50/50 split isn't
            // worth showing next to "No connection".
            ClippingRectangle {
              Layout.fillWidth: true
              Layout.preferredHeight: 6
              radius: 3
              color: Qt.rgba(1, 1, 1, 0.08)
              visible: root.netInterface !== ""

              Row {
                anchors.fill: parent

                Rectangle {
                  width: parent.width * root.netDownloadShare
                  height: parent.height
                  color: "#3ecf5b"
                  Behavior on width { NumberAnimation { duration: 200 } }
                }

                Rectangle {
                  width: parent.width * (1 - root.netDownloadShare)
                  height: parent.height
                  color: "#e05252"
                  Behavior on width { NumberAnimation { duration: 200 } }
                }
              }
            }

            // Caption directly under the bar -- per direct follow-up
            // ("under this progress bar on the left and right side
            // below it can you put like whats actually happening...
            // is that where the up down speed is supposed to go?").
            // The rate/total rows above already have the full numbers;
            // this is just the two rates again, color-matched to the
            // bar's own green/red so which segment is which reads
            // instantly without tracing back up to the rows.
            RowLayout {
              Layout.fillWidth: true
              visible: root.netInterface !== ""

              Text {
                text: "↓ " + root.formatRate(root.netRxRate)
                font.family: root.fontFamily
                font.pixelSize: 10
                color: "#3ecf5b"
              }

              Item { Layout.fillWidth: true }

              Text {
                text: "↑ " + root.formatRate(root.netTxRate)
                font.family: root.fontFamily
                font.pixelSize: 10
                color: "#e05252"
              }
            }

            // Matching trailing spacer -- per direct follow-up ("what
            // about padding it better so it matches more with
            // memory?"). Only the header had a spacer after it before
            // this, so everything below (Download/Upload, the bar,
            // the caption) sat pinned to the tile's bottom margin
            // instead of vertically centered the way MemoryDialTile's
            // own matching top+bottom spacers keep its content.
            Item { Layout.fillHeight: true }
          }
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
      //
      // Capped height + its own internal Flickable, per direct
      // follow-up ("is scroll within that section an option we can
      // do?") -- rather than making the WHOLE right column scroll (or
      // just letting it grow unbounded and clip against the notch's
      // own fixed height, the previous mitigation), this section alone
      // gets a bounded height and scrolls internally once disk count
      // exceeds it. CPU/GPU/Network/Memory above stay fully visible
      // and pinned regardless of how many disks this machine has --
      // same scoped-Flickable pattern the left panel's own per-core
      // CPU list already uses, just applied to this one section
      // instead of the whole column.
      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(Math.max(40, disksColumn.implicitHeight + 20), 100)
        radius: 10
        color: Qt.rgba(1, 1, 1, 0.05)

        Flickable {
          anchors.fill: parent
          anchors.margins: 10
          contentWidth: width
          contentHeight: disksColumn.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          ColumnLayout {
            id: disksColumn
            width: parent.width
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
      }

      Item { Layout.fillHeight: true }
    }
  }
}
