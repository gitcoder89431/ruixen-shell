import QtQuick
import Quickshell
import Quickshell.Io
import "PluginModel.js" as PluginModel

// Issue #7 ("Split backend/state responsibilities out of oversized
// Settings.qml and Bar.qml"): the Plugins page's own list/toggle/
// update/uninstall backend, extracted verbatim out of Settings.qml --
// no behavior change, just moved. Settings.qml keeps thin pass-through
// aliases/wrappers on its own root (pluginRows, togglePluginEnabled(),
// etc.) so PluginsContent.qml's own settingsRoot.xxx calls need zero
// changes; only the implementation moved.
//
// Bundles list/toggle, whole-repo update, AND full-uninstall together
// (not three separate services) on purpose -- update and uninstall
// both key off the exact same ruixenRepoPath state and mutate the same
// pluginUpdateStatus/Error surface, so splitting them further would
// just be two objects constantly reaching into each other.
Item {
  id: root

  // Direct review finding ("this repo has no `git`-checkout-relative
  // way to answer 'am I up to date'"): omarchy plugin update itself
  // refuses against a real installed ruixen.* plugin (confirmed
  // directly: it refused with "not a git checkout") -- these are
  // cp -r'd from one shared monorepo checkout instead, so this repo's
  // own update.sh (git pull + reinstall) is the real update path, not
  // that command.
  property var pluginRows: []
  property string pluginBusyId: ""
  // Direct review finding ("Make rapid asynchronous Process actions
  // last-action-wins"): pluginActionProc below is ONE shared Process
  // across every row's own toggle, and reassigning a Quickshell
  // Process's command while it's already running does NOT cancel the
  // in-flight run -- confirmed directly -- it finishes, THEN the
  // reassigned command auto-fires. So toggling row A then quickly row
  // B doesn't lose either toggle (both really do run, in order), but
  // without this, pluginActionProc's own onExited had no way to tell
  // "did the run that just exited belong to the row currently marked
  // busy, or a stale run for a row that's since been superseded" --
  // it would clear pluginBusyId the moment ANY run exited, even A's,
  // while B's own toggle was still only QUEUED, not yet actually
  // running. Tracks the one genuinely-queued toggle (at most one can
  // ever be pending, matching Quickshell's own Process semantics) so
  // onExited only clears busy state once nothing is left queued.
  property string pluginActionPendingId: ""
  property string pluginUpdateStatus: ""
  property string pluginUpdateError: ""
  property string ruixenRepoPath: ""

  // Pure parsing/sorting/lockout logic lives in PluginModel.js (see
  // its own header comment) -- these are thin QML-facing wrappers.
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
      // A newer toggle is genuinely queued behind this one (Quickshell
      // will auto-fire it now that this run has exited) -- leave
      // pluginBusyId showing that row rather than clearing it, which
      // would flash "nothing busy" for a moment right before the
      // queued toggle actually starts.
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

  // Per-plugin remove was dropped entirely per direct follow-up ("why
  // not allow disable only and uninstall gets rid of everything as the
  // only option") -- disable already covers "don't want this running"
  // (instant, reversible), and actual file removal now lives
  // exclusively behind the danger-zone full uninstall's own typed
  // confirmation. A second, lighter-weight per-row way to delete files
  // was redundant with that, not a real safety improvement. See
  // uninstall.sh for the equivalent backup-cleanup reasoning that used
  // to live in a confirmRemovePlugin() here.

  // Repo path -- install.sh now writes its own checkout location to
  // this state file on every install/update run (added alongside this
  // feature, since nothing previously recorded it anywhere machine-
  // readable). Read fresh via bash so a missing file just yields an
  // empty string instead of a QML file-read error.
  Process {
    id: repoPathProc
    command: ["bash", "-c", "cat \"$HOME/.local/state/ruixen/repo-path\" 2>/dev/null"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.ruixenRepoPath = text.trim()
    }
  }

  // Thin trigger, not fired from in here -- the real condition (only
  // read while the settings panel is actually open, same moment
  // refreshPlugins() itself already runs) lives in Settings.qml's own
  // onOpenedChanged, unchanged from before this extraction.
  function refreshRepoPath() {
    repoPathProc.running = true
  }

  Process {
    id: updateProc
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        // A successful run never gets here to report success -- update.sh
        // ends with `omarchy restart shell`, which tears down and
        // reloads this very plugin instance before this handler would
        // ever fire. Only a failure that happens BEFORE that point
        // (network down, git pull conflict, etc.) leaves this instance
        // alive long enough to actually show the error.
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
    // one bash argument, rather than the nested-double-quote version
    // this first went out with (cd \"$(cat \\\"...\\\")\" -- readable
    // on paper but actually wrong: escaping the inner quotes with \\\"
    // stops them from acting as bash quoting at all inside $(...),
    // which already gets a fresh quoting context of its own).
    var safePath = root.ruixenRepoPath.replace(/'/g, "'\\''")
    updateProc.command = ["bash", "-c", "cd '" + safePath + "' && ./update.sh"]
    updateProc.running = true
  }

  // Full uninstall -- direct request, following a real Discord report
  // ("its currently hard to uninstall cleanly even with cli"). Runs
  // this repo's own new uninstall.sh, which reverses everything
  // install.sh did: switches back to the built-in Omarchy bar, removes
  // every ruixen.* plugin's files for real (omarchy-plugin-remove
  // itself only backs a cp -r'd plugin up to a hidden .{id}.bak.
  // <timestamp> folder rather than deleting it -- confirmed by reading
  // it directly -- so uninstall.sh explicitly deletes those backups
  // too afterward, per direct follow-up: "people want like a full
  // uninstall"), restores the real pre-install looknfeel.lua (or
  // Omarchy's own default if there was none), and restarts the shell.
  // See uninstall.sh's own comments for the full research behind each
  // step.
  //
  // Deliberately fired via Quickshell.execDetached, not a lifecycle-
  // bound Process like updateProc above -- the script's own last real
  // step disables/removes ruixen.settings itself, which would tear
  // down this very QML instance (and, plausibly, any Process objects
  // it owns) mid-script if that happened before the script finished.
  // execDetached exists specifically to survive exactly that, the same
  // reason Wi-Fi/Bluetooth's own actions already use it.
  readonly property string uninstallConfirmPhrase: "CONFIRM UNINSTALL"
  property string uninstallConfirmInput: ""

  function confirmFullUninstall() {
    if (root.ruixenRepoPath === "" || root.uninstallConfirmInput !== root.uninstallConfirmPhrase) return
    var safePath = root.ruixenRepoPath.replace(/'/g, "'\\''")
    Quickshell.execDetached(["bash", "-c", "cd '" + safePath + "' && ./uninstall.sh"])
  }
}
