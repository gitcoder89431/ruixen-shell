import QtQuick
import Quickshell
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
    readonly property int cornerRadius: 24

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
            antialiasing: true

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
