import QtQuick

// The default docked-chrome look: the dock splits into a left group and
// a right group, leaving the notch's own reserved gap open between them.
//
// Part of the docked-skin contract added in issue #78 Phase 6 (stage 5)
// to retire `barStyle`/`fullbarStyle` as a boolean threaded through
// scattered branches across Bar.qml/FrameWindow.qml. Deliberately a
// plain QtObject exposing pure data -- no back-reference to the bar
// root, no visual items -- so a future third skin only needs to
// implement this same small, closed interface, and so the fragile
// Canvas/Connections pairing FrameWindow.qml's own dock-chrome shadow/
// fill rely on (see that file's own comment) never has to cross a file
// boundary to read a skin's own geometry.
QtObject {
  // Whether the docked strip is one continuous surface spanning the
  // full bar width (true, fullbar) or splits into independent left/
  // right groups around the notch's own open gap (false, notch --
  // this skin). Drives BarPanel's own leftDockedBg/rightDockedBg
  // width and corner-radius bindings, and root's own
  // reservedCenterRect() (fullbar reserves zero notch width, notch
  // style reserves the real one).
  readonly property bool dockSpansFullWidth: false
}
