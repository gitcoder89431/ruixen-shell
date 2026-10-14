import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import ".."

// Issue #102 phase 6: extracted from SettingsContent.qml's own Profile
// section (429 lines -- avatar picker/preview, Glass Effect, Glass
// Tint, Window Curvature, Window Spacing, Animation Style). Same
// pattern as every prior page -- see PluginsPage.qml's own header for
// the full reasoning (live property bindings via settingsRoot, never a
// one-time copy; a Column wrapper with its own matching spacing/
// visible so an inactive section collapses to zero space in the outer
// Column exactly like individually-hidden siblings did). import ".."
// exposes SettingsSegmentedItem, still a sibling one directory up.
//
// Unlike every other page so far, this one carries its own real
// backend object (avatarFileDialog, a Process that spawns a standalone
// helper QML file for the native file picker -- kept with this page
// per this issue's own "move category-specific Process/FileView/
// timers with the category when practical" guidance, since it is
// avatar-picking-specific and nothing else references it). Its own
// target path is an absolute, deployed path
// (~/.config/omarchy/plugins/ruixen.launcher/extensions/settings/
// avatar-file-picker.qml), not a path relative to this file's own
// source location, so moving this file does not affect it.
//
// profilePictureItem/glassProfileItem/glassTintItem/windowCurvatureItem/
// windowSpacingItem/animationStyleItem are exposed because
// SettingsContent.qml's own shared, cross-section focusedItemVisual()
// keyboard-navigation coordinator needs to reach them regardless of
// which page owns them. avatarFileDialog is ALSO exposed, for the same
// reason, by SettingsContent.qml's own profileItems keyboard-
// navigation data model (a different, data-only list that stays
// centralized, same as every other page's own equivalent --
// pluginItems, audioItems, ...) -- that model's own "custom" avatar
// entry needs to actually open the real picker, not just report focus.
Column {
  id: root
  required property Item settingsRoot

  width: parent.width
  spacing: 16
  visible: settingsRoot.profileOpen

  readonly property alias profilePictureItem: profilePictureItem
  readonly property alias glassProfileItem: glassProfileItem
  readonly property alias glassTintItem: glassTintItem
  readonly property alias windowCurvatureItem: windowCurvatureItem
  readonly property alias windowSpacingItem: windowSpacingItem
  readonly property alias animationStyleItem: animationStyleItem
  readonly property alias avatarFileDialog: avatarFileDialog

  // Profile's own real content -- centered avatar + username@machine,
  // then the DiceBear collection picker -- ported from ruixen.settings/
  // GeneralContent.qml's own avatar card (see this file's header
  // comment). No card background/border here (unlike the real app's
  // own black card) -- this pane is already the ghost/ContentPage
  // treatment every extension's right side uses, a second nested card
  // would be a surface-on-a-surface with nothing to visually separate.
  // Frames this one setting as a distinct menu item/option -- direct
  // follow-up: "this would be considered an option or menu item, how
  // do we group it as that... put that darker bg tonal we used for
  // the file picker text or zebra stripe." Same dark tonal
  // FileDetailsPanel.qml's own zebra-striped metadata rows already use
  // (Qt.rgba(0, 0, 0, 0.18)) -- this is that same "item" treatment
  // scaled up to a whole option's card instead of one thin row, not a
  // new color invented for this.
  Rectangle {
    id: profilePictureItem
    width: parent.width
    height: profilePictureContent.implicitHeight + 24
    radius: 10
    color: Qt.rgba(0, 0, 0, 0.18)
    // Card-level focus ring -- direct request: "tab between cards...
    // then left or right direction and enter for that option". Shown
    // whenever this is the Tab-focused card, regardless of which of
    // its own options the cursor is on.
    border.width: settingsRoot.rightFocused && settingsRoot.focusedItemIndex === 0 ? 1 : 0
    border.color: settingsRoot.accent
    visible: settingsRoot.profileOpen

    Column {
      id: profilePictureContent
      anchors.fill: parent
      anchors.margins: 12
      spacing: 12

      // Each individual setting gets its OWN plain, descriptive label
      // -- no separate subtitle underneath it -- direct correction:
      // "for this first setting option we can put Select Profile
      // Picture. i dont think these options need subtitle if we make
      // the option... kind a descriptive? itll be good for searching
      // for them later too." Every future real setting in any category
      // follows this same one-line, self-descriptive convention rather
      // than a title+subtitle pair. Shortened to "Profile Picture" per
      // direct follow-up.
      Text {
        text: "Profile Picture"
        font.family: settingsRoot.fontFamily
        font.pixelSize: 12
        font.weight: Font.DemiBold
        color: settingsRoot.textColor
      }

      Item {
        id: avatarPreviewWrap
        anchors.horizontalCenter: parent.horizontalCenter
        width: 64
        height: 64

        // AnimatedImage ONLY for a genuine multi-frame animation
        // (frameCount > 1) -- plain Image for everything else, including
        // every static DiceBear/GitHub/custom avatar. Direct live
        // finding (confirmed with temporary console.log instrumentation,
        // then isolated by forcing each element as the sole source in
        // turn): AnimatedImage decodes a NEW static image correctly
        // every time (status genuinely reaches Ready with the right
        // content) but its own texture update does not reliably
        // propagate to MultiEffect past the very first successful decode
        // of its lifetime -- a second, different static image assigned
        // to the SAME AnimatedImage element silently kept showing the
        // first one on screen forever, while the exact same reload
        // sequence through plain Image alone refreshed correctly every
        // single time. Real animated GIFs are unaffected either way
        // (their own frame timer drives repaints through a completely
        // different path, confirmed live: frameCount > 1 still animates
        // correctly here) -- this only changes which element renders
        // STATIC content. .ico still needs the fallback too, for the
        // older, separate reason below (AnimatedImage's decoder errors
        // out on it outright).
        readonly property var activeAvatarImage: (avatarPreviewImage.status === Image.Ready && avatarPreviewImage.frameCount > 1)
          ? avatarPreviewImage : avatarPreviewImageFallback
        property int avatarFrameIndex: 0
        readonly property string avatarSource: settingsRoot.avatarAnimated
          ? "file://" + settingsRoot.avatarFrameDir + "/frame-" + ("00" + avatarPreviewWrap.avatarFrameIndex).slice(-3) + ".png#" + settingsRoot.avatarCacheBust
          : "file://" + Quickshell.env("HOME") + "/.face.icon#" + settingsRoot.avatarCacheBust

        Timer {
          interval: settingsRoot.avatarFrameDelayMs
          running: settingsRoot.avatarAnimated && settingsRoot.avatarFrameCount > 1
          repeat: true
          onTriggered: avatarPreviewWrap.avatarFrameIndex = (avatarPreviewWrap.avatarFrameIndex + 1) % settingsRoot.avatarFrameCount
        }

        // Circular gradient fallback -- explicitly hidden once a real
        // image is loaded (not just painted over by an assumed-opaque
        // one), so nothing is left behind for any load-state edge case
        // to reveal.
        Rectangle {
          anchors.fill: parent
          radius: width / 2
          visible: !settingsRoot.avatarAnimated && avatarPreviewWrap.activeAvatarImage.status !== Image.Ready
          gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.lighter(settingsRoot.accent, 1.6) }
            GradientStop { position: 1.0; color: Qt.darker(settingsRoot.accent, 1.4) }
          }
        }

        // "#" cache-bust fragment, not "?" -- Qt's local file:// loader
        // can try to resolve a "?"-suffixed string as a literal filename
        // instead of stripping it, unlike an HTTP server. A URL fragment
        // is always stripped before path resolution, busting the Image's
        // own source-string cache (needed since a new avatar overwrites
        // the exact same path) without that risk.
        // AnimatedImage exists alongside plain Image so a picked GIF
        // still actually animates (activeAvatarImage's own comment above
        // covers when each one is actually selected) -- QMovie (the
        // decoder behind AnimatedImage) also supports a narrower format
        // set than QImageReader (behind plain Image): an .ico-format
        // ~/.face.icon decodes fine via Image but errors out via
        // AnimatedImage every time, confirmed live.
        AnimatedImage {
          id: avatarPreviewImage
          anchors.fill: parent
          source: avatarPreviewWrap.avatarSource
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          cache: false
          visible: settingsRoot.avatarAnimated
        }

        Image {
          id: avatarPreviewImageFallback
          anchors.fill: parent
          source: avatarPreviewWrap.avatarSource
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          cache: false
          visible: false
        }

        Rectangle {
          id: avatarPreviewMask
          anchors.fill: parent
          radius: width * 0.2
          color: "#ffffff"
          visible: false
          layer.enabled: true
        }

        MultiEffect {
          anchors.fill: parent
          source: avatarPreviewWrap.activeAvatarImage
          visible: !settingsRoot.avatarAnimated
          maskEnabled: true
          maskSource: avatarPreviewMask
          maskThresholdMin: 0.5
          maskThresholdMax: 1.0
        }
      }

      Column {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 1

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          readonly property int detailStart: settingsRoot.hardwareName.indexOf(" (")
          readonly property string shortHardwareName: detailStart > 0 ? settingsRoot.hardwareName.slice(0, detailStart) : settingsRoot.hardwareName

          text: Quickshell.env("USER") + "@" + shortHardwareName
          font.family: settingsRoot.fontFamily
          font.pixelSize: 11
          color: settingsRoot.muted
        }

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          readonly property int detailStart: settingsRoot.hardwareName.indexOf(" (")
          text: detailStart > 0 ? settingsRoot.hardwareName.slice(detailStart) : ""
          visible: text !== ""
          font.family: settingsRoot.fontFamily
          font.pixelSize: 10
          color: Qt.rgba(settingsRoot.muted.r, settingsRoot.muted.g, settingsRoot.muted.b, 0.78)
        }
      }

      // Selecting one both picks it (highlighted border) AND immediately
      // applies it -- no separate "pick then press an action button"
      // step, same as the real picker. Flow, not a Row -- 9 labels don't
      // reliably fit one line at this panel's width.
      Flow {
        width: parent.width
        spacing: 6

        Repeater {
          model: settingsRoot.avatarCollections

          Rectangle {
            id: collectionBtn
            required property var modelData
            required property int index
            readonly property bool isCurrent: settingsRoot.avatarCollection === collectionBtn.modelData.id
            // Keyboard cursor position, distinct from isCurrent (the
            // actually-applied value) -- direct request: "tab between
            // cards options and then left or right direction and enter
            // for that option". Direct correction: an all-white border
            // here read as bad design, clobbering the accent ring's own
            // meaning -- shown as an underline on the label instead
            // (below), leaving border.color alone entirely.
            readonly property bool isFocused: settingsRoot.rightFocused
              && settingsRoot.focusedItemIndex === 0 && settingsRoot.focusedOptionIndex === collectionBtn.index
            // !== false, not truthiness -- every entry except github
            // omits this field entirely and must still count as
            // available (undefined !== false is true).
            readonly property bool isAvailable: collectionBtn.modelData.available !== false

            width: collectionLabel.implicitWidth + 16
            height: 24
            radius: 6
            color: collectionBtn.isCurrent ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
            border.width: 1
            border.color: collectionBtn.isCurrent ? settingsRoot.accent : Qt.rgba(1, 1, 1, 0.12)
            opacity: (settingsRoot.avatarBusy || !collectionBtn.isAvailable) ? 0.5 : 1

            Text {
              id: collectionLabel
              anchors.centerIn: parent
              text: collectionBtn.modelData.label
              font.family: settingsRoot.fontFamily
              font.pixelSize: 10
              font.weight: collectionBtn.isCurrent ? Font.DemiBold : Font.Normal
              color: collectionBtn.isCurrent ? settingsRoot.textColor : settingsRoot.muted
            }

            // Accent-colored underline, not font.underline -- direct
            // correction: "the underline kinda hard to see, use the
            // accent color for the underline?" font.underline always
            // draws in the text's OWN color (muted when not current),
            // which is exactly why it read as faint; a separate bar
            // can be any color regardless of the label's own.
            Rectangle {
              visible: collectionBtn.isFocused
              anchors.top: collectionLabel.bottom
              anchors.horizontalCenter: collectionLabel.horizontalCenter
              width: collectionLabel.paintedWidth
              height: 1
              color: settingsRoot.accent
            }

            MouseArea {
              anchors.fill: parent
              enabled: !settingsRoot.avatarBusy && collectionBtn.isAvailable
              cursorShape: collectionBtn.isAvailable ? Qt.PointingHandCursor : Qt.ArrowCursor
              // "custom" has no self-contained action the way every
              // other entry does (gradient/DiceBear/github all apply
              // immediately on click) -- it needs a file first, so this
              // opens the picker instead and lets its own stderr
              // collector call selectAvatar() once something is actually
              // chosen.
              onClicked: {
                if (collectionBtn.modelData.id === "custom") avatarFileDialog.openPicker()
                else settingsRoot.selectAvatar(collectionBtn.modelData.id)
              }
            }
          }
        }
      }

      // Spawned as a genuinely SEPARATE process (`qml6` running the
      // sibling avatar-file-picker.qml), not run in-process via
      // QtQuick.Dialogs' FileDialog directly -- direct fix after a real,
      // reproducible crash (confirmed via coredumpctl + debuginfod
      // symbolization, twice, byte-for-byte identical both times) inside
      // GTK3's native file chooser + GVfs's directory-monitor D-Bus
      // call, triggered by this system's QT_QPA_PLATFORMTHEME=gtk3 and
      // taking the WHOLE shell down with it -- several seconds of the
      // entire desktop shell restarting, every time it fired. Running
      // this same FileDialog as a standalone process instead means a
      // crash there can never touch quickshell again -- worst case, this
      // one small helper dies and the picker just doesn't open. See the
      // sibling file's own comment for the full mechanism, including why
      // GTK_USE_PORTAL=1/QT_FORCE_STDERR_LOGGING=1 are set here rather
      // than there (this is the caller, so this is where the child's
      // environment gets to be decided).
      Process {
        id: avatarFileDialog
        command: ["env", "GTK_USE_PORTAL=1", "QT_FORCE_STDERR_LOGGING=1",
          "qml6", Quickshell.env("HOME") + "/.config/omarchy/plugins/ruixen.launcher/extensions/settings/avatar-file-picker.qml"]
        stderr: StdioCollector {
          id: avatarFileDialogStderr
          waitForEnd: true
          onStreamFinished: {
            var marker = "RUIXEN_AVATAR_PICK:"
            var lines = String(text || "").split("\n")
            for (var i = 0; i < lines.length; i++) {
              var idx = lines[i].indexOf(marker)
              if (idx < 0) continue
              // selectedFile is a file:// URL, not a plain path --
              // decode first so a filename with a space/unicode
              // character in it (URL-encoded in the url form) reaches
              // ImageMagick correctly rather than as a literal "%20"
              // etc.
              var path = lines[i].slice(idx + marker.length).trim()
              if (path.indexOf("file://") === 0) path = decodeURIComponent(path.slice(7))
              if (path !== "") settingsRoot.selectAvatar("custom", path)
              return
            }
          }
        }
        function openPicker() {
          if (!running) running = true
        }
      }
    }
  }

  // Glass Effect (Frosted/Transparent) -- moved above Window
  // Curvature -- direct request: "maybe we can move this setting high
  // than window curvature even?" (after noticing it affects both
  // ruixen.launcher's own card AND real Hyprland window blur/opacity,
  // a bigger-reaching setting than most of what's below it). See
  // glassProfile's own property comment above for the full "why,"
  // including the Vibrant/Solid pair that was tried and reverted. The
  // real opacity/blur values live in hyprland/looknfeel.ruixen.lua and
  // looknfeel.square.lua (both read the same glass-profile file).
  SettingsSegmentedItem {
    id: glassProfileItem
    label: "Glass Effect"
    options: [
      { id: "transparent", label: "Transparent" },
      { id: "frosted", label: "Frosted" }
    ]
    current: settingsRoot.glassProfile
    cardFocused: settingsRoot.rightFocused && settingsRoot.focusedItemIndex === 1
    focusedOptionIndex: cardFocused ? settingsRoot.focusedOptionIndex : -1
    visible: settingsRoot.profileOpen
    textColor: settingsRoot.textColor
    muted: settingsRoot.muted
    accent: settingsRoot.accent
    fontFamily: settingsRoot.fontFamily
    onActivated: (id) => settingsRoot.setGlassProfile(id)
  }

  // Glass Tint (Dark/Theme) -- direct request, right after Glass
  // Effect since they're both "glass"-related, even though they're
  // orthogonal settings (see glassTintMode's own comment above for the
  // full "why," including the git-history confirmation that Black is
  // this repo's own original value, not a new invention).
  SettingsSegmentedItem {
    id: glassTintItem
    label: "Glass Tint"
    options: [
      { id: "black", label: "Dark" },
      { id: "themed", label: "Theme" }
    ]
    current: settingsRoot.glassTintMode
    cardFocused: settingsRoot.rightFocused && settingsRoot.focusedItemIndex === 2
    focusedOptionIndex: cardFocused ? settingsRoot.focusedOptionIndex : -1
    visible: settingsRoot.profileOpen
    textColor: settingsRoot.textColor
    muted: settingsRoot.muted
    accent: settingsRoot.accent
    fontFamily: settingsRoot.fontFamily
    onActivated: (id) => settingsRoot.setGlassTintMode(id)
  }

  // Fourth/fifth/sixth Profile items -- SettingsSegmentedItem.qml,
  // the shared "segmented option" card three near-identical hand-
  // rolled copies got extracted into: "how do we keep this pattern
  // going? easy to reuse". Ported values (options/current/activate)
  // still come from ruixen.settings, unchanged -- only the visual
  // shell moved into the shared component.
  SettingsSegmentedItem {
    id: windowCurvatureItem
    label: "Window Curvature"
    options: [
      { id: "rounded", label: "Curve" },
      { id: "half", label: "Half" },
      { id: "sharp", label: "Sharp" }
    ]
    current: settingsRoot.cornerCurvature
    cardFocused: settingsRoot.rightFocused && settingsRoot.focusedItemIndex === 3
    focusedOptionIndex: cardFocused ? settingsRoot.focusedOptionIndex : -1
    visible: settingsRoot.profileOpen
    textColor: settingsRoot.textColor
    muted: settingsRoot.muted
    accent: settingsRoot.accent
    fontFamily: settingsRoot.fontFamily
    onActivated: (id) => settingsRoot.setCornerCurvature(id)
  }

  SettingsSegmentedItem {
    id: windowSpacingItem
    label: "Window Spacing"
    options: [
      { id: "comfy", label: "Comfy" },
      { id: "tight", label: "Tight" }
    ]
    current: settingsRoot.spacingProfile
    cardFocused: settingsRoot.rightFocused && settingsRoot.focusedItemIndex === 4
    focusedOptionIndex: cardFocused ? settingsRoot.focusedOptionIndex : -1
    visible: settingsRoot.profileOpen
    textColor: settingsRoot.textColor
    muted: settingsRoot.muted
    accent: settingsRoot.accent
    fontFamily: settingsRoot.fontFamily
    onActivated: (id) => settingsRoot.setSpacingProfile(id)
  }

  SettingsSegmentedItem {
    id: animationStyleItem
    label: "Animation Style"
    // Calm first (the real app's own default), then Bubbly, then
    // Snappy -- matches ruixen.settings/GeneralContent.qml's own model
    // order exactly, not alphabetical.
    options: [
      { id: "calm", label: "Calm" },
      { id: "bubbly", label: "Bubbly" },
      { id: "snappy", label: "Snappy" }
    ]
    current: settingsRoot.animationProfile
    cardFocused: settingsRoot.rightFocused && settingsRoot.focusedItemIndex === 5
    focusedOptionIndex: cardFocused ? settingsRoot.focusedOptionIndex : -1
    visible: settingsRoot.profileOpen
    textColor: settingsRoot.textColor
    muted: settingsRoot.muted
    accent: settingsRoot.accent
    fontFamily: settingsRoot.fontFamily
    onActivated: (id) => settingsRoot.setAnimationProfile(id)
  }
}
