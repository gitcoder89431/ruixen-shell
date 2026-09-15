import QtQuick

// Shared GEOMETRY ONLY for every "2-panel" extension (a left list + a
// right detail pane) -- direct follow-up after Settings shipped with
// its own hand-rolled sizing, THEN a Loader/Component version of this
// file that quietly broke font propagation: "why did you port it over
// from the ruixen settings menu... wouldnt it be a lot easier to just
// make a list of stuff like a list component from file search thats
// shared?" Two real course-corrections landed here:
//
// 1. The actual LIST is just ResultsList/ResultRow, reused directly by
// SettingsContent.qml (filesMode: true, same icon+label-only row
// shape Search Files itself renders) -- not reinvented here, and not
// funneled through this file either. This component's only job is
// deciding the two panes' WIDTHS and drawing the divider between them;
// it has no opinion on what's inside either one.
//
// 2. No Loader/Component/dynamic-property-injection layer -- that
// indirection was the actual root cause of a real bug (a one-time
// `item.prop = root.prop` copy in a Loader's onLoaded, confirmed live,
// meant the loaded content's font silently never tracked
// root.fontFamily, since it was a snapshot, not a binding). This
// component exposes its two panes as plain child Items instead
// (leftPane/rightPane); the caller reparents its real content into
// them (`parent: someExtensionTwoPanel.leftPane`) and binds colors/
// fonts directly off its OWN root, the exact same way every other file
// in this plugin already does -- no new mechanism to get subtly wrong.
//
// Same geometry Search Files' own resultsList/detailsPanel split
// (Launcher.qml) already uses -- the 8px gap the divider sits centered
// in, and the 60/40 detail/list ratio FileDetailsPanel.qml's own
// comment already documents. The list-left/detail-right 8px insets
// themselves stay the CALLER's own outer anchors (see availableWidth
// below) -- exactly like resultsList/detailsPanel, which apply theirs
// directly against the card rather than against a further-inset
// wrapper. Wallpapers stays its own thing on purpose -- a grid-flow
// extension is a genuinely different shape, not a 2-panel layout with
// different numbers, so it isn't forced through this component.
Item {
  id: root

  // Same 0.6 FileDetailsPanel.qml's own comment already settled on
  // ("a real 1:3 split turned out too extreme... 0.6 still gives this
  // panel the larger, featured share without starving the list").
  property real detailRatio: 0.6

  readonly property alias leftPane: leftContainer
  readonly property alias rightPane: rightContainer

  // The only inset genuinely internal to this component is the 8px
  // gap between the two panes, which the divider sits centered in --
  // the list's own left inset and the detail pane's own right inset
  // are the caller's job (its own outer anchors), same as
  // resultsList/detailsPanel themselves.
  readonly property real availableWidth: root.width - 8
  readonly property real listWidth: root.availableWidth * (1 - root.detailRatio)
  readonly property real detailWidth: root.availableWidth * root.detailRatio

  Item {
    id: leftContainer
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    anchors.left: parent.left
    width: root.listWidth
  }

  // Same vertical gradient divider Launcher.qml itself draws between
  // resultsList and detailsPanel in Search Files mode -- centered in
  // the 8px gutter between the two panes, identical treatment.
  Rectangle {
    anchors.top: leftContainer.top
    anchors.bottom: leftContainer.bottom
    anchors.left: leftContainer.right
    anchors.leftMargin: 4
    width: 1
    gradient: Gradient {
      GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0) }
      GradientStop { position: 0.3; color: Qt.rgba(1, 1, 1, 0.12) }
      GradientStop { position: 0.7; color: Qt.rgba(1, 1, 1, 0.12) }
      GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0) }
    }
  }

  // Ghost -- no surface of its own, same "ghost it on the spotlight"
  // treatment FileDetailsPanel.qml already gives Search Files' own
  // detail pane. Left for the caller's content to actually paint.
  Item {
    id: rightContainer
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    anchors.right: parent.right
    width: root.detailWidth
  }
}
