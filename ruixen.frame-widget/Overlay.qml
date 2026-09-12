import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Ported from REPOS/PLUGINS/quickshell-mocha-v2's Frame.qml FrameMaskCanvas —
// same rounded-hole-punch technique, stripped of the notch/dock/theme-JSON
// machinery that came with it. Fills the screen with frameColor, then punches
// a rounded-rect hole out of the middle (destination-out compositing),
// leaving a colored border with rounded inner corners.
//
// The PanelWindow + WlrLayershell setup mirrors the built-in Emojis.qml
// overlay plugin — a plugin has to create its own layer-shell surface,
// the shell doesn't hand it screen geometry for free.

Item {
    id: root

    property var shell: null
    property var manifest: null

    readonly property color frameColor: "#000000"
    readonly property int thickness: 6
    // Was a hardcoded 24 -- real bug, found live while adding a 3rd
    // look'n'feel variant (hyprland/looknfeel.square.lua, 0 rounding):
    // this frame's own corner mask never actually matched whatever
    // Hyprland's real window rounding was, it just always assumed
    // looknfeel.ruixen.lua's 24px. That silently mismatched for
    // "off" (0 rounding) too, already, before "square" ever existed --
    // a real window's square corner got partly painted over by this
    // frame's still-rounded hole, reading as "the bottom corner clips
    // under the shell frame".
    //
    // Direct follow-up, later the same session: square only when BOTH
    // floating AND sharp -- docked mode stays curved regardless of
    // curvature. Docked's own gaps (hyprland/looknfeel.square.lua's
    // gaps_out bump) already keep a real window's corner well clear of
    // this frame's curve there, so there's no clipping risk to avoid by
    // going square in docked mode -- direct request: "dont remove the
    // curve from sharp and dock... i think the only one that doesnt
    // use it and have it off is floating and sharp."
    // Defaults chosen to keep cornerRadius at 0 (square) until both
    // reads below resolve -- matches this property's own original
    // safe-failure direction (a square hole under an actually-rounded
    // window just leaves a transparent sliver of wallpaper, not this
    // frame's own color painted over real window content).
    property bool isSquareVariant: true
    property bool isDocked: false
    readonly property int cornerRadius: (!isDocked && isSquareVariant) ? 0 : 24

    Process {
        id: readLookAndFeelVariant
        command: ["bash", "-c", "readlink \"$HOME/.config/hypr/looknfeel.lua\" 2>/dev/null"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                root.isSquareVariant = text.indexOf("looknfeel.square.lua") >= 0
            }
        }
    }

    Process {
        id: readBarMode
        command: ["bash", "-c", "python3 -c \"import json; d=json.load(open('" + Quickshell.env("HOME") + "/.config/omarchy/shell.json')); print('docked' if d.get('bar',{}).get('docked') is True else 'floating')\" 2>/dev/null || echo floating"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                root.isDocked = String(text || "").trim() === "docked"
            }
        }
    }

    // ruixen.sidepanel's own left-edge exclusive zone -- this frame is a
    // separate full-screen overlay with no knowledge of that reservation
    // on its own, so its border/curve stayed put at the physical screen
    // edge while the panel pushed everything else in. Direct report from
    // trying that live: "that fucked up our frame pretty badly... can
    // the frame move in too?" Reads the same on-disk flag
    // ruixen.sidepanel writes on every toggle (same shared-flag-file
    // convention as barHidden between ruixen.bar/ruixen.notch, not a
    // direct cross-plugin call) and runs its OWN local animation off it,
    // timed to match ruixen.sidepanel's own Behavior (280ms/OutCubic) so
    // the two edges appear to move together.
    readonly property string sidepanelStateDir: Quickshell.env("HOME") + "/.local/state/ruixen"
    readonly property string sidepanelStatePath: root.sidepanelStateDir + "/sidepanel-open"
    // Mirrors ruixen.sidepanel/Overlay.qml's own panelWidth -- keep in
    // sync if that one ever changes.
    readonly property int sidepanelWidth: 320
    property bool sidepanelOpen: false
    property real leftInset: 0
    Behavior on leftInset {
        // Matches ruixen.sidepanel's own Behavior duration -- keep in
        // sync if that one changes (direct follow-up after the first
        // 280ms pass read as stuttery: animating a real exclusive-zone
        // reservation forces Hyprland to reflow tiled windows on every
        // step, so fewer/faster steps reads snappier rather than
        // smoother -- there's no tuning that makes it buttery on top of
        // real relayout work).
        NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
    }
    onSidepanelOpenChanged: root.leftInset = root.sidepanelOpen ? root.sidepanelWidth : 0

    // Watches the FILE directly, not its parent directory -- direct bug
    // hit live ("when i dismiss the panel the desktop frame... stuck in
    // the middle, it didnt move back out"). barHidden's own directory-
    // watch trick (see the comment above) only exists because that flag
    // is a file that gets CREATED/DELETED (touch/rm) -- a directory
    // watch reliably catches entries appearing/disappearing but not a
    // plain content overwrite of a file that already exists, which is
    // exactly what ruixen.sidepanel's toggle does here (same inode,
    // rewritten 1/0 each time). Watching the file's own path is the
    // right tool for that -- same reactive FileView convention already
    // used for dashboardStyle/animationProfile/etc.
    FileView {
        path: root.sidepanelStatePath
        watchChanges: true
        printErrors: false
        onLoaded: root.sidepanelOpen = text().trim() === "1"
        onLoadFailed: root.sidepanelOpen = false
        onFileChanged: reload()
    }

    Component.onCompleted: {
        readLookAndFeelVariant.running = true
        readBarMode.running = true
    }
    // Canvas.onPaint is a plain JS function, not a reactive binding --
    // it never re-runs on its own just because cornerRadius changes
    // once the Processes above finish (same class of bug already
    // fixed for the notch's own volume dials this same session).
    onCornerRadiusChanged: canvas.requestPaint()

    // Real fullscreen-state watching, not a layer trick -- this stays on
    // WlrLayer.Overlay (see ruixen.notch's own Overlay.qml for why: Top
    // caused click-stacking contention with ruixen.bar's own top-layer
    // surface), so a fullscreen window would otherwise never cover it.
    // ToplevelManager.activeToplevel.fullscreen is the same Wayland
    // foreign-toplevel property Omarchy's own ActiveWindow.qml reads.
    readonly property bool fullscreenActive: ToplevelManager.activeToplevel
      ? ToplevelManager.activeToplevel.fullscreen : false

    PanelWindow {
        id: panel
        visible: !root.fullscreenActive
        anchors { top: true; bottom: true; left: true; right: true }
        // Shrinks this surface's own left edge inward to match
        // ruixen.sidepanel's reservation, instead of painting over it --
        // this window's canvas simply doesn't extend into that region
        // any more, same technique ruixen.bar/ruixen.sidepanel already
        // use to move their own edges (a live layer-shell margin), not a
        // second hole punched into this one's own opaque fill (that
        // approach painted a big solid rectangle straight over the
        // panel's content instead, since this surface sits on
        // WlrLayer.Overlay, above the panel's own WlrLayer.Top).
        margins.left: root.leftInset
        color: "transparent"

        WlrLayershell.namespace: "ruixen-frame-widget"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore
        // Purely decorative, zero interactive elements — without this,
        // this full-screen topmost-layer surface swallows scroll/click
        // input for everything underneath (e.g. terminal scrollback),
        // even with no MouseArea in the QML. Matches the same `mask:
        // Region {}` pattern the built-in bar/osd plugins use.
        mask: Region {}

        Canvas {
            id: canvas
            anchors.fill: parent
            // False, not true: this hole-punch is a binary mask (fully
            // opaque frame vs. fully transparent hole), and Canvas
            // antialiasing leaves partial-alpha pixels along the hole's
            // edge (fractional shape coverage -> fractional erase in the
            // destination-out blend below). On an integer-scale display
            // those partial pixels round away and the seam is invisible;
            // on a fractional Hyprland monitor scale they can land wide
            // enough to read as a visible sliver of whatever's behind the
            // frame (the wallpaper) bleeding through -- reported as "white
            // artifact/leak at the top of the screen" on a machine this
            // repo couldn't reproduce on (fixed HDMI-A-1 @ scale 1). A hard
            // edge has no fractional coverage to leak.
            antialiasing: false

            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()

            function roundedRect(ctx, x, y, w, h, r) {
                const rr = Math.max(0, Math.min(r, w / 2, h / 2));
                ctx.beginPath();
                ctx.moveTo(x + rr, y);
                ctx.lineTo(x + w - rr, y);
                ctx.quadraticCurveTo(x + w, y, x + w, y + rr);
                ctx.lineTo(x + w, y + h - rr);
                ctx.quadraticCurveTo(x + w, y + h, x + w - rr, y + h);
                ctx.lineTo(x + rr, y + h);
                ctx.quadraticCurveTo(x, y + h, x, y + h - rr);
                ctx.lineTo(x, y + rr);
                ctx.quadraticCurveTo(x, y, x + rr, y);
                ctx.closePath();
            }

            onPaint: {
                const ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);

                ctx.fillStyle = root.frameColor;
                ctx.fillRect(0, 0, width, height);

                ctx.globalCompositeOperation = "destination-out";
                // No leftInset term here -- the PanelWindow's own
                // margins.left (see above) already moved this whole
                // surface's local (0,0) in to match, so plain
                // root.thickness on every side is still correct.
                roundedRect(
                    ctx,
                    root.thickness,
                    root.thickness,
                    width - root.thickness * 2,
                    height - root.thickness * 2,
                    root.cornerRadius
                );
                ctx.fill();
                ctx.globalCompositeOperation = "source-over";
            }
        }
    }
}
