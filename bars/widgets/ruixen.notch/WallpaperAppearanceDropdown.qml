import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "WallpaperEffectModel.js" as EffectModel

Item {
  id: root
  property string title: ""
  property var options: []
  property string selected: ""
  property bool transition: false
  property var controller
  property string currentBackground: ""
  property var artworkEntries: []
  property color accent: "#8aadf4"
  property color textColor: "white"
  property string fontFamily: "monospace"
  property string hoveredKey: ""
  property bool active: false
  property Item boundsItem
  readonly property string previewKey: hoveredKey || selected
  function openMenu() { if (active) menu.open() }
  function closeMenu() { menu.close() }
  function preview(key) { if (options.some(function(item) {return item.key===key})) hoveredKey=key }
  function status() {return {open:menu.opened, preview:previewKey, imagesReady:previewTile.imagesReady, progress:previewTile.progress}}
  signal chosen(string key)
  width: trigger.implicitWidth
  height: 28
  onVisibleChanged: if (!visible) menu.close()
  onActiveChanged: if (!active) menu.close()
  Button {
    id: trigger
    anchors.fill: parent
    text: root.title + " · " + root.options.reduce(function(label, item) {return item.key === root.selected ? item.label : label}, "Off") + " ▾"
    font.family: root.fontFamily; font.pixelSize: 11
    padding: 8
    Accessible.name: root.title + " selection"
    contentItem: Text {text: trigger.text; color:root.accent; font:trigger.font; verticalAlignment:Text.AlignVCenter}
    background: Rectangle {radius:8; color:trigger.hovered || menu.opened ? Qt.rgba(root.accent.r,root.accent.g,root.accent.b,.2) : Qt.rgba(root.textColor.r,root.textColor.g,root.textColor.b,.06)}
    onClicked: menu.opened ? menu.close() : menu.open()
  }
  Popup {
    id: menu
    x: -Math.max(0, width - root.width)
    y: root.height + 6
    width: root.boundsItem ? Math.min(490, root.boundsItem.width - 8) : 490
    height: root.boundsItem ? Math.min(260, Math.max(100, root.boundsItem.height - root.mapToItem(root.boundsItem, 0, root.height).y - 18)) : 260
    padding: 10
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    onClosed: root.hoveredKey = ""
    background: Rectangle {color:"#15171c"; radius:12; border.color:Qt.rgba(root.accent.r,root.accent.g,root.accent.b,.4)}
    contentItem: RowLayout {
      spacing: 12
      ScrollView {
        Layout.preferredWidth: 180; Layout.fillHeight: true
        clip: true
        contentWidth: availableWidth
        ScrollBar.vertical.policy: ScrollBar.AlwaysOn
        Column {
          width: 180; spacing: 3
          Repeater {
            model: root.options
            Button {
              required property var modelData
              width:180; height:30
              text:modelData.label
              font.family:root.fontFamily; font.pixelSize:11
              Accessible.name:text
              contentItem:Text {text:parent.text; font:parent.font; color:root.textColor; verticalAlignment:Text.AlignVCenter}
              background:Rectangle {radius:6; color:parent.hovered || parent.activeFocus || root.selected===modelData.key ? Qt.rgba(root.accent.r,root.accent.g,root.accent.b,.25) : "transparent"}
              HoverHandler {onHoveredChanged:root.hoveredKey=hovered ? modelData.key : ""}
              onActiveFocusChanged: if (activeFocus) root.hoveredKey=modelData.key
              onClicked: {root.chosen(modelData.key);menu.close()}
            }
          }
        }
      }
      ColumnLayout {
        Layout.fillWidth:true; Layout.fillHeight:true
        Text {text:"Preview"; color:root.textColor; font.family:root.fontFamily; font.pixelSize:12}
        WallpaperEffectPreview {
          id: previewTile
          Layout.fillWidth:true; Layout.fillHeight:true
          fromPath:root.currentBackground
          toPath:EffectModel.nextPreviewArtwork(root.currentBackground,root.artworkEntries)
          effect:root.transition && root.previewKey!=="stock" ? root.previewKey : "reveal"
          playing:menu.opened && root.transition && root.previewKey!=="stock" && root.controller.settings.disableMotion!==true
          durationMs:root.previewKey===root.selected && root.controller.settings.transitionDurationMs>0 ? root.controller.settings.transitionDurationMs : (root.controller.glitchKeys.indexOf(root.previewKey)>=0 ? 550 : 900)
          softness:root.controller.settings.transitionSoftness || .02
          transitionOptions:root.controller.settings.transitionOptions || ({})
          backgroundEffect:root.transition ? (root.controller.settings.backgroundEffect || "none") : root.previewKey
          ambientActive:menu.opened
          backgroundIntensity:root.controller.settings.backgroundIntensity===undefined ? .25 : root.controller.settings.backgroundIntensity
          backgroundSpeed:root.controller.settings.backgroundSpeed || 1
          disableMotion:root.controller.settings.disableMotion===true
          accent:root.accent
        }
        Text {text:"Hover to preview · click to apply"; color:root.textColor; opacity:.65; font.pixelSize:10}
      }
    }
  }
}
