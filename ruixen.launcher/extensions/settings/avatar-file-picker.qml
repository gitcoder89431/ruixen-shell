import QtQuick
import QtQuick.Window
import QtQuick.Dialogs

// Standalone, single-purpose picker -- spawned as a genuinely separate
// `qml6` process (env: GTK_USE_PORTAL=1 QT_FORCE_STDERR_LOGGING=1) by
// SettingsContent.qml's own avatarFileDialog Process, not run in-process
// via QtQuick.Dialogs' FileDialog directly. Direct fix after a real,
// reproducible crash (confirmed via coredumpctl + debuginfod
// symbolization, twice, byte-for-byte identical both times): this
// system's QT_QPA_PLATFORMTHEME=gtk3 routes an in-process FileDialog
// through GTK3's native chooser + GVfs's directory-monitor D-Bus call,
// which aborts inside glib's own g_variant_builder_end / g_malloc on a
// cold gvfsd start -- taking the WHOLE shell down with it since that
// code runs inside quickshell's own address space, several seconds of
// the entire desktop shell restarting every time. Running this exact
// same FileDialog in a separate, short-lived process instead means a
// crash here can never touch quickshell again -- worst case, this one
// small helper dies and the picker just doesn't open, instead of the
// whole desktop shell restarting. GTK_USE_PORTAL=1 (set by the caller,
// not here) additionally asks GTK3's own GtkFileChooserNative to route
// through the real xdg-desktop-portal instead of its own bundled
// GVfs-backed chooser in the first place -- a real, documented GTK env
// var for exactly this -- so this may avoid the crash outright, not
// just contain it.
//
// Prints a single marker line to STDERR (confirmed live: this system's
// Qt defaults console.log to the systemd journal instead of a real,
// capturable stream whenever JOURNAL_STREAM is set -- QT_FORCE_STDERR_
// LOGGING=1, set by the caller, is what makes this land on a real pipe
// instead) on accept; nothing on cancel.
//
// Window { visible: false }, not a plain Item -- direct live report: a
// blank white window opened alongside the real picker every time.
// qml6's own runtime auto-creates a default QQuickView/window to host a
// non-Window root item, since it needs SOMETHING to render a GUI app
// into -- that auto-created window is what was showing up empty. An
// explicit, already-invisible Window as the root sidesteps that
// entirely; FileDialog itself is still a real, separate native/portal
// window regardless of this one's own visibility.
Window {
  visible: false
  FileDialog {
    id: dlg
    title: "Choose Avatar Image"
    nameFilters: ["Images (*.png *.jpg *.jpeg *.gif *.webp *.bmp)"]
    onAccepted: {
      console.log("RUIXEN_AVATAR_PICK:" + String(selectedFile))
      Qt.quit()
    }
    onRejected: Qt.quit()
    Component.onCompleted: open()
  }
}
