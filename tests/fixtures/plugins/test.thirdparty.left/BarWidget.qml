import QtQuick
import qs.Ui

// Minimal fake third-party bar-widget fixture -- see
// tests/fixtures/plugins/README.md. Fixed 40px width, plain box.
BarWidget {
  id: root
  moduleName: "test.thirdparty.left"

  implicitWidth: 40
  implicitHeight: 24

  Rectangle {
    anchors.fill: parent
    radius: 4
    color: "#e05252"

    Text {
      anchors.centerIn: parent
      text: "L"
      color: "#ffffff"
      font.pixelSize: 12
    }
  }
}
