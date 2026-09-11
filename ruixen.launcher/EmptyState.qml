import QtQuick

// Issue #57: extracted from Launcher.qml verbatim (two originally-
// separate sibling children of `card` -- the "no results" block and
// the degraded-but-has-results corner note -- bundled here since both
// exist only to communicate the same underlying condition). Instantiate
// spanning the exact same region the original "no results" Item did
// (top: searchHeader.bottom, bottom/left/right: card's own edges) --
// the corner note below relies on that to land in card's real
// bottom-right corner, not just this component's own local bounds.
Item {
  id: root

  // Search Files ONLY, deliberately -- see Launcher.qml's own
  // showNoResults comment for why the main Results view never shows
  // this (it always has its own "Use ... with" fallback row instead).
  property bool showNoResults: false
  // Issue #55: a genuinely empty result and a search that never
  // actually finished (a timed-out or failed root) used to render
  // identically -- see Launcher.qml's own filesSearchDegraded comment.
  property bool degraded: false
  // Whether a specific source (not "All Sources") is the active
  // filter -- singular vs plural wording below.
  property bool sourceSelected: false
  property color mutedColor: "#888888"
  property string fontFamily: ""

  // Empty state -- centered in the whole content area below the
  // search box (spans the full card width, not just the list column,
  // so it reads the same whether or not the details panel would
  // otherwise be showing beside it). Same magnifying-glass glyph
  // (fa-search, U+F002) as the Search Files fallback row's own icon,
  // just large -- a found-nothing state reading as "the search itself"
  // rather than needing a distinct icon of its own.
  Item {
    visible: root.showNoResults
    anchors.fill: parent

    Column {
      anchors.centerIn: parent
      spacing: 10

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: ""
        color: root.mutedColor
        font.family: root.fontFamily
        font.pixelSize: 40
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        // Issue #55: a genuinely empty result reads as "No Results"
        // same as always; a result that's empty because a root timed
        // out or failed says so instead, rather than falsely implying
        // a successful, complete search found nothing. "This source"
        // (singular) when one specific source was selected and it's
        // the one that failed -- "Some sources" for the All Sources
        // case, where other roots may still have searched fine.
        text: root.degraded
          ? (root.sourceSelected ? "This source could not be searched" : "Some sources could not be searched")
          : "No Results"
        color: root.mutedColor
        font.family: root.fontFamily
        font.pixelSize: 14
      }
    }
  }

  // Issue #55: a small, unobtrusive note for the "results exist, but
  // one source is degraded" case -- the empty-state block above only
  // covers when there are NO results at all. Direct product guidance
  // was to keep this minimal (a small note, not an elaborate status
  // system) -- a corner overlay rather than reflowing resultsList/
  // detailsPanel to make room for it, so there's no layout risk to
  // either.
  Text {
    visible: root.degraded && !root.showNoResults
    anchors.bottom: parent.bottom
    anchors.bottomMargin: 10
    anchors.right: parent.right
    anchors.rightMargin: 16
    text: root.sourceSelected ? "This source could not be fully searched" : "Some sources could not be searched"
    color: root.mutedColor
    font.family: root.fontFamily
    font.pixelSize: 10
  }
}
