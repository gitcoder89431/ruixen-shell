import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

// Minimal from-scratch bar — workspaces + clock, nothing else.
//
// Deliberately does NOT use `required property` for omarchyPath /
// barWidgetRegistry / barConfig, unlike the built-in bar. Cloning the
// built-in bar (which does declare those required) and swapping to it via
// `omarchy bar use` crashed with "Required property X was not initialized"
// — the shell injects these via a later assignment (target.x = ...), not
// at creation time, which QML's `required` keyword doesn't accept. Plain
// defaults sidestep that; this is the test of that theory.

Item {
    id: root

    property string omarchyPath: Quickshell.env("OMARCHY_PATH")
    property var barWidgetRegistry: null
    property var barConfig: ({})
    property var shell: null
    property var manifest: null

    readonly property int barHeight: 26
    // ruixen.frame-widget draws one continuous rounded-rect shell around the
    // whole screen (all 4 corners) at thickness=6, cornerRadius=24. The bar
    // sits INSIDE that hole as plain content, not a shape with its own
    // corners — inset far enough (thickness + cornerRadius) that it never
    // reaches into the shell's rounded corner zone, so the shell's own
    // curve stays visible at the very top corners instead of getting
    // covered by a square-cornered bar.
    readonly property int frameThickness: 6
    readonly property int frameCornerRadius: 24
    // Deliberately not the frame's black — needs to contrast against the
    // shell's border, not blend into it.
    readonly property color barColor: "#15141b"

    PanelWindow {
        id: panel
        visible: true
        anchors { top: true; left: true; right: true }
        implicitHeight: root.barHeight
        color: "transparent"

        margins {
            top: root.frameThickness
            left: root.frameThickness
            right: root.frameThickness
        }

        WlrLayershell.namespace: "ruixen-bar"
        WlrLayershell.layer: WlrLayer.Top
        exclusionMode: ExclusionMode.Auto

        Rectangle {
            anchors.fill: parent
            color: root.barColor
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 8

            Row {
                id: workspaces
                spacing: 6
                Layout.alignment: Qt.AlignVCenter

                function ids() {
                    var list = [1, 2, 3, 4, 5];
                    var values = Hyprland.workspaces.values;
                    for (var i = 0; i < values.length; i++) {
                        var id = values[i].id;
                        if (id > 0 && id <= 10 && list.indexOf(id) === -1) list.push(id);
                    }
                    list.sort(function (a, b) { return a - b; });
                    return list;
                }

                Repeater {
                    model: workspaces.ids()

                    Item {
                        required property int modelData
                        readonly property bool focused: Hyprland.focusedWorkspace !== null
                            && Hyprland.focusedWorkspace.id === modelData

                        width: label.implicitWidth + 8
                        height: 20

                        Text {
                            id: label
                            anchors.centerIn: parent
                            text: parent.modelData
                            color: parent.focused ? "#8464c6" : "#bdbdbd"
                            font.pixelSize: 12
                            font.bold: parent.focused
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: Quickshell.execDetached(["hyprctl", "dispatch", "workspace", String(parent.modelData)])
                        }
                    }
                }
            }

            Item { Layout.fillWidth: true }

            Text {
                id: clockText
                Layout.alignment: Qt.AlignVCenter
                color: "#bdbdbd"
                font.pixelSize: 12

                function updateText() {
                    text = Qt.formatDateTime(new Date(), "ddd d  h:mm AP");
                }

                Component.onCompleted: updateText()

                Timer {
                    interval: 1000
                    running: true
                    repeat: true
                    onTriggered: clockText.updateText()
                }
            }
        }
    }
}
