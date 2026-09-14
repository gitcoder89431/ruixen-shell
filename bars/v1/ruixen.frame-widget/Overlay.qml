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
