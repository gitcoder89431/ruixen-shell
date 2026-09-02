import QtQuick
import qs.Ui

// Minimal fake third-party bar-widget fixture -- see
// tests/fixtures/plugins/README.md. Fixed 100px width, deliberately
// different from every other fixture here, so tests can prove the
// host doesn't assume a uniform widget size anywhere.
BarWidget {
  id: root
  moduleName: "test.thirdparty.center-b"

  implicitWidth: 100
  implicitHeight: 24

  Rectangle {
    anchors.fill: parent
    radius: 4
    color: "#c9a542"

    Text {
      anchors.centerIn: parent
      text: "center-b (100px)"
      color: "#241d05"
      font.pixelSize: 10
    }
  }
}
