import QtQuick
import Quickshell
import Quickshell.Io

// Quick app launcher -- a search box for finding any installed app,
// plus a row of pinned Omarchy system-menu actions shown while the
// search is empty (Lock, Power, etc.). Deliberately stays inside
// the exact same 420x190 launcherOpen footprint used by the old
// click-only grid below -- v1's own search box needed
// WlrKeyboardFocus.Exclusive (see panel's keyboardFocus above)
// AND a taller notch (340x260/etc) to fit a scrollable list, and
// that combination hit a real, non-deterministic bug in the
// notchBg masking (MultiEffect layer effect below) at taller
// heights. Only the keyboard-focus flip happens this time; no new
// size, so the resize half of that bad combination never occurs.
//
// Pinned actions run through Omarchy's own `omarchy menu summon
// <id>` CLI (launcherActionProc below) instead of duplicating any
// command strings here -- same id space as
// /usr/share/omarchy/default/omarchy/omarchy-menu.jsonc, so this
// can never drift out of sync with Omarchy's real menu. Edit
// pinnedActions below to change which ones show. App search reads
// shell.appLibrary.sortedEntries() -- real ranking (prefix match
// highest, then substring, then a bounded acronym fallback), not
// fuzzy/subsequence matching, confirmed by reading AppSearch.js.
//
// Both states share one Grid + Repeater (model swaps, tile visual
// stays identical) capped to a single row (6 tiles) -- deliberately
// not enough room for a second row within 190px alongside the
// search box, and no scrolling, so this stays a fast glance/click
// UI rather than growing into something that needs the taller,
// unproven notch size.
Item {
  id: launcherContent

  property var overlayRoot: null
  property var panel: null
  visible: panel.launcherOpen
  opacity: panel.launcherOpen ? 1 : 0
  anchors.centerIn: parent
  width: 410
  height: 190
  // Inner content (search box + tile row) sits at this width,
  // centered within the 410 footprint above -- leaves real side
  // padding so neither touches the notch's own curved edge.
  readonly property int contentWidth: 366
  Behavior on opacity { NumberAnimation { duration: 160 } }

  onVisibleChanged: {
    if (visible) {
      selectedIndex = 0
      // WlrLayershell.keyboardFocus: Exclusive only grants the
      // layer surface itself keyboard focus at the Wayland level
      // -- Qt Quick's own scene-graph focus is separate, and
      // nothing gets it by default. Same forceActiveFocus() call
      // ruixen.weather/Panel.qml already needs for its own search
      // field (startEditingLocation()); without it the TextInput
      // never receives typed characters despite the surface-level
      // grab succeeding.
      Qt.callLater(function() { launcherSearchInput.forceActiveFocus() })
    } else {
      launcherSearchInput.text = ""
      searchText = ""
    }
  }

  property string searchText: ""
  readonly property bool showingSearch: searchText.length > 0
  // "actions" (Omarchy system-menu shortcuts) or "favorites"
  // (pinned apps) -- which one the empty-search view shows.
  // Toggled by the button beside the search box.
  property string pinnedMode: "actions"
  // Arrow-key selection, matching ruixen.weather/Panel.qml's own
  // Keys.onPressed pattern (its locationField -- the closest real
  // precedent in this repo). Reset on every keystroke so a new
  // query always starts from the top match, and on open so a
  // stale selection from the last session never carries over.
  // Hovering a tile also claims this (see cardMouse.onEntered
  // below), so Ctrl+F/Ctrl+R act on "whichever tile is
  // highlighted" whether that got there by mouse or keyboard.
  property int selectedIndex: 0
  onSearchTextChanged: selectedIndex = 0

  // Glyphs copied verbatim from
  // /usr/share/omarchy/default/omarchy/omarchy-menu.jsonc so these
  // tiles match what Omarchy's own menu shows for the same ids.
  readonly property var pinnedActions: [
    { id: "system.lock", label: "Lock", icon: "" },
    { id: "system", label: "Power", icon: "" },
    { id: "learn.keybindings", label: "Keybind", icon: "" },
    { id: "trigger.capture.screenshot", label: "Screenshot", icon: "" },
    { id: "style.theme", label: "Theme", icon: "󰸌" },
    { id: "setup", label: "Settings", icon: "" }
  ]

  readonly property var searchResults: {
    if (!showingSearch || !overlayRoot.shell || !overlayRoot.shell.appLibrary) return []
    var rows = overlayRoot.shell.appLibrary.sortedEntries(searchText)
    var picked = []
    for (var i = 0; i < rows.length && picked.length < 6; i++) picked.push(rows[i].entry)
    return picked
  }

  // ---- Favorite apps: persisted list of desktop-entry ids, capped
  // at 6 so the single-row grid never overflows. Real
  // customization (the whole point of this rebuild -- see the
  // block comment above) instead of a hardcoded array: pin/unpin
  // from the UI (Ctrl+F, Ctrl+R, or right-click), same
  // FileView.setText() persistence pattern Omarchy's own
  // notifications service uses for its settings.json (confirmed
  // by reading plugins/notifications/Service.qml directly, not
  // guessed) -- debounced write, atomicWrites, a loaded guard so
  // the initial onLoaded/onLoadFailed race can't stomp state.
  readonly property string favoritesPath: Quickshell.env("HOME") + "/.local/state/ruixen/launcher-favorites.json"
  // Empty-state fallback shown only while the user has zero real
  // favorites of their own -- never written to favorites.json
  // (see favoriteEntries below). Every id here is a real package
  // in /usr/share/omarchy/install/omarchy-base.packages (confirmed
  // by reading that file, not guessed), so this reflects what a
  // fresh Omarchy install actually ships rather than one person's
  // personal app picks -- the exact problem the old hardcoded
  // favoriteAppIds array had. Desktop-entry ids confirmed against
  // /usr/share/applications/*.desktop.
  readonly property var defaultFavoriteAppIds: [
    "chromium", "foot", "org.gnome.Nautilus", "obsidian", "mpv", "com.obsproject.Studio"
  ]
  property var favoriteAppIds: []
  property bool favoritesLoaded: false
  // Brief override for the search placeholder when a 6th pin is
  // attempted -- reuses the existing placeholder text instead of
  // a separate warning element, so nothing else in the layout
  // shifts (a standalone message caused a visible jump).
  property bool favoritesFullHint: false

  function isFavorited(id) {
    return favoriteAppIds.indexOf(id) !== -1
  }

  function addFavorite(id) {
    if (!id || isFavorited(id)) return
    if (favoriteAppIds.length >= 6) {
      favoritesFullHint = true
      favoritesFullHintTimer.restart()
      return
    }
    favoriteAppIds = favoriteAppIds.concat([id])
    favoritesSaveTimer.restart()
  }

  function removeFavorite(id) {
    var idx = favoriteAppIds.indexOf(id)
    if (idx === -1) return
    var next = favoriteAppIds.slice()
    next.splice(idx, 1)
    favoriteAppIds = next
    favoritesSaveTimer.restart()
  }

  function loadFavorites(raw) {
    if (favoritesLoaded) return
    var ids = []
    try {
      var parsed = JSON.parse(raw)
      if (parsed && Array.isArray(parsed.ids)) ids = parsed.ids
    } catch (e) {}
    favoriteAppIds = ids.slice(0, 6)
    favoritesLoaded = true
  }

  function resolveEntries(ids) {
    if (!overlayRoot.shell || !overlayRoot.shell.appLibrary) return []
    var all = overlayRoot.shell.appLibrary.sortedEntries("")
    var byId = {}
    for (var i = 0; i < all.length; i++) byId[all[i].entry.id] = all[i].entry
    var picked = []
    for (var j = 0; j < ids.length; j++) {
      if (byId[ids[j]]) picked.push(byId[ids[j]])
    }
    return picked
  }

  // favoriteAppIds itself only ever holds real, persisted, user-
  // picked favorites -- it starts and stays empty until the user
  // actually pins something (Ctrl+F / right-click). defaultFavoriteAppIds
  // is a pure display fallback for the empty state, never written
  // to favorites.json: the moment a real pin exists this falls
  // back to showing only that, and if the user later removes
  // every real favorite, this reverts to the defaults again --
  // an empty-state placeholder, not starting data to clean out.
  readonly property var favoriteEntries: resolveEntries(
    favoriteAppIds.length > 0 ? favoriteAppIds : defaultFavoriteAppIds)

  Timer {
    id: favoritesFullHintTimer
    interval: 1600
    repeat: false
    onTriggered: launcherContent.favoritesFullHint = false
  }

  Timer {
    id: favoritesSaveTimer
    interval: 200
    repeat: false
    onTriggered: favoritesFile.setText(JSON.stringify({ ids: launcherContent.favoriteAppIds }, null, 2) + "\n")
  }

  Process {
    id: ensureFavoritesDirProc
    command: ["mkdir", "-p", Quickshell.env("HOME") + "/.local/state/ruixen"]
  }

  FileView {
    id: favoritesFile
    path: launcherContent.favoritesPath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: launcherContent.loadFavorites(text())
    onLoadFailed: launcherContent.loadFavorites("")
  }

  Component.onCompleted: ensureFavoritesDirProc.running = true

  // Search-results and favorite-app tiles both show real app icons
  // and names; the Omarchy-actions tiles show a static glyph +
  // label instead. Same delegate either way (see tile Item
  // below), branched on this.
  readonly property bool tilesAreApps: showingSearch || pinnedMode === "favorites"

  readonly property var activeTiles: showingSearch
    ? searchResults
    : (pinnedMode === "favorites" ? favoriteEntries : pinnedActions)

  function activateTile(data) {
    if (!data) return
    if (tilesAreApps) {
      overlayRoot.shell.appLibrary.launch(data.id, overlayRoot.shell.appLibrary.entryName(data))
    } else {
      launcherActionProc.command = ["omarchy", "menu", "summon", data.id]
      launcherActionProc.running = true
    }
    panel.launcherOpen = false
  }

  // Shared by the toggle button and the Tab shortcut below.
  // Clearing search here makes the toggle take priority over an
  // active query -- without it, toggling while search results
  // were showing flipped pinnedMode but activeTiles stayed on
  // searchResults (showingSearch was still true), so nothing
  // visibly happened.
  function togglePinnedMode() {
    pinnedMode = pinnedMode === "favorites" ? "actions" : "favorites"
    launcherSearchInput.text = ""
    searchText = ""
    Qt.callLater(function() { launcherSearchInput.forceActiveFocus() })
  }

  Process {
    id: launcherActionProc
    stdout: StdioCollector { waitForEnd: true }
  }

  // Search box sits at a FIXED offset from the top rather than
  // inside a height-based-centered Column -- with the old layout,
  // an empty result set hid the Grid entirely, shrinking the
  // Column's total height and re-centering it, which visibly
  // shifted the search box up/down every time the match count hit
  // zero. Anchoring everything to searchBox instead means the
  // Grid and the empty-state text swapping in and out never moves
  // it. topMargin chosen to match the old centered look for the
  // common (results visible) case: 36 (search) + 28 (gap) + 66
  // (tile row) = 130 content height inside a 190 box centers at
  // (190-130)/2 = 30.
  Rectangle {
    id: searchBox
    anchors.top: parent.top
    anchors.topMargin: 30
    anchors.left: parent.horizontalCenter
    anchors.leftMargin: -launcherContent.contentWidth / 2
    width: launcherContent.contentWidth - 44
    height: 36
    radius: 12
    color: Qt.rgba(1, 1, 1, 0.06)

    TextInput {
      id: launcherSearchInput
      anchors.fill: parent
      anchors.leftMargin: 12
      anchors.rightMargin: 28
      verticalAlignment: TextInput.AlignVCenter
      color: overlayRoot.textColor
      font.family: overlayRoot.fontFamily
      font.pixelSize: 12
      clip: true

      onTextChanged: launcherContent.searchText = text

      Keys.onPressed: function(event) {
        var count = launcherContent.activeTiles.length
        var active = launcherContent.activeTiles[launcherContent.selectedIndex]
        if (event.key === Qt.Key_Escape) {
          panel.launcherOpen = false
          event.accepted = true
        } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Up) {
          if (launcherContent.selectedIndex > 0) launcherContent.selectedIndex--
          event.accepted = true
        } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Down) {
          if (launcherContent.selectedIndex < count - 1) launcherContent.selectedIndex++
          event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          launcherContent.activateTile(active)
          event.accepted = true
        } else if (event.key === Qt.Key_F && (event.modifiers & Qt.ControlModifier)) {
          // Bare "f" would collide with typing app names that
          // contain the letter (firefox, spotify...), so this is
          // Ctrl+F rather than the plain key.
          if (launcherContent.showingSearch && active) launcherContent.addFavorite(active.id)
          event.accepted = true
        } else if (event.key === Qt.Key_R && (event.modifiers & Qt.ControlModifier)) {
          if (!launcherContent.showingSearch && launcherContent.pinnedMode === "favorites" && active) {
            launcherContent.removeFavorite(active.id)
          }
          event.accepted = true
        } else if (event.key === Qt.Key_Tab) {
          // Same toggle as the star button, keyboard-only --
          // switches between pinned Omarchy actions and pinned
          // favorite apps.
          launcherContent.togglePinnedMode()
          event.accepted = true
        }
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: launcherContent.favoritesFullHint ? "Favorite Apps Full" : "Search apps..."
        color: overlayRoot.muted
        font.family: overlayRoot.fontFamily
        font.pixelSize: 12
        visible: launcherSearchInput.text.length === 0
      }
    }

    // Clear button -- only meaningful once there's something to
    // clear; sits in the rightMargin space reserved above so it
    // never overlaps typed text.
    Text {
      visible: launcherSearchInput.text.length > 0
      anchors.right: parent.right
      anchors.rightMargin: 10
      anchors.verticalCenter: parent.verticalCenter
      text: "✕"
      font.pixelSize: 11
      color: clearMouse.containsMouse ? overlayRoot.textColor : overlayRoot.muted

      MouseArea {
        id: clearMouse
        anchors.centerIn: parent
        width: 20
        height: 20
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
          launcherSearchInput.text = ""
          launcherSearchInput.forceActiveFocus()
        }
      }
    }
  }

  // Toggle button -- switches the empty-search view between
  // pinned Omarchy actions and pinned favorite apps. Only changes
  // what's shown once the search box is actually empty; toggling
  // mid-query just changes what you'll see after clearing it.
  Rectangle {
    id: favoritesToggle
    anchors.top: searchBox.top
    anchors.left: searchBox.right
    anchors.leftMargin: 8
    width: 36
    height: 36
    radius: 12
    color: launcherContent.pinnedMode === "favorites"
      ? Qt.rgba(1, 1, 1, 0.16)
      : (toggleMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.06))
    Behavior on color { ColorAnimation { duration: 120 } }

    Text {
      anchors.centerIn: parent
      text: ""
      font.family: overlayRoot.fontFamily
      font.pixelSize: 14
      color: launcherContent.pinnedMode === "favorites" ? overlayRoot.textColor : overlayRoot.muted
    }

    MouseArea {
      id: toggleMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: launcherContent.togglePinnedMode()
    }
  }

  Grid {
    visible: launcherContent.showingSearch
      ? launcherContent.searchResults.length > 0
      : (launcherContent.pinnedMode === "favorites" ? launcherContent.favoriteEntries.length > 0 : true)
    anchors.top: searchBox.bottom
    anchors.topMargin: 28
    anchors.horizontalCenter: parent.horizontalCenter
    width: launcherContent.contentWidth
    columns: 6
    spacing: 8

    Repeater {
      model: launcherContent.activeTiles

      Item {
        id: tile
        required property var modelData
        required property int index
        width: 54
        height: 66

        Rectangle {
          id: cardBg
          anchors.top: parent.top
          anchors.horizontalCenter: parent.horizontalCenter
          width: 52
          height: 52
          radius: 14
          color: (cardMouse.containsMouse || tile.index === launcherContent.selectedIndex)
            ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.06)
          Behavior on color { ColorAnimation { duration: 120 } }

          Image {
            id: appIcon
            // Only visible once actually loaded -- gating on
            // tilesAreApps alone left a blank tile for any app
            // missing a real icon (no icon in its .desktop entry,
            // or iconSource() couldn't resolve one), since a
            // failed/empty Image source just renders nothing.
            // The fallback glyph below covers that gap.
            visible: launcherContent.tilesAreApps && status === Image.Ready
            anchors.centerIn: parent
            width: 26
            height: 26
            sourceSize: Qt.size(26, 26)
            asynchronous: true
            source: launcherContent.tilesAreApps && overlayRoot.shell && overlayRoot.shell.appLibrary
              ? overlayRoot.shell.appLibrary.iconSource(tile.modelData.icon) : ""
          }

          // Generic app glyph -- shown once loading has settled
          // and it didn't resolve to a real icon (Error/Null),
          // not during the brief async Loading window, so apps
          // with a working icon never flash this first.
          Text {
            visible: launcherContent.tilesAreApps
              && (appIcon.status === Image.Error || appIcon.status === Image.Null)
            anchors.centerIn: parent
            text: ""
            font.family: overlayRoot.fontFamily
            font.pixelSize: 18
            color: overlayRoot.muted
          }

          Text {
            visible: !launcherContent.tilesAreApps
            anchors.centerIn: parent
            text: launcherContent.tilesAreApps ? "" : tile.modelData.icon
            color: overlayRoot.textColor
            font.pixelSize: 20
          }

          // Pin badge -- shown on any app tile (search results or
          // the favorites view itself) that's a real, persisted
          // favorite. isFavorited() checks favoriteAppIds
          // directly, not the empty-state fallback list, so this
          // naturally stays off the fallback defaults shown when
          // the user has no real favorites yet -- only genuine
          // pins get the dot. Action tiles aren't apps at all, so
          // gated on tilesAreApps too. Plain theme-accent dot, no
          // glyph -- a quieter "already pinned" indicator than an
          // icon-in-a-circle.
          Rectangle {
            visible: launcherContent.tilesAreApps && launcherContent.isFavorited(tile.modelData.id)
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.topMargin: -1
            anchors.rightMargin: -1
            width: 10
            height: 10
            radius: 5
            color: overlayRoot.accent
            border.color: overlayRoot.notchColor
            border.width: 1.5
          }
        }

        Text {
          anchors.top: cardBg.bottom
          anchors.topMargin: 4
          anchors.horizontalCenter: parent.horizontalCenter
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          elide: Text.ElideRight
          text: launcherContent.tilesAreApps && overlayRoot.shell && overlayRoot.shell.appLibrary
            ? overlayRoot.shell.appLibrary.entryName(tile.modelData) : (tile.modelData.label || "")
          color: overlayRoot.muted
          font.family: overlayRoot.fontFamily
          font.pixelSize: 9
        }

        MouseArea {
          id: cardMouse
          anchors.fill: cardBg
          hoverEnabled: true
          acceptedButtons: Qt.LeftButton | Qt.RightButton
          cursorShape: Qt.PointingHandCursor
          onEntered: launcherContent.selectedIndex = tile.index
          onClicked: function(mouse) {
            if (mouse.button === Qt.RightButton) {
              if (launcherContent.showingSearch) launcherContent.addFavorite(tile.modelData.id)
              else if (launcherContent.pinnedMode === "favorites") launcherContent.removeFavorite(tile.modelData.id)
            } else {
              launcherContent.activateTile(tile.modelData)
            }
          }
        }
      }
    }
  }

  Text {
    visible: launcherContent.showingSearch && launcherContent.searchResults.length === 0
    anchors.top: searchBox.bottom
    anchors.topMargin: 28
    anchors.horizontalCenter: parent.horizontalCenter
    width: launcherContent.contentWidth
    horizontalAlignment: Text.AlignHCenter
    text: "No apps match \u201c" + launcherContent.searchText + "\u201d"
    color: overlayRoot.muted
    font.family: overlayRoot.fontFamily
    font.pixelSize: 12
  }

  Text {
    visible: !launcherContent.showingSearch && launcherContent.pinnedMode === "favorites" && launcherContent.favoriteEntries.length === 0
    anchors.top: searchBox.bottom
    anchors.topMargin: 28
    anchors.horizontalCenter: parent.horizontalCenter
    width: launcherContent.contentWidth
    horizontalAlignment: Text.AlignHCenter
    text: "No favorites yet"
    color: overlayRoot.muted
    font.family: overlayRoot.fontFamily
    font.pixelSize: 12
  }
}
