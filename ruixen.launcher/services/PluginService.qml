import QtQuick
import Quickshell
import Quickshell.Io
import "PluginModel.js" as PluginModel

// Plugins AND About categories' shared backend, ported from
// ruixen.settings/services/PluginService.qml -- list/toggle/update/
// check for Plugins, full-uninstall for About's own danger zone (added
// back once About actually existed to host it; the same reasoning the
// real page's own AboutContent.qml documents for keeping it off the
// Plugins page: "the plugs in list is kinda big").
Item {
  id: root

  // omarchy plugin update itself refuses against a real installed
  // ruixen.* plugin (confirmed directly: it refused with "not a git
  // checkout") -- these are cp -r'd from one shared monorepo checkout
  // instead, so this repo's own update.sh (git pull + reinstall) is the
  // real update path, not that command.
  property var pluginRows: []
  property string pluginBusyId: ""
  // pluginActionProc below is ONE shared Process across every row's own
  // toggle, and reassigning a Quickshell Process's command while it's
  // already running does NOT cancel the in-flight run -- it finishes,
  // THEN the reassigned command auto-fires. Tracks the one genuinely-
  // queued toggle (at most one can ever be pending) so onExited only
  // clears busy state once nothing is left queued.
  property string pluginActionPendingId: ""
  property string pluginUpdateStatus: ""
  property string pluginUpdateError: ""
  property string ruixenRepoPath: ""

  function parsePluginList(raw) {
    return PluginModel.parsePluginList(raw)
  }

  function pluginIsProtected(row) {
    return PluginModel.pluginIsProtected(row)
  }

  Process {
    id: pluginListProc
    command: ["omarchy", "plugin", "list", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.pluginRows = root.parsePluginList(text)
    }
  }

  function refreshPlugins() {
    if (!pluginListProc.running) pluginListProc.running = true
  }

  Process {
    id: pluginActionProc
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onExited: {
      // A newer toggle is genuinely queued behind this one -- leave
      // pluginBusyId showing that row rather than clearing it, which
      // would flash "nothing busy" for a moment right before the queued
      // toggle actually starts.
      if (root.pluginActionPendingId !== "") {
        root.pluginActionPendingId = ""
      } else {
        root.pluginBusyId = ""
      }
      root.refreshPlugins()
    }
  }

  function togglePluginEnabled(row) {
    if (!row || !row.id || root.pluginIsProtected(row)) return
    root.pluginActionPendingId = pluginActionProc.running ? row.id : ""
    root.pluginBusyId = row.id
    pluginActionProc.command = ["omarchy", "plugin", row.enabled ? "disable" : "enable", row.id]
    pluginActionProc.running = true
  }

  // Repo path -- install.sh writes its own checkout location to this
  // state file on every install/update run. Read fresh via bash so a
  // missing file just yields an empty string instead of a QML file-read
  // error.
  Process {
    id: repoPathProc
    command: ["bash", "-c", "cat \"$HOME/.local/state/ruixen/repo-path\" 2>/dev/null"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.ruixenRepoPath = text.trim()
    }
  }

  function refreshRepoPath() {
    repoPathProc.running = true
  }

  Process {
    id: updateProc
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        // A successful run never gets here to report success --
        // update.sh ends with `omarchy restart shell`, which tears down
        // and reloads this very plugin instance before this handler
        // would ever fire. Only a failure that happens BEFORE that
        // point (network down, git pull conflict, etc.) leaves this
        // instance alive long enough to actually show the error.
        if (updateProc.exitCode !== 0) {
          root.pluginUpdateStatus = "error"
          var errLines = text.trim().split("\n")
          root.pluginUpdateError = errLines.slice(Math.max(0, errLines.length - 3)).join("\n")
        }
      }
    }
  }

  function updateRuixenShell() {
    if (root.ruixenRepoPath === "" || root.pluginUpdateStatus === "updating") return
    root.pluginUpdateStatus = "updating"
    root.pluginUpdateError = ""
    // Single-quoted, with any literal single-quote in the path escaped
    // as '\'' -- the standard safe way to embed an arbitrary string as
    // one bash argument.
    var safePath = root.ruixenRepoPath.replace(/'/g, "'\\''")
    updateProc.command = ["bash", "-c", "cd '" + safePath + "' && ./update.sh"]
    updateProc.running = true
  }

  // "Check for updates" -- read-only (update.sh --check-json only
  // fetches + compares, never mutates the working tree), so unlike
  // updateRuixenShell() above this never restarts the shell and always
  // gets to report its own result.
  property string pluginCheckStatus: ""
  property string pluginCheckError: ""
  property var pluginChangedIds: []
  property bool pluginsUpToDate: true

  Process {
    id: checkUpdatesProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = null
        try { parsed = JSON.parse(text) } catch (e) { parsed = null }
        if (!parsed || parsed.error) {
          root.pluginCheckStatus = "error"
          root.pluginCheckError = (parsed && parsed.error) || "check failed"
          return
        }
        root.pluginsUpToDate = !!parsed.upToDate
        root.pluginChangedIds = Array.isArray(parsed.changedPlugins) ? parsed.changedPlugins : []
        root.pluginCheckStatus = "checked"
      }
    }
  }

  function checkForUpdates() {
    if (root.ruixenRepoPath === "" || root.pluginCheckStatus === "checking") return
    root.pluginCheckStatus = "checking"
    root.pluginCheckError = ""
    var safePath = root.ruixenRepoPath.replace(/'/g, "'\\''")
    checkUpdatesProc.command = ["bash", "-c", "cd '" + safePath + "' && ./update.sh --check-json"]
    checkUpdatesProc.running = true
  }

  // Full uninstall -- ported back in now that About (its real home,
  // same as ruixen.settings' own page) exists. Runs this repo's own
  // uninstall.sh, which reverses everything install.sh did: switches
  // back to the built-in Omarchy bar, removes every ruixen.* plugin's
  // files for real (omarchy-plugin-remove itself only backs a cp -r'd
  // plugin up to a hidden .{id}.bak.<timestamp> folder rather than
  // deleting it, so uninstall.sh explicitly deletes those backups too
  // afterward), restores the real pre-install looknfeel.lua (or
  // Omarchy's own default if there was none), and restarts the shell.
  //
  // Deliberately fired via Quickshell.execDetached, not a lifecycle-
  // bound Process like updateProc above -- the script's own last real
  // step disables/removes ruixen.launcher itself (this very plugin),
  // which would tear down this QML instance (and, plausibly, any
  // Process objects it owns) mid-script if that happened before the
  // script finished. execDetached exists specifically to survive
  // exactly that, the same reason Wi-Fi/Bluetooth's own actions
  // already use it.
  readonly property string uninstallConfirmPhrase: "CONFIRM UNINSTALL"
  property string uninstallConfirmInput: ""

  function confirmFullUninstall() {
    if (root.ruixenRepoPath === "" || root.uninstallConfirmInput !== root.uninstallConfirmPhrase) return
    var safePath = root.ruixenRepoPath.replace(/'/g, "'\\''")
    Quickshell.execDetached(["bash", "-c", "cd '" + safePath + "' && ./uninstall.sh"])
  }
}
