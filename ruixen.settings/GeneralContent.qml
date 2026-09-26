import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import QtQuick.Dialogs
import Quickshell

// General -- bar layout mode + avatar + about, first page in the
// sidebar. Per direct request ("i think we can just do General for
// now"). See the property/function block in Settings.qml (root.
// barMode, root.avatarCacheBust, root.selectAvatar() etc.) for the
// real mechanism and reasoning.
ColumnLayout {
  id: root

  property var settingsRoot: null

  spacing: 16

  // Avatar -- shown on ruixen.notch's own collapsed row. Live preview
  // uses the exact same dual-layer technique as ruixen.notch's own
  // UserAvatar component (gradient Rectangle underneath, theme-aware
  // via Qt.lighter/darker off settingsRoot.accent -- same Color.accent
  // source, just computed locally since plugins can't import across
  // each other), real ~/.face.icon image + circular mask on top, which
  // simply renders nothing when the file doesn't exist, letting the
  // gradient show through on its own -- no separate "gradient mode"
  // flag needed anywhere.
  Rectangle {
    Layout.fillWidth: true
    Layout.preferredHeight: avatarCardContent.implicitHeight + 24
    radius: 10
    color: "#000000"

    ColumnLayout {
      id: avatarCardContent
      anchors.fill: parent
      anchors.margins: 12
      spacing: 12

      // Page title lives here now, not a separate floating headerPill
      // above this card -- direct follow-up ("the header like Settings
      // instead of floating it can go on the Avatar as the header for
      // that card... audio and wifi has a toggle button so it can stay
      // floating"). Settings.qml's own headerPill collapses to nothing
      // for this page specifically (selectedSection === 0) since
      // Profile has no inline control (mute/radio toggle) that needs a
      // consistently-positioned floating row -- see its own comment.
      // Same size/weight/color the floating pill's title used (15px
      // DemiBold, root.textColor equivalent), so it still reads as the
      // page header, just relocated. Distinct from the small muted
      // section labels below it (Bar Layout, and the same "Output"/
      // "Input" pattern elsewhere in this file) -- this is the page's
      // own title, not a card-local one. Text renamed from "System" to
      // "Profile" per direct request ("i feel like Profile sounds
      // better here"), same rename as the sidebar's own label.
      Text {
        text: "Profile"
        font.family: settingsRoot.fontFamily
        font.pixelSize: 15
        font.weight: Font.DemiBold
        color: settingsRoot.textColor
      }

      // Centered preview + username@machine underneath, not a plain
      // "Avatar" header -- direct follow-up ("this card looks better
      // if the avatar is centered, and then instead of Avatar text in
      // the card header, we can put username and machine under the
      // avatar center then?"). No Shuffle/Reset buttons beside it
      // either (see the collection picker Flow below) -- every action
      // lives there instead.
      Item {
        id: avatarPreviewWrap
        Layout.preferredWidth: 64
        Layout.preferredHeight: 64
        Layout.alignment: Qt.AlignHCenter

        // Whichever of the two image elements below actually decoded
        // the source -- AnimatedImage first (for real GIF animation),
        // falling back to plain Image only once AnimatedImage's own
        // decoder (QMovie) has genuinely failed. Confirmed live this
        // fallback is load-bearing, not defensive-for-no-reason code:
        // QMovie supports a narrower format set than QImageReader (the
        // decoder behind plain Image) -- an .ico-format ~/.face.icon
        // (confirmed live on this exact machine) decodes fine via Image
        // but errors out via AnimatedImage every time, fragment or not.
        // Without this, an avatar that worked before this feature
        // shipped could silently stop rendering at all.
        readonly property var activeAvatarImage: avatarPreviewImage.status === Image.Error
          ? avatarPreviewImageFallback : avatarPreviewImage
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

        // Explicitly hidden once a real image is loaded, not just
        // painted over by an assumed-opaque one -- direct follow-up
        // ("why do we need to keep showing the fallback gradient...
        // why do we need both to appear and overlap"): the two
        // layers overlapping regardless of load state is exactly
        // what let any imperfection show up as the gradient visibly
        // bleeding through. With this, nothing is left behind the
        // avatar for any edge case to ever reveal.
        Rectangle {
          anchors.fill: parent
          // Circular, unlike the real DiceBear avatars this sits
          // behind (deliberately plain square now, see settingsRoot.
          // selectAvatar's own comment) -- direct follow-up ("keep it
          // for the gradient though, the gradient default we load in
          // is square now... why not just make the gradient a
          // circle"). Never shown at the same time as a real avatar
          // (visible below is gated on the image NOT being ready), so
          // the two shapes never need to match.
          radius: width / 2
          visible: !settingsRoot.avatarAnimated && avatarPreviewWrap.activeAvatarImage.status !== Image.Ready
          gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.lighter(settingsRoot.accent, 1.6) }
            GradientStop { position: 1.0; color: Qt.darker(settingsRoot.accent, 1.4) }
          }
        }

        // "#" cache-bust fragment, not a "?" query string -- Qt's
        // local file:// loader can try to resolve a "?"-suffixed
        // string as a literal filename instead of stripping it the
        // way an HTTP server would. A URL fragment is universally
        // stripped before path resolution, so it busts the Image's
        // source-string cache (needed since selecting a new avatar
        // overwrites the exact same path) without that risk.
        //
        // No circular treatment -- direct follow-up chain: first "why
        // do we still hard cap a circle around it, doesnt dicebear
        // take care of it" (tried DiceBear's own radius=50 param,
        // which scales each style's content to fit a circle instead of
        // the old MultiEffect mask's blind crop), then, after actually
        // seeing it, "the circle is still there... the circle mask
        // comes back" -- radius=50 still produces a circle, just a
        // better-behaved one, which wasn't the actual ask. Dropped
        // radius=50 too (see settingsRoot.selectAvatar).
        //
        // Rounded-square clip, not a hard rectangle though -- direct
        // follow-up ("on the site it shows it has like a curved around
        // the edge, its not suppose to be rectangular with hard
        // edge"). That curve is DiceBear's own website preview-card
        // CSS, not part of the fetched image -- confirmed by reading
        // pixelbot's raw SVG directly, rx="0" regardless of style. So
        // a real mask is what gets that look here, same MultiEffect
        // technique this used before, just a small proportional radius
        // instead of width/2 -- a rounded square, not a circle (the
        // circle stays for the gradient placeholder only, per its own
        // comment above).
        // AnimatedImage, not Image -- direct request to make a picked
        // GIF actually animate. AnimatedImage (QQuickAnimatedImage) is a
        // real subclass of QQuickImage per Qt's own qmltypes, and a
        // standalone `qs -p` test confirmed it renders DiceBear's SVG
        // collections and a static PNG/JPG identically to plain Image
        // when the source isn't a movie -- so this isn't a GIF-only
        // special case in principle. In practice, QMovie (the decoder
        // behind AnimatedImage) supports a genuinely narrower format set
        // than QImageReader (behind plain Image) -- confirmed live on
        // this exact machine that an .ico-format ~/.face.icon decodes
        // fine via Image but errors out via AnimatedImage every time.
        // avatarPreviewImageFallback below exists because of that: this
        // element is tried first (so a real GIF still animates), and
        // avatarPreviewWrap.activeAvatarImage (used by the gradient
        // placeholder above and MultiEffect below) only falls back to
        // plain Image once this one has genuinely failed to decode.
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

      ColumnLayout {
        Layout.alignment: Qt.AlignHCenter
        spacing: 1

        Text {
          Layout.alignment: Qt.AlignHCenter
          // Raw Quickshell.env("USER"), not settingsRoot.username --
          // matches the header's own "user@machine" string exactly.
          readonly property int detailStart: settingsRoot.hardwareName.indexOf(" (")
          readonly property string shortHardwareName: detailStart > 0 ? settingsRoot.hardwareName.slice(0, detailStart) : settingsRoot.hardwareName

          text: Quickshell.env("USER") + "@" + shortHardwareName
          font.family: settingsRoot.fontFamily
          font.pixelSize: 11
          color: settingsRoot.muted
        }

        Text {
          Layout.alignment: Qt.AlignHCenter
          readonly property int detailStart: settingsRoot.hardwareName.indexOf(" (")
          text: detailStart > 0 ? settingsRoot.hardwareName.slice(detailStart) : ""
          visible: text !== ""
          font.family: settingsRoot.fontFamily
          font.pixelSize: 10
          color: Qt.rgba(settingsRoot.muted.r, settingsRoot.muted.g, settingsRoot.muted.b, 0.78)
        }
      }

      // Collection picker -- direct follow-up chain: first "this uses
      // only 1 dicebear collections right, can we do buttons with the
      // collection name and clicking on them just shuffle from within
      // that collection?", then "we dont need the shuffle and reset
      // button, just put the collection there and then instead of
      // reset just call it the gradient collection". "Gradient" is now
      // just the first entry in settingsRoot.avatarCollections rather
      // than a separate Reset button/concept -- every click here (this
      // one included) goes through the same settingsRoot.selectAvatar()
      // entry point. Selecting one both picks it (highlighted border,
      // same selected-state treatment as Bar Layout's own segmented
      // buttons below) AND immediately applies it, not a separate
      // "pick then press an action button" step. Flow instead of a
      // RowLayout since 6 labels don't reliably fit one row at this
      // card's width; wraps to a second line instead of squeezing/
      // eliding.
      Flow {
        Layout.fillWidth: true
        spacing: 6

        Repeater {
          model: settingsRoot.avatarCollections

          Rectangle {
            id: collectionBtn
            required property var modelData
            readonly property bool isCurrent: settingsRoot.avatarCollection === collectionBtn.modelData.id
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

            MouseArea {
              anchors.fill: parent
              enabled: !settingsRoot.avatarBusy && collectionBtn.isAvailable
              cursorShape: collectionBtn.isAvailable ? Qt.PointingHandCursor : Qt.ArrowCursor
              // "custom" has no self-contained action the way every
              // other entry does (gradient/DiceBear/github all apply
              // immediately on click) -- it needs a file first, so this
              // opens the picker instead and lets its own onAccepted
              // below call selectAvatar() once something is actually
              // chosen.
              onClicked: {
                if (collectionBtn.modelData.id === "custom") avatarFileDialog.open()
                else settingsRoot.selectAvatar(collectionBtn.modelData.id)
              }
            }
          }
        }
      }

      // Native, XDG-portal-backed file picker -- confirmed live this
      // actually works from inside a Quickshell layer-shell PanelWindow
      // (not a given; Quickshell's own windows are not ordinary
      // top-level windows, which is what FileDialog normally expects to
      // parent to) before building this rather than assuming it would.
      FileDialog {
        id: avatarFileDialog
        title: "Choose Avatar Image"
        nameFilters: ["Images (*.png *.jpg *.jpeg *.gif *.webp *.bmp)"]
        onAccepted: {
          // selectedFile is a file:// URL, not a plain path -- decode
          // first so a filename with a space/unicode character in it
          // (URL-encoded in the url form) reaches ImageMagick correctly
          // rather than as a literal "%20" etc.
          var path = String(avatarFileDialog.selectedFile)
          if (path.indexOf("file://") === 0) path = decodeURIComponent(path.slice(7))
          settingsRoot.selectAvatar("custom", path)
        }
      }
    }
  }
  // Bar Layout -- own card, same segmented-button treatment as
  // Display's own Display Scale card (DisplayContent.qml).
  Rectangle {
    Layout.fillWidth: true
    Layout.preferredHeight: barModeCardContent.implicitHeight + 24
    radius: 10
    color: "#000000"

    ColumnLayout {
      id: barModeCardContent
      anchors.fill: parent
      anchors.margins: 12
      spacing: 12

      Text {
        text: "Bar Layout"
        font.family: settingsRoot.fontFamily
        font.pixelSize: 11
        font.weight: Font.DemiBold
        color: settingsRoot.muted
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: 6

        Repeater {
          model: [
            { id: "floating", label: "Floating" },
            { id: "docked", label: "Docked" }
          ]

          Rectangle {
            id: modeBtn
            required property var modelData
            readonly property bool isCurrent: settingsRoot.barMode === modeBtn.modelData.id

            Layout.fillWidth: true
            Layout.preferredHeight: 28
            radius: 6
            color: modeBtn.isCurrent ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
            border.width: 1
            border.color: modeBtn.isCurrent ? settingsRoot.accent : Qt.rgba(1, 1, 1, 0.12)

            Text {
              anchors.centerIn: parent
              text: modeBtn.modelData.label
              font.family: settingsRoot.fontFamily
              font.pixelSize: 11
              font.weight: modeBtn.isCurrent ? Font.DemiBold : Font.Normal
              color: modeBtn.isCurrent ? settingsRoot.textColor : settingsRoot.muted
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: settingsRoot.setBarMode(modeBtn.modelData.id)
            }
          }
        }
      }
    }
  }

  // Window Curvature -- own card, same segmented-button treatment as
  // Bar Layout above. Direct request: a Settings UI
  // for the on/half/square split hyprland/ruixen-lookfeel.sh already has.
  // "Off" (stock Omarchy, no border/blur/shadow either) isn't offered
  // here -- a much bigger toggle than just corner shape, stays
  // CLI-only. Clicking any option runs the real script and
  // restarts the shell (see setCornerCurvature's own comment), so
  // this settings panel itself will visibly reopen fresh a moment
  // after clicking -- expected, not a bug.
  Rectangle {
    Layout.fillWidth: true
    Layout.preferredHeight: curvatureCardContent.implicitHeight + 24
    radius: 10
    color: "#000000"

    ColumnLayout {
      id: curvatureCardContent
      anchors.fill: parent
      anchors.margins: 12
      spacing: 12

      Text {
        text: "Window Curvature"
        font.family: settingsRoot.fontFamily
        font.pixelSize: 11
        font.weight: Font.DemiBold
        color: settingsRoot.muted
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: 6

        Repeater {
          model: [
            { id: "sharp", label: "Sharp" },
            { id: "half", label: "Half" },
            { id: "rounded", label: "Rounded" }
          ]

          Rectangle {
            id: curvatureBtn
            required property var modelData
            readonly property bool isCurrent: settingsRoot.cornerCurvature === curvatureBtn.modelData.id

            Layout.fillWidth: true
            Layout.preferredHeight: 28
            radius: 6
            color: curvatureBtn.isCurrent ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
            border.width: 1
            border.color: curvatureBtn.isCurrent ? settingsRoot.accent : Qt.rgba(1, 1, 1, 0.12)

            Text {
              anchors.centerIn: parent
              text: curvatureBtn.modelData.label
              font.family: settingsRoot.fontFamily
              font.pixelSize: 11
              font.weight: curvatureBtn.isCurrent ? Font.DemiBold : Font.Normal
              color: curvatureBtn.isCurrent ? settingsRoot.textColor : settingsRoot.muted
            }

            MouseArea {
              anchors.fill: parent
              enabled: settingsRoot.ruixenRepoPath !== ""
              cursorShape: Qt.PointingHandCursor
              onClicked: settingsRoot.setCornerCurvature(curvatureBtn.modelData.id)
            }
          }
        }
      }

      Text {
        visible: settingsRoot.ruixenRepoPath === ""
        Layout.fillWidth: true
        text: "Needs a repo checkout path -- run install.sh or update.sh once from your ruixen-shell clone to enable this."
        wrapMode: Text.WordWrap
        font.family: settingsRoot.fontFamily
        font.pixelSize: 10
        color: settingsRoot.muted
      }
    }
  }

  // Window Spacing -- own card, same segmented-button treatment as
  // Bar Layout/Window Curvature above. Direct follow-up after
  // live-testing gaps_in 0 with `hyprctl eval`: "with the round
  // curvature on the window the tight spacing looks kinda bad, on
  // sharp it might be fine... its probably easier if its just a
  // setting". Unlike Window Curvature, this doesn't shell out to a
  // real script or need a repo checkout -- same plain-text-file +
  // hyprctl reload mechanism as Animation Style, so no ruixenRepoPath
  // guard here either. Applies under both Sharp and Rounded (direct
  // instruction: "if its tight then both round and sharp will get no
  // inner padding") -- both looknfeel.ruixen.lua and
  // looknfeel.square.lua read the same file.
  Rectangle {
    Layout.fillWidth: true
    Layout.preferredHeight: spacingCardContent.implicitHeight + 24
    radius: 10
    color: "#000000"

    ColumnLayout {
      id: spacingCardContent
      anchors.fill: parent
      anchors.margins: 12
      spacing: 12

      Text {
        text: "Window Spacing"
        font.family: settingsRoot.fontFamily
        font.pixelSize: 11
        font.weight: Font.DemiBold
        color: settingsRoot.muted
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: 6

        Repeater {
          model: [
            { id: "comfy", label: "Comfy" },
            { id: "tight", label: "Tight" }
          ]

          Rectangle {
            id: spacingBtn
            required property var modelData
            readonly property bool isCurrent: settingsRoot.spacingProfile === spacingBtn.modelData.id

            Layout.fillWidth: true
            Layout.preferredHeight: 28
            radius: 6
            color: spacingBtn.isCurrent ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
            border.width: 1
            border.color: spacingBtn.isCurrent ? settingsRoot.accent : Qt.rgba(1, 1, 1, 0.12)

            Text {
              anchors.centerIn: parent
              text: spacingBtn.modelData.label
              font.family: settingsRoot.fontFamily
              font.pixelSize: 11
              font.weight: spacingBtn.isCurrent ? Font.DemiBold : Font.Normal
              color: spacingBtn.isCurrent ? settingsRoot.textColor : settingsRoot.muted
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: settingsRoot.setSpacingProfile(spacingBtn.modelData.id)
            }
          }
        }
      }
    }
  }

  // Animation Style -- own card, same segmented-button treatment as
  // Bar Layout/Window Curvature/Window Spacing above -- moved to last
  // per direct request (reordering the page: "Bar Layout is the first
  // profile setting after the avatar stuff, then after bar layout lets
  // do the Window Curve and then Window Spacing, then last is the
  // Animation Style"). Direct request ("its the hyprland windows that
  // needs it... bubbly, calm, snappy seems to be enough") -- this only
  // ever switches Hyprland's own window animations (see
  // hyprland/looknfeel.ruixen.lua), nothing on the Quickshell/plugin
  // side changes; deliberately not called "Window Animations" though,
  // since "the plug ins dont need animations, its fine the way it is"
  // was explicit -- this card's own placement on the same page as Bar
  // Layout (a Hyprland-side setting too) is enough context for what it
  // actually controls.
  Rectangle {
    Layout.fillWidth: true
    Layout.preferredHeight: animationCardContent.implicitHeight + 24
    radius: 10
    color: "#000000"

    ColumnLayout {
      id: animationCardContent
      anchors.fill: parent
      anchors.margins: 12
      spacing: 12

      Text {
        text: "Animation Style"
        font.family: settingsRoot.fontFamily
        font.pixelSize: 11
        font.weight: Font.DemiBold
        color: settingsRoot.muted
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: 6

        Repeater {
          // Calm first (the new default), then Bubbly, then Snappy --
          // direct request ("switch the order so we start with calm
          // by default and then user can pick next toggle as Bubbly
          // then Snappy last").
          model: [
            { id: "calm", label: "Calm" },
            { id: "bubbly", label: "Bubbly" },
            { id: "snappy", label: "Snappy" }
          ]

          Rectangle {
            id: animBtn
            required property var modelData
            readonly property bool isCurrent: settingsRoot.animationProfile === animBtn.modelData.id

            Layout.fillWidth: true
            Layout.preferredHeight: 28
            radius: 6
            color: animBtn.isCurrent ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
            border.width: 1
            border.color: animBtn.isCurrent ? settingsRoot.accent : Qt.rgba(1, 1, 1, 0.12)

            Text {
              anchors.centerIn: parent
              text: animBtn.modelData.label
              font.family: settingsRoot.fontFamily
              font.pixelSize: 11
              font.weight: animBtn.isCurrent ? Font.DemiBold : Font.Normal
              color: animBtn.isCurrent ? settingsRoot.textColor : settingsRoot.muted
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: settingsRoot.setAnimationProfile(animBtn.modelData.id)
            }
          }
        }
      }
    }
  }

  // No more trailing fillHeight spacer -- direct follow-up ("nothing
  // is sticky... everything in the page scroll"): this page's own
  // ColumnLayout is naturally sized inside Settings.qml's shared
  // Flickable now, not a fixed-height container to absorb leftover
  // space in, so this sink has nothing left to do.
}
