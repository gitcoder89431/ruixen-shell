import QtQuick
import "OmarchyMenuParser.js" as OmarchyMenuParser

// Issue #57: extracted verbatim from Launcher.qml's own ListView
// delegate. A ListView delegate can be any Item type, so this can be a
// full standalone component (`delegate: ResultRow { ... }` in
// ResultsList.qml) rather than an inline anonymous Rectangle -- no
// change to how ListView itself instantiates/recycles it. Every
// `root.` reference from the original inline delegate is now either a
// property this component exposes (passed in from ResultsList.qml,
// which itself receives them from Launcher.qml) or one of the two
// signals below, bubbled up to whoever owns selectedIndex/activation.
Rectangle {
  id: row
  required property var modelData
  required property int index

  property int selectedIndex: -1
  property bool filesMode: false
  property color textColor: "#ffffff"
  property color mutedColor: "#888888"
  property color accentColor: "#ffffff"
  property string fontFamily: ""
  property int rowHeightPx: 44
  property int rowWidth: 0
  property var appLibrary: null

  signal hovered(int index)
  signal activated(int index)
  // Issue #62 follow-up: right-click opens the contextual actions menu
  // for this row directly, alongside Tab (which operates on whichever
  // row is already selected) -- a second, mouse-first path to the same
  // menu, not a replacement for it.
  signal actionsRequested(int index)

  width: row.rowWidth
  height: row.rowHeightPx
  radius: 10
  // Row itself stays a plain transparent hit-box, full width (icon/
  // text below still anchor off ITS edges, unaffected) -- the actual
  // highlight fill is the separate, inset Rectangle below instead.
  // Direct report: the highlight used to fill row's own full width,
  // right up against the list/details separator (only the
  // resultsList-to-separator 4px gap stood between them, reading as
  // "too close"). 6px on both sides now, matching left/right for
  // balance.
  color: "transparent"

  Rectangle {
    anchors.fill: parent
    anchors.leftMargin: 6
    anchors.rightMargin: 6
    radius: row.radius
    // Direct feedback: a flat white fill reads fine over a dark
    // backdrop but gets too bright over a lighter one -- alpha
    // blending with white always brightens by a fixed amount
    // regardless of what's underneath, so it can't help swinging
    // wildly with whatever's behind the glass. A themed accent tint
    // (same hue the whole card's own glassTint already uses) at a
    // lower fill alpha, PLUS a crisp accent border, keeps the row
    // clearly legible via its own edge/hue rather than leaning on raw
    // brightness -- steadier across backdrops than a brightness-only
    // highlight can be.
    color: row.index === row.selectedIndex ? Qt.rgba(row.accentColor.r, row.accentColor.g, row.accentColor.b, 0.14) : "transparent"
    border.width: row.index === row.selectedIndex ? 1 : 0
    border.color: Qt.rgba(row.accentColor.r, row.accentColor.g, row.accentColor.b, 0.45)
  }

  // Omarchy Actions: a Nerd Font glyph. Applications: a real icon via
  // the shared AppLibrary instance -- same branch-on-provider split
  // LauncherContent.qml's own tilesAreApps already uses for the
  // identical reason (two different icon sources, one Image + one
  // fallback Text).
  Image {
    id: appIcon
    visible: row.modelData.providerId === "app-search" && status === Image.Ready
    anchors.left: parent.left
    anchors.leftMargin: 12
    anchors.verticalCenter: parent.verticalCenter
    width: 22
    height: 22
    sourceSize: Qt.size(22, 22)
    asynchronous: true
    source: row.modelData.providerId === "app-search" && row.appLibrary ? row.appLibrary.iconSource(row.modelData.icon) : ""
  }

  Text {
    visible: row.modelData.providerId !== "app-search"
    anchors.left: parent.left
    anchors.leftMargin: 12
    anchors.verticalCenter: parent.verticalCenter
    width: 22
    horizontalAlignment: Text.AlignHCenter
    text: row.modelData.icon
    // Folders (Search Files only -- Commands/Applications never have
    // kind "Folder") pick up the active theme's own accent color, same
    // as every other accent-colored element in this repo's own theme
    // convention -- files stay the plain textColor every other icon
    // uses.
    color: row.modelData.kind === "Folder" ? row.accentColor : row.textColor
    font.family: row.fontFamily
    font.pixelSize: 16
  }

  // Shrinks to the label's own content again, but WITHOUT measuring
  // rendered text at all this time -- both earlier attempts did that
  // and both broke: implicitWidth off a Text that also elides is a
  // real, documented Qt Quick "Binding loop detected for property
  // width" gotcha, and a sibling TextMetrics (the usual fix for that
  // gotcha) hit a worse bug -- ListView recycles delegates, and
  // TextMetrics.width lagged a stale measurement from whatever row
  // PREVIOUSLY occupied this recycled delegate, truncating every label
  // regardless of its own actual length. Since the font here is
  // monospace (JetBrainsMono Nerd Font), label.length times a fixed
  // per-character advance is a good enough estimate of the real
  // rendered width -- pure arithmetic on a string, no layout-engine
  // measurement involved, so neither bug can recur. elide still
  // absorbs any small over/under-estimate. In Search Files mode
  // there's no subtitle/kind at all (see metaText/kindText below), so
  // the label just takes the whole row regardless.
  readonly property real charWidth: 8
  Text {
    id: labelText
    anchors.left: parent.left
    anchors.leftMargin: 44
    anchors.verticalCenter: parent.verticalCenter
    width: row.filesMode
      ? (parent.width - 44 - 12)
      : Math.min(row.modelData.label.length * row.charWidth + 4, parent.width * 0.55 - 44)
    elide: Text.ElideRight
    text: row.modelData.label
    color: row.textColor
    font.family: row.fontFamily
    font.pixelSize: 13
  }

  // Subtitle beside the name -- Applications: AppSearchProvider's own
  // category (the app's genericName, e.g. "Web Browser", falling back
  // to a bare "Application"). Omarchy Actions / any future native
  // Ruixen provider: the full breadcrumb (e.g. "Remove › Development",
  // "Ruixen" for the synthetic Ruixen Settings row). Bounded on the
  // right by kindText below, not the row's own edge, so the two never
  // overlap. Hidden in Search Files mode -- the details panel's own
  // "Where" field already shows the path, so repeating it here (and
  // the Folder/File kind tag below, already obvious from the row's own
  // icon) would just be noise; the row is just an icon + name there, on
  // purpose, so the details panel is the featured part of that view,
  // not a third column squeezed beside it.
  Text {
    id: metaText
    visible: !row.filesMode
    anchors.left: labelText.right
    anchors.leftMargin: 8
    anchors.verticalCenter: parent.verticalCenter
    elide: Text.ElideRight
    // Hugs its own actual text width (capped to whatever room is left
    // before kindText, minus keybindHint's own width when it's
    // showing) instead of stretching all the way to kindText's own
    // column -- direct request: the keybind chips should sit right
    // after the visible subtitle text, not pinned flush against the
    // far-right kind tag with a dead gap in between for every short
    // subtitle (which is most of them). Non-circular: keybindHint's
    // own width never depends on metaText's, only the other way
    // around.
    width: Math.max(0, Math.min(implicitWidth,
      kindText.x - (labelText.x + labelText.width) - 8
        - (keybindHint.visible ? keybindHint.width + 8 : 0) - 8))
    text: row.modelData.providerId === "app-search" ? row.modelData.category : row.modelData.breadcrumb
    color: row.mutedColor
    font.family: row.fontFamily
    font.pixelSize: 10
  }

  // Existing Omarchy keybind hint, right after the subtitle -- many
  // Omarchy Actions/native Ruixen rows already have a real Hyprland
  // keybind configured (this launcher's own suggestions list is itself
  // built from that same catalog), so surfacing it here saves a trip
  // to Omarchy's own keybindings menu. OmarchyActionsProvider's own
  // keybindFor() already resolves personal-vs-stock priority (only one
  // is ever shown -- no room for both, direct product decision).
  // Rendered as actual key-cap chips (one small bordered chip per key,
  // same visual as the search box's own Enter-hint chip) rather than
  // spelled-out text ("SUPER + SHIFT + Z") -- direct request: "[KBD] +
  // [KBD] + [A] or something". SUPER/SHIFT/CTRL/ALT get their own real
  // keycap symbol via keySymbol(); everything else (a letter, digit, or
  // named key) shows as its own plain uppercase chip. App Search/
  // Search Files rows simply never carry a keybind field, so this
  // renders nothing for them.
  Row {
    id: keybindHint
    visible: !row.filesMode && !!row.modelData.keybind
    anchors.left: metaText.right
    anchors.leftMargin: 8
    anchors.verticalCenter: parent.verticalCenter
    spacing: 3
    opacity: 0.75

    Repeater {
      model: row.modelData.keybind ? OmarchyMenuParser.keybindParts(row.modelData.keybind) : []

      Rectangle {
        id: keyCap
        required property string modelData
        height: 18
        width: Math.max(18, capText.implicitWidth + 9)
        radius: 5
        color: Qt.rgba(1, 1, 1, 0.06)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.12)

        Text {
          id: capText
          anchors.centerIn: parent
          text: OmarchyMenuParser.keySymbol(keyCap.modelData)
          color: row.mutedColor
          font.family: row.fontFamily
          font.pixelSize: 9
        }
      }
    }
  }

  // Kind tag -- "Command" for every Omarchy Actions/native Ruixen row,
  // "Application" for App Search -- pinned to the row's own right
  // edge, kept separate from the breadcrumb/category subtitle above
  // rather than folded into one string, so it stays in a stable,
  // scannable column even as the subtitle's own length varies row to
  // row. Hidden in Search Files mode -- see metaText's own comment
  // above.
  Text {
    id: kindText
    visible: !row.filesMode
    anchors.right: parent.right
    anchors.rightMargin: 12
    anchors.verticalCenter: parent.verticalCenter
    horizontalAlignment: Text.AlignRight
    elide: Text.ElideRight
    width: 72
    text: row.modelData.providerId === "app-search" ? "Application" : row.modelData.kind
    color: row.mutedColor
    font.family: row.fontFamily
    font.pixelSize: 10
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: Qt.PointingHandCursor
    onEntered: row.hovered(row.index)
    onClicked: (mouse) => {
      if (mouse.button === Qt.RightButton) row.actionsRequested(row.index)
      else row.activated(row.index)
    }
  }
}
