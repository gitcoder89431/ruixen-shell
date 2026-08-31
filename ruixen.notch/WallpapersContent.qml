import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import Quickshell.Widgets

// Real wallpaper picker for the notch dashboard's own "Wallpapers" tab,
// replacing the "coming soon" stub. Reads from the exact same two
// directories Omarchy's own omarchy-theme-bg-switcher does (confirmed
// by reading that script directly, not guessed), plus one of this
// plugin's own -- direct request ("each theme has unique wallpapers,
// we can keep this and show them first... but can we also show from
// the folder like in /Pictures/... this folder survives theme
// changes"):
//   - ~/.local/state/omarchy/current/theme/backgrounds (the active
//     theme's own shipped wallpapers)
//   - ~/.config/omarchy/backgrounds/<theme-name>/ (Omarchy's existing
//     per-theme user-additions folder -- already the real extension
//     point, no custom watcher needed)
//   - ~/Pictures/ruixen-wallpapers (this plugin's own persistent folder,
//     shown after the two above -- never touched by Omarchy's theme
//     switching, unlike the first two, so whatever's dropped in here
//     survives every theme change untouched)
// Clicking a plain image tile calls the same real omarchy-theme-bg-set
// the stock picker uses, so it stays byte-for-byte consistent with
// Super+Ctrl+Space's own picker (same symlink write, same live shell
// notify) -- this is a second front door onto the same state, not a
// parallel one.
//
// Video and GIF tiles -- direct request ("can we remake one in our
// shell like ruixen-wallpaper plugin that works with our notch... it
// just needs to show up in the notch wallpaper picker"), GIF added as
// the planned fast-follow ("yea lets do the gif next"). Video/GIF
// playback itself lives entirely in the separate ruixen.wallpaper
// service plugin (see its own Service.qml for the real mechanism --
// video is a from-scratch port of yesheytenzin/live-wallpaper's own
// design, used only as a reference; GIF has no reference, it's just
// QML's own native AnimatedImage); this file's own job is discovering
// video/gif files alongside plain images, generating/caching a poster
// frame for video specifically (Image can't decode video, so the tile
// itself always shows a real image regardless of source kind -- a gif
// needs no such extraction, Image already renders its own first frame
// directly), and routing a click to the right place -- ruixen.
// wallpaper's own playVideo/playGif IPC for those two kinds, the
// normal omarchy-theme-bg-set flow for everything else.
Item {
  id: root

  property color textColor: "#ffffff"
  property color muted: Qt.rgba(1, 1, 1, 0.5)
  property color accent: "#3ecf5b"
  property string fontFamily: "JetBrainsMono Nerd Font"

  // Only visible/active while the tab itself is on screen -- refresh()
  // is cheap (two quick Processes) but no reason to run it while some
  // other tab is showing.
  property bool active: false

  // Each entry: { kind, display, real }. kind is "image", "gif", or
  // "video" -- an explicit tag now, not derived from display/real
  // differing the way it briefly was for video-only support: a gif
  // entry has display === real (same as a plain image, no poster
  // needed) but still needs routing to playGif, not the plain
  // omarchy-theme-bg-set flow, so equality alone can't distinguish
  // them anymore. display is always a real *image* path (the file
  // itself for a plain wallpaper or gif, a generated poster frame for
  // video) -- the tile's own Image element never needs to know or
  // care which kind it's looking at, it just always renders display.
  // real is what actually gets played -- passed to omarchy-theme-bg-
  // set for images, or ruixen.wallpaper's playVideo/playGif for those
  // two kinds.
  property var wallpaperPaths: []
  property string currentBackground: ""
  property string searchText: ""

  // Filename substring match against the REAL path (the video's own
  // filename, not its poster's hashed cache name) -- same logic as
  // ambxst's own WallpapersTab filteredWallpapers (ported the rule,
  // not the file -- their version is bound up with per-screen/OLED/
  // tint/scheme state this notch doesn't have).
  readonly property var filteredPaths: {
    if (searchText.length === 0) return wallpaperPaths
    var needle = searchText.toLowerCase()
    return wallpaperPaths.filter(function(entry) {
      var fileName = entry.real.substring(entry.real.lastIndexOf("/") + 1).toLowerCase()
      return fileName.indexOf(needle) !== -1
    })
  }

  function refresh() {
    if (!listProc.running) listProc.running = true
    if (!currentProc.running) currentProc.running = true
  }

  onActiveChanged: if (active) refresh()

  // Theme wallpapers (the exact same two directories/extensions
  // omarchy-theme-bg-switcher passes to the stock image-picker
  // overlay -- verified by reading that script directly) THEN the
  // user's own persistent folder, appended after -- direct request
  // ("we can create /USER_wallpapper and then show the images from
  // that folder after the theme, and then this folder survives theme
  // changes"). Two `find ... | sort | process` pipelines run back to
  // back in one script rather than one combined find+sort, specifically
  // so the two groups stay in that order in the output -- a single
  // sort across all three directories would interleave user wallpapers
  // alphabetically among the theme ones instead of keeping them after.
  // ~/Pictures/ruixen-wallpapers is plain filesystem state (not
  // ~/.local/state/ruixen/ like this repo's other persisted settings)
  // on purpose -- Pictures is where a person would actually go drop
  // image files in with a file manager, and it's never touched by
  // Omarchy's own theme switching (unlike the two directories above,
  // which are theme-scoped and change contents whenever the active
  // theme does), so it survives every theme change untouched. Created
  // with mkdir -p on every refresh so it's there and ready even
  // before the user has dropped anything into it.
  //
  // The `process` shell function classifies each found file: a plain
  // image prints `image|path|path` (display and real are the same
  // thing); a gif prints `gif|path|path` too (no poster needed --
  // Image already renders a gif's own first frame directly, same as
  // any other static image); a video ensures its poster exists (same
  // md5-of-real-path cache naming ruixen.wallpaper's own Service.qml
  // uses for its own poster lookups, so both sides agree on the same
  // cache file with neither one telling the other its path) then
  // prints `video|poster|path` -- a video with no decodable first
  // frame (corrupt file, unsupported codec) is silently skipped
  // rather than showing a broken tile.
  //
  // Skips the stock picker's thumbnail-cache indirection (list.sh)
  // since a handful of wallpaper-sized images downscaled via
  // Image.sourceSize is cheap enough on its own, same cost class as
  // the blurred-art backgrounds already loaded elsewhere in this
  // plugin. Poster generation is the one real added cost, but it's
  // cached after the first run (ffmpeg only runs for a file with no
  // cached poster yet), so only ever paid once per video -- and only
  // video pays it at all, gif never does.
  Process {
    id: listProc
    command: ["bash", "-c",
      "theme=$(cat \"$HOME/.local/state/omarchy/current/theme.name\" 2>/dev/null); " +
      "mkdir -p \"$HOME/Pictures/ruixen-wallpapers\" \"$HOME/.cache/ruixen/wallpaper-posters\"; " +
      "process() { while IFS= read -r f; do " +
      "case \"${f,,}\" in " +
      "*.mp4|*.mkv|*.webm|*.mov|*.m4v) " +
      "hash=$(printf '%s' \"$f\" | md5sum | cut -d' ' -f1); " +
      "poster=\"$HOME/.cache/ruixen/wallpaper-posters/$hash.jpg\"; " +
      "[[ -f \"$poster\" ]] || ffmpeg -y -loglevel quiet -i \"$f\" -vframes 1 -q:v 3 \"$poster\" 2>/dev/null; " +
      "[[ -f \"$poster\" ]] && printf 'video|%s|%s\\n' \"$poster\" \"$f\" ;; " +
      "*.gif) printf 'gif|%s|%s\\n' \"$f\" \"$f\" ;; " +
      "*) printf 'image|%s|%s\\n' \"$f\" \"$f\" ;; " +
      "esac; done; }; " +
      "find -L \"$HOME/.local/state/omarchy/current/theme/backgrounds\" \"$HOME/.config/omarchy/backgrounds/$theme\" " +
      "-maxdepth 1 -type f \\( -iname \"*.jpg\" -o -iname \"*.jpeg\" -o -iname \"*.png\" -o -iname \"*.gif\" -o -iname \"*.bmp\" -o -iname \"*.webp\" " +
      "-o -iname \"*.mp4\" -o -iname \"*.mkv\" -o -iname \"*.webm\" -o -iname \"*.mov\" -o -iname \"*.m4v\" \\) " +
      "2>/dev/null | sort | process; " +
      "find -L \"$HOME/Pictures/ruixen-wallpapers\" " +
      "-maxdepth 1 -type f \\( -iname \"*.jpg\" -o -iname \"*.jpeg\" -o -iname \"*.png\" -o -iname \"*.gif\" -o -iname \"*.bmp\" -o -iname \"*.webp\" " +
      "-o -iname \"*.mp4\" -o -iname \"*.mkv\" -o -iname \"*.webm\" -o -iname \"*.mov\" -o -iname \"*.m4v\" \\) " +
      "2>/dev/null | sort | process"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text || "").split("\n").filter(function(line) { return line.length > 0 })
        root.wallpaperPaths = lines.map(function(line) {
          var parts = line.split("|")
          return { kind: parts[0], display: parts[1], real: parts[2] }
        })
      }
    }
  }

  Process {
    id: currentProc
    command: ["bash", "-c", "readlink -f \"$HOME/.local/state/omarchy/current/background\" 2>/dev/null"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.currentBackground = String(text || "").trim()
    }
  }

  // Same real command the stock Super+Ctrl+Space picker's own selection
  // handler runs -- just symlinks current/background and notifies the
  // live shell, doesn't touch theme colors at all.
  Process {
    id: setProc
    stdout: StdioCollector { waitForEnd: true }
  }

  // Stops any playing video/gif the instant a plain image is picked
  // here -- ruixen.wallpaper's own 1s poll would eventually catch
  // this too (comparing current/background against its last-set
  // posterPath), but that poll is really a safety net for the STOCK
  // Omarchy picker, which has no way to know this plugin exists at
  // all. Our own picker can just say so directly and immediately.
  // Harmless no-op if nothing was playing.
  Process {
    id: stopVideoProc
    command: ["qs", "-p", "/usr/share/omarchy/shell", "ipc", "call", "ruixen.wallpaper", "stop"]
  }

  Process {
    id: playVideoProc
    stdout: StdioCollector { waitForEnd: true }
  }

  Process {
    id: playGifProc
    stdout: StdioCollector { waitForEnd: true }
  }

  function select(entry) {
    root.currentBackground = entry.display
    if (entry.kind === "video") {
      playVideoProc.command = ["qs", "-p", "/usr/share/omarchy/shell", "ipc", "call", "ruixen.wallpaper", "playVideo", entry.real]
      playVideoProc.running = true
    } else if (entry.kind === "gif") {
      playGifProc.command = ["qs", "-p", "/usr/share/omarchy/shell", "ipc", "call", "ruixen.wallpaper", "playGif", entry.real]
      playGifProc.running = true
    } else {
      if (!stopVideoProc.running) stopVideoProc.running = true
      setProc.command = ["omarchy-theme-bg-set", entry.real]
      setProc.running = true
    }
  }

  ColumnLayout {
    anchors.fill: parent
    spacing: 10

    // Search row -- plain TextInput + placeholder overlay, matching
    // this plugin's existing self-contained style (no qs.Ui.TextField
    // pulled in here, unlike ruixen.weather's location search -- that
    // one already has qs.Ui available; this plugin deliberately stays
    // on plain QML primitives throughout, see DashboardContent.qml).
    Rectangle {
      Layout.fillWidth: true
      Layout.preferredHeight: 40
      radius: 12
      color: Qt.rgba(1, 1, 1, 0.06)

      TextInput {
        id: searchInput
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        verticalAlignment: TextInput.AlignVCenter
        color: root.textColor
        font.family: root.fontFamily
        font.pixelSize: 12
        clip: true

        onTextChanged: root.searchText = text

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "Search wallpapers..."
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: 12
          visible: searchInput.text.length === 0
        }
      }
    }

    Text {
      Layout.fillWidth: true
      Layout.fillHeight: true
      visible: root.filteredPaths.length === 0
      horizontalAlignment: Text.AlignHCenter
      verticalAlignment: Text.AlignVCenter
      // Dropped "for this theme" -- no longer accurate on its own now
      // that ~/Pictures/ruixen-wallpapers is a real second source.
      text: root.wallpaperPaths.length === 0 ? "No wallpapers found" : "No wallpapers match “" + root.searchText + "”"
      color: root.muted
      font.family: root.fontFamily
      font.pixelSize: 12
    }

    // GridView, not Flow+Repeater -- direct follow-up ("theres no
    // preview image, only the first one has preview image... it just
    // shows up now, took sometime to load, do we do like lazy load or
    // something?"). Flow+Repeater instantiated and started loading
    // EVERY tile's Image the instant the tab opened, no matter how
    // many wallpapers exist or how many are actually visible -- fine
    // at the handful of theme wallpapers this was built against, but
    // a real problem once ~/Pictures/ruixen-wallpapers had a real
    // library dropped into it (330 files, several multi-megabyte
    // PNGs, confirmed directly on this machine) -- all 330 Image
    // decodes queued up at once, so only the first few finished fast
    // and the rest visibly popped in one at a time as their turn in
    // the decode queue came up. GridView is a real fix, not a tuning
    // knob: it only ever creates delegates for the tiles actually in
    // (or near) the viewport, and reuseItems: true recycles them
    // during scroll (changes an existing Image's source instead of
    // destroying/recreating it) -- so opening this tab now only ever
    // starts as many decodes as fit on screen, regardless of whether
    // the library has 4 wallpapers or 4000.
    GridView {
      id: grid
      Layout.fillWidth: true
      Layout.fillHeight: true
      visible: root.filteredPaths.length > 0
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      reuseItems: true
      // 160x100 tile + 10px gap on the right/bottom of each cell --
      // same visual spacing Flow's own `spacing: 10` produced.
      cellWidth: 170
      cellHeight: 110
      model: root.filteredPaths

      // Structural rewrite per direct correction: the previous pass
      // copied ambxst's frame APPEARANCE without their actual
      // rendering structure. Ambxst never animates a border on the
      // image container itself -- the wallpaper image stays
      // geometrically static, and a separate highlight overlay
      // draws above it. Copying the frame onto the SAME
      // ClippingRectangle that holds the image (animated
      // border.width, a permanent Image margin, an idle
      // Behavior-driven fill color) is what caused the reported
      // zoom/flash/lingering-fade symptoms -- each one traced back
      // to the image container's own geometry or render layer
      // changing. Fixed by fully separating them: the image sits in
      // its own static, never-animated container; the ring, inner
      // line, and label are separate sibling overlays with fixed
      // geometry, toggled by plain `visible: tile.hovered` and
      // nothing else -- no Behaviors anywhere in this delegate, so
      // there's no lingering fade after the pointer leaves either.
      delegate: Item {
        id: tile
        // { kind, display, real } now, not a bare path string -- see
        // root.wallpaperPaths' own comment for why.
        required property var modelData
        readonly property bool hovered: tileMouse.containsMouse
        // Compares against display, not real -- for a video entry,
        // ruixen.wallpaper's own Service.qml sets current/background
        // to the POSTER (display), not the original video file, so
        // display is what root.currentBackground will actually equal
        // while that video is the active wallpaper. For an image or a
        // gif, display and real are the same path anyway, so this is
        // correct for all three kinds without needing a branch.
        //
        // Only read for the label's own text/color below -- the
        // frame itself (ring/band) stays hover-only regardless,
        // per direct request that active alone shouldn't keep it
        // lit at rest.
        readonly property bool active: tile.modelData.display === root.currentBackground

        width: 160
        height: 100

        // Image container -- always exactly `width`x`height`, no
        // margins, no border, no animated properties at all. This
        // is the ONLY thing visible at rest. Always a real *image*
        // (display) even for a video entry -- Image can't decode
        // video frames, display is guaranteed to be an actual poster
        // image file for those.
        ClippingRectangle {
          anchors.fill: parent
          radius: 10
          color: "transparent"

          Image {
            anchors.fill: parent
            source: "file://" + tile.modelData.display
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize: Qt.size(160, 100)
          }
        }

        // Hover decoration only -- a separate overlay sibling, not
        // a property on the image's own container, so it can never
        // affect the image's geometry or force a clip rebuild.
        // Two directly-adjacent bands stacked outside-in: accent
        // ring at the very edge, then the black band starting
        // exactly where the ring ends (anchors.margins here MUST
        // equal the ring's own border.width, 2 -- anything bigger
        // leaves a transparent gap between them that the raw image
        // shows through, reading as a separate floating ring
        // instead of one continuous frame).
        Rectangle {
          anchors.fill: parent
          radius: 10
          color: "transparent"
          border.width: 2
          border.color: root.accent
          visible: tile.hovered
          z: 2

          Rectangle {
            anchors.fill: parent
            anchors.margins: 2
            radius: 8
            color: "transparent"
            border.width: 9
            border.color: "#000000"
          }
        }

        // Filename label -- also a separate overlay sibling, fixed
        // geometry, plain visible toggle.
        Rectangle {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.margins: 5
          height: 26
          color: Qt.rgba(0, 0, 0, 0.82)
          visible: tile.hovered
          z: 3

          Text {
            anchors.centerIn: parent
            width: parent.width - 12
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            // "CURRENT" in the theme's own accent color for the
            // actually-active wallpaper, matching ambxst's real
            // treatment (their isCurrentWallpaper label swaps to
            // Styling.srItem("overprimary") the same way) -- plain
            // filename otherwise, real's own (the video's real
            // filename for a video entry, not its poster's hashed
            // cache name).
            text: tile.active ? "CURRENT" : tile.modelData.real.substring(tile.modelData.real.lastIndexOf("/") + 1)
            color: tile.active ? root.accent : root.textColor
            font.family: root.fontFamily
            font.pixelSize: 10
          }
        }

        MouseArea {
          id: tileMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.select(tile.modelData)
          z: 4
        }
      }
    }
  }
}
