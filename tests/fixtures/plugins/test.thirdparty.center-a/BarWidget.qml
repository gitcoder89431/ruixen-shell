import QtQuick
import qs.Ui

// Minimal fake third-party bar-widget fixture -- see
// tests/fixtures/plugins/README.md. Fixed 60px width, and reads an
// inline "label" setting (settings: {"label": "..."} in shell.json) to
// prove per-widget inline settings pass through the host unchanged.
BarWidget {
  id: root
  moduleName: "test.thirdparty.center-a"

  implicitWidth: 60
  implicitHeight: 24

  Rectangle {
    anchors.fill: parent
    radius: 4
    color: "#52e0a8"

    Text {
      anchors.centerIn: parent
      text: root.setting("label", "CA")
      color: "#0a2318"
      font.pixelSize: 12
    }
  }
}
