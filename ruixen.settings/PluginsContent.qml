import QtQuick
import QtQuick.Layouts

// Plugins section content -- extracted out of Settings.qml (which stays the
// manifest's single overlay entry point) as a trial run of splitting this
// app's pages into their own files, same pattern ruixen.notch already
// proved out (Overlay.qml + DashboardContent.qml/MetricsContent.qml/
// WallpapersContent.qml, same-directory QML types, no manifest change
// needed). Checklist of this repo's own ruixen.* plugins (enable/disable)
// and the repo-wide Update button. All backend state/Processes stay on
// Settings.qml's own root -- this component is presentation only, reading
// and writing through the single settingsRoot reference below, same
// shape as DashboardContent's own `shell: root.shell` passthrough. The
// full-uninstall danger zone that used to live here moved to its own
// About page -- direct follow-up ("should we put the uninstall on the
// about then? seems like we have more room there, the plugs in list is
// kinda big") -- see AboutContent.qml.

ColumnLayout {
  id: root

  property var settingsRoot: null

  spacing: 12

  Text {
    visible: settingsRoot.ruixenRepoPath === ""
    Layout.fillWidth: true
    text: "Update needs a repo checkout path -- run install.sh or update.sh once from your ruixen-shell clone to enable it here."
    wrapMode: Text.WordWrap
    font.family: settingsRoot.fontFamily
    font.pixelSize: 10
    color: settingsRoot.muted
  }

  Text {
    visible: settingsRoot.pluginUpdateStatus === "error" && settingsRoot.pluginUpdateError !== ""
    Layout.fillWidth: true
    text: settingsRoot.pluginUpdateError
    wrapMode: Text.WordWrap
    font.family: settingsRoot.fontFamily
    font.pixelSize: 10
    color: "#e05252"
  }

  // No inner Flickable of its own anymore -- direct follow-up
  // ("should we just scroll with the header too, so put the fade on
  // top and everything in the page scroll, nothing is sticky"): the
  // whole detail panel scrolls as one unit now (see Settings.qml's own
  // Flickable wrapping headerPill + the active page together), so a
  // second, nested Flickable in here would just fight it over scroll
  // gestures. This card now renders at its own natural height, same as
  // every other card on every other page.
  ColumnLayout {
    id: pluginsCardWrap
    Layout.fillWidth: true
    spacing: 12

        Rectangle {
          Layout.fillWidth: true
          // settingsRoot.pluginRows.length read even though
        // it's not otherwise needed in this expression --
        // real bug hit live ("im only seeing 2 plugin app
        // launcher and bar now, the rest arent showing up
        // anymore"): unlike Wi-Fi/Bluetooth's own lists,
        // which come from already-live Quickshell modules
        // with data available on first paint, this list
        // starts empty and only populates ~100-500ms
        // later once the omarchy plugin list --json
        // subprocess actually finishes. This height
        // binding's real dependency (pluginsCardContent.
        // implicitHeight, several Repeater-populated
        // layout levels down) didn't reliably re-fire
        // when the Repeater's model went from empty to
        // populated after the fact -- same underlying
        // class of bug as the accordion collapse fix
        // above, just hitting on initial load instead of
        // a later toggle. Reading pluginRows.length here
        // directly forces this binding to re-evaluate the
        // moment the real data arrives, sidestepping
        // whatever the implicitHeight chain's own signal
        // timing issue is.
        Layout.preferredHeight: (settingsRoot.pluginRows.length >= 0 ? pluginsCardContent.implicitHeight : 0) + 24
        radius: 10
        color: "#000000"

        ColumnLayout {
          id: pluginsCardContent
          anchors.fill: parent
          anchors.margins: 12
          spacing: 4

          Text {
            visible: settingsRoot.pluginRows.length === 0
            text: "No plugins found"
            font.family: settingsRoot.fontFamily
            font.pixelSize: 11
            color: settingsRoot.muted
          }

          Repeater {
            model: settingsRoot.pluginRows

            Rectangle {
              // Enable/disable only, no per-row remove --
              // direct follow-up: "why not allow disable
              // only and uninstall gets rid of everything
              // as the only option". Disable already
              // covers "don't want this running" (instant,
              // reversible); actual file removal stays
              // exclusively behind the danger-zone full
              // uninstall below, which already has its own
              // heavier typed-confirmation gate. A second,
              // lighter-weight way to delete files per-row
              // was redundant with that, not a real safety
              // improvement.
              id: pluginRow
              required property var modelData
              readonly property bool isProtected: settingsRoot.pluginIsProtected(pluginRow.modelData)
              readonly property bool busy: settingsRoot.pluginBusyId === pluginRow.modelData.id

              Layout.fillWidth: true
              Layout.preferredHeight: 32
              radius: 8
              color: "transparent"

              RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: 8

                Text {
                  text: pluginRow.modelData.name
                  font.family: settingsRoot.fontFamily
                  font.pixelSize: 12
                  color: pluginRow.isProtected ? settingsRoot.muted : settingsRoot.textColor
                  elide: Text.ElideRight
                  Layout.fillWidth: true
                }

                // Lock -- protected plugin (canDisable:
                // false from the CLI itself, e.g.
                // ruixen.bar, or ruixen.settings by this
                // UI's own added guard -- see
                // pluginIsProtected's comment).
                Text {
                  visible: pluginRow.isProtected
                  text: ""
                  font.family: settingsRoot.fontFamily
                  font.pixelSize: 11
                  color: settingsRoot.muted
                }

                // Enable/disable -- same pill-switch
                // shape as every radio toggle elsewhere
                // in this app, just smaller to fit a
                // dense checklist row.
                Rectangle {
                  visible: !pluginRow.isProtected
                  Layout.preferredWidth: 32
                  Layout.preferredHeight: 16
                  radius: 8
                  color: pluginRow.modelData.enabled ? settingsRoot.accent : Qt.rgba(1, 1, 1, 0.15)
                  opacity: pluginRow.busy ? 0.5 : 1
                  Behavior on color { ColorAnimation { duration: 120 } }

                  Rectangle {
                    width: 12
                    height: 12
                    radius: 6
                    color: "#ffffff"
                    anchors.verticalCenter: parent.verticalCenter
                    x: pluginRow.modelData.enabled ? parent.width - width - 2 : 2
                    Behavior on x { NumberAnimation { duration: 120 } }
                  }

                  MouseArea {
                    anchors.fill: parent
                    enabled: !pluginRow.busy
                    cursorShape: Qt.PointingHandCursor
                    onClicked: settingsRoot.togglePluginEnabled(pluginRow.modelData)
                  }
                }
              }
            }
          }
        }
      }
  }

    // No scroll indicator, no per-card fade either -- direct follow-up
    // chain: first "that scroll bar is it an os thing... i dont want
    // it shown" (removed the custom scroll-position Rectangle), then a
    // top/bottom fade was tried here directly on this card, which hit
    // a real geometric problem once actually scrolled: "on scroll i
    // get a square edge then back to round" -- this card's rounded
    // corner only really exists at scroll position 0 (or the bottom
    // equivalent); a fade Rectangle with a matching fixed radius looks
    // right at rest but mismatches the instant the card's real corner
    // scrolls out of view, since what's actually underneath at that
    // point is a plain straight edge, not a corner. Direct correction:
    // "all our other stuff its not in scroll the cards themselves
    // actually scroll, i think we should stick to one design" -- this
    // page now matches Wi-Fi/Bluetooth's own Flickable/card shape
    // exactly (see WifiContent.qml), and the fade moved to the shared
    // panel chrome in Settings.qml instead, where it's anchored to
    // fixed, never-scrolling panel edges instead of a scrolling card's
    // own corner -- see its own comment there for why that sidesteps
    // this problem entirely rather than just patching it again here.

}
