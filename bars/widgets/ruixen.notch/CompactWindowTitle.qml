import QtQuick

Item {
  id: root

  property string text: ""
  property alias font: titleLabel.font
  property alias color: titleLabel.color

  // Codex's ten braille spinner frames occupy the upper three rows of
  // an eight-dot cell. Sharing the title's baseline leaves them raised.
  // Split only this leading spinner; ordinary window titles stay intact.
  readonly property var spinnerMatch: text.match(/^([\u280b\u2819\u2839\u2838\u283c\u2834\u2826\u2827\u2807\u280f])(\s+)(.+)$/)
  readonly property bool hasSpinner: spinnerMatch !== null

  TextMetrics {
    id: letterMetrics
    font: titleLabel.font
    text: "M"
  }
  TextMetrics {
    id: spinnerMetrics
    font: titleLabel.font
    // Measure the whole six-dot grid, never the current frame: sparse
    // frames must rotate in place rather than bob up and down.
    text: "\u283f"
  }
  readonly property real spinnerBaselineShift:
    letterMetrics.tightBoundingRect.y + letterMetrics.tightBoundingRect.height / 2
    - spinnerMetrics.tightBoundingRect.y - spinnerMetrics.tightBoundingRect.height / 2

  Item {
    anchors.horizontalCenter: parent.horizontalCenter
    width: Math.min(root.width, titleLabel.implicitWidth + (root.hasSpinner ? spinnerLabel.implicitWidth : 0))
    height: root.height

    Text {
      id: spinnerLabel
      visible: root.hasSpinner
      text: root.hasSpinner ? root.spinnerMatch[1] + root.spinnerMatch[2] : ""
      textFormat: Text.PlainText
      font: titleLabel.font
      color: titleLabel.color
      anchors.baseline: titleLabel.baseline
      anchors.baselineOffset: root.spinnerBaselineShift
    }

    Text {
      id: titleLabel
      x: root.hasSpinner ? spinnerLabel.implicitWidth : 0
      width: Math.max(0, parent.width - x)
      height: parent.height
      text: root.hasSpinner ? root.spinnerMatch[3] : root.text
      textFormat: Text.PlainText
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
      elide: Text.ElideRight
    }
  }
}
