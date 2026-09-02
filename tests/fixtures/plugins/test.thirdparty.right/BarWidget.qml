import QtQuick
import qs.Ui

// Minimal fake third-party bar-widget fixture -- see
// tests/fixtures/plugins/README.md. Fixed 40px width, plain box.
BarWidget {
  id: root
  moduleName: "test.thirdparty.right"

  implicitWidth: 40
  implicitHeight: 24

  Rectangle {
    anchors.fill: parent
    radius: 4
    color: "#5286e0"

    Text {
      anchors.centerIn: parent
      text: "R"
      color: "#ffffff"
      font.pixelSize: 12
    }
  }
}
