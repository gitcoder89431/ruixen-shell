import QtQuick

// The saved legacy sharp+docked full-strip look: the dock is one
// continuous surface spanning the whole bar width, no notch cutout.
// Reachable only via bar.style="fullbar" in shell.json -- curvature
// alone must not select it.
//
// Part of the docked-skin contract added in issue #78 Phase 6 (stage 5)
// to retire `barStyle`/`fullbarStyle` as a boolean threaded through
// scattered branches across Bar.qml/FrameWindow.qml. See
// NotchDockedSkin.qml's own comment for why this is a plain QtObject
// with no back-reference and no visual items.
QtObject {
  // See NotchDockedSkin's own comment -- true here, the dock is one
  // continuous strip with no open notch gap to split around.
  readonly property bool dockSpansFullWidth: true
}
