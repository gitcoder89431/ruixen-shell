import QtQuick

// A Loader that mounts a Row/Column of ModuleSlot per entries array.
//
// Extracted out of Bar.qml (issue #78 Phase 6 -- stage 4) as a pure file
// move: this was previously `component ModuleList: Loader { ... }`
// declared inline inside Bar.qml's own `Item { id: root }`. barRoot is
// the explicit back-reference the one `root.foo` read was rewritten to
// go through, wired at each of this component's instantiation sites
// (`barRoot: <the enclosing scope's own barRoot>`). No behavior change
// from this move.
Loader {
  id: moduleListRoot

  required property Item barRoot
  property var entries: []
  property string region: ""

  visible: entries.length > 0
  // A hidden list must not build its modules. The center section declares
  // both an anchored and an unanchored arrangement and shows whichever
  // fits, so leaving the other one loaded mounts every center module
  // twice — two IPC handlers registered for the same target, two clocks
  // ticking, two of every timer and fetch behind them.
  active: visible && entries.length > 0
  sourceComponent: moduleListRoot.barRoot.vertical ? verticalModuleList : horizontalModuleList
  width: item ? item.implicitWidth : 0
  height: item ? item.implicitHeight : 0

  Component {
    id: horizontalModuleList

    Row {
      spacing: 0

      Repeater {
        model: moduleListRoot.entries

        ModuleSlot {
          required property var modelData
          entry: modelData
          region: moduleListRoot.region
          barRoot: moduleListRoot.barRoot
        }
      }
    }
  }

  Component {
    id: verticalModuleList

    Column {
      spacing: 0

      Repeater {
        model: moduleListRoot.entries

        ModuleSlot {
          required property var modelData
          entry: modelData
          region: moduleListRoot.region
          barRoot: moduleListRoot.barRoot
        }
      }
    }
  }
}
