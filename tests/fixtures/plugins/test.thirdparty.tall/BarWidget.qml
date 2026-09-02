import QtQuick
import qs.Ui

// Minimal fake third-party bar-widget fixture -- see
// tests/fixtures/plugins/README.md. Deliberately 48px tall (bigger than
// ruixen.bar's own barSize of 34) -- the other fixtures are a uniform 24px,
// which centers inside a 34px row with no visible slack either way and so
// can't actually expose a vertical-centering bug (#29). This one is taller
// than the row on purpose, so a wrong anchor (top-aligned instead of
// center-aligned, or centered on the wrong baseline) becomes visible.
BarWidget {
  id: root
  moduleName: "test.thirdparty.tall"

  implicitWidth: 40
  implicitHeight: 48

  Rectangle {
    anchors.fill: parent
    radius: 4
    color: "#e05286"

    Text {
      anchors.centerIn: parent
      text: "T"
      color: "#ffffff"
      font.pixelSize: 12
    }
  }
}
