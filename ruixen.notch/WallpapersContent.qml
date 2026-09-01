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

  // Direct follow-up ("we should lazyload it in from the other
  // direction... it seems to be loading in 50, 49, 48, 47 etc so we
  // see a huge blank space while waiting for the top ones to load
  // in"). Real cause: Image's own asynchronous decode (below) hands
  // every initially-visible tile's request to Qt's decode thread at
  // once on first population, and that thread doesn't guarantee it
  // finishes a whole burst in the order the requests were issued --
  // empirically it was coming back closer to reverse order, so the
  // bottom rows resolved first and the top stayed blank longest. This
  // gate drip-feeds "permission to load" in strict ascending index
  // order instead, a couple tiles at a time, so requests never arrive
  // as one big simultaneous burst and the visible fill order matches
  // the array order (theme wallpapers, top-left, first) regardless of
  // whatever order the decode thread would otherwise finish in.
  property int loadGate: 0

  // "all", "image", "video", or "gif" -- direct request ("on the
  // right side of the panel, theres some space left like a right
  // panel, can we use these to toggle between IMAGE and VIDEO and
  // then GIF too"). Combines with searchText below rather than
  // replacing it -- a kind filter plus a live text search is more
  // useful than having to choose one or the other.
  property string kindFilter: "all"

  readonly property int imageCount: wallpaperPaths.filter(function(e) { return e.kind === "image" }).length
  readonly property int videoCount: wallpaperPaths.filter(function(e) { return e.kind === "video" }).length
  readonly property int gifCount: wallpaperPaths.filter(function(e) { return e.kind === "gif" }).length

  // Filename substring match against the REAL path (the video's own
  // filename, not its poster's hashed cache name) -- same logic as
  // ambxst's own WallpapersTab filteredWallpapers (ported the rule,
  // not the file -- their version is bound up with per-screen/OLED/
  // tint/scheme state this notch doesn't have). kindFilter narrows
  // first, search narrows further -- either or both can be active.
  readonly property var filteredPaths: {
    var result = kindFilter === "all" ? wallpaperPaths : wallpaperPaths.filter(function(e) { return e.kind === kindFilter })
    if (searchText.length === 0) return result
    var needle = searchText.toLowerCase()
    return result.filter(function(entry) {
      var fileName = entry.real.substring(entry.real.lastIndexOf("/") + 1).toLowerCase()
      return fileName.indexOf(needle) !== -1
    })
  }

  function refresh() {
    if (!listProc.running) listProc.running = true
    if (!currentProc.running) currentProc.running = true
  }

  onActiveChanged: if (active) refresh()

  // Drives loadGate up a couple tiles at a time -- fast enough that
  // the initial screenful fills in well under half a second, but
  // spaced out enough that each request has time to actually reach
  // Qt's decode thread before the next one arrives, which is what
  // keeps them from bunching into the kind of simultaneous burst that
  // was coming back out of order. Stops itself once the gate has
  // caught up to however many entries exist.
  Timer {
    interval: 10
    running: root.active && root.loadGate < root.wallpaperPaths.length
    repeat: true
    onTriggered: root.loadGate += 2
  }

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
  // image prints `image<US>path<US>path` (display and real are the
  // same thing); a gif prints `gif<US>path<US>path` too (no poster
  // needed -- Image already renders a gif's own first frame directly,
  // same as any other static image); a video ensures its poster
  // exists (same md5-of-real-path cache naming ruixen.wallpaper's own
  // Service.qml uses for its own poster lookups, so both sides agree
  // on the same cache file with neither one telling the other its
  // path) then prints `video<US>poster<US>path` -- a video with no
  // decodable first frame (corrupt file, unsupported codec) is
  // silently skipped rather than showing a broken tile.
  //
  // <US> is ASCII Unit Separator (0x1F), not "|" -- direct review
  // finding ("Harden wallpaper discovery/state serialization... a
  // legal Linux filename containing | breaks that record"). 0x1F is
  // the standard non-printable field-separator control character
  // (same family as CSV/TSV alternatives use for exactly this
  // reason), so a real filename would have to go out of its way to
  // contain it -- unlike "|", which plenty of real files legitimately
  // do. Records themselves stay newline-separated; find/sort/read all
  // moved to NUL-delimited (-print0/-z/-d '') so a filename is never
  // split on its own bytes during DISCOVERY either, only the (already
  // extremely unlikely) case of a literal embedded newline WITHIN a
  // filename can still misalign the record framing -- not attempted
  // here, no acceptance criterion asked for it and NUL can never
  // legally appear in a Linux path at all, so it was the one truly
  // safe choice for the parts of the pipeline that still needed one.
  //
  // Poster staleness: the ffmpeg extraction now also re-runs when the
  // source video is newer than its cached poster (`-nt`, bash's
  // built-in mtime comparison), not just when the poster is entirely
  // missing -- direct review finding ("replacing a video with new
  // content at the same path can keep the old cached poster
  // indefinitely"). Deliberately compares mtimes rather than baking
  // mtime into the cache filename itself: a changed filename would
  // orphan the old poster file forever with nothing to ever clean it
  // up, where overwriting the same filename in place needs no
  // separate pruning step at all.
  //
  // Skips the stock picker's thumbnail-cache indirection (list.sh)
  // since a handful of wallpaper-sized images downscaled via
  // Image.sourceSize is cheap enough on its own, same cost class as
  // the blurred-art backgrounds already loaded elsewhere in this
  // plugin. Poster generation is the one real added cost, but it's
  // cached after the first run (ffmpeg only runs for a file with no
  // cached poster yet, or a stale one), so only ever paid once per
  // video (twice if the video's ever replaced) -- and only video pays
  // it at all, gif never does.
  Process {
    id: listProc
    command: ["bash", "-c",
      "theme=$(cat \"$HOME/.local/state/omarchy/current/theme.name\" 2>/dev/null); " +
      "mkdir -p \"$HOME/Pictures/ruixen-wallpapers\" \"$HOME/.cache/ruixen/wallpaper-posters\"; " +
      "US=$'\\x1f'; " +
      "process() { while IFS= read -r -d '' f; do " +
      "case \"${f,,}\" in " +
      "*.mp4|*.mkv|*.webm|*.mov|*.m4v) " +
      "hash=$(printf '%s' \"$f\" | md5sum | cut -d' ' -f1); " +
      "poster=\"$HOME/.cache/ruixen/wallpaper-posters/$hash.jpg\"; " +
      "if [[ ! -f \"$poster\" ]] || [[ \"$f\" -nt \"$poster\" ]]; then " +
      "ffmpeg -y -loglevel quiet -i \"$f\" -vframes 1 -q:v 3 \"$poster\" 2>/dev/null; fi; " +
      "[[ -f \"$poster\" ]] && printf 'video%s%s%s%s\\n' \"$US\" \"$poster\" \"$US\" \"$f\" ;; " +
      "*.gif) printf 'gif%s%s%s%s\\n' \"$US\" \"$f\" \"$US\" \"$f\" ;; " +
      "*) printf 'image%s%s%s%s\\n' \"$US\" \"$f\" \"$US\" \"$f\" ;; " +
      "esac; done; }; " +
      "find -L \"$HOME/.local/state/omarchy/current/theme/backgrounds\" \"$HOME/.config/omarchy/backgrounds/$theme\" " +
      "-maxdepth 1 -type f \\( -iname \"*.jpg\" -o -iname \"*.jpeg\" -o -iname \"*.png\" -o -iname \"*.gif\" -o -iname \"*.bmp\" -o -iname \"*.webp\" " +
      "-o -iname \"*.mp4\" -o -iname \"*.mkv\" -o -iname \"*.webm\" -o -iname \"*.mov\" -o -iname \"*.m4v\" \\) " +
      "-print0 2>/dev/null | sort -z | process; " +
      "find -L \"$HOME/Pictures/ruixen-wallpapers\" " +
      "-maxdepth 1 -type f \\( -iname \"*.jpg\" -o -iname \"*.jpeg\" -o -iname \"*.png\" -o -iname \"*.gif\" -o -iname \"*.bmp\" -o -iname \"*.webp\" " +
      "-o -iname \"*.mp4\" -o -iname \"*.mkv\" -o -iname \"*.webm\" -o -iname \"*.mov\" -o -iname \"*.m4v\" \\) " +
      "-print0 2>/dev/null | sort -z | process"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text || "").split("\n").filter(function(line) { return line.length > 0 })
        root.wallpaperPaths = lines.map(function(line) {
          var parts = line.split("\u001f")
          return { kind: parts[0], display: parts[1], real: parts[2] }
        })
        root.loadGate = 0
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

  // Outer ColumnLayout -- direct follow-up ("put the right panel
  // below the search bar so keep search like before full"): the
  // search bar moved back out to span the FULL panel width again (it
  // had shrunk to just the grid column's own width once the sidebar
  // sat beside it at the same row), with a RowLayout now nested below
  // it instead of wrapping the whole page -- grid on the left,
  // sidebar on the right, only for the content BELOW the search bar.
  ColumnLayout {
    anchors.fill: parent
    spacing: 10

    // Search row -- plain TextInput + placeholder overlay, matching
    // this plugin's existing self-contained style (no qs.Ui.TextField
    // pulled in here, unlike ruixen.weather's location search -- that
    // one already has qs.Ui available; this plugin deliberately stays
    // on plain QML primitives throughout, see DashboardContent.qml).
    // Full Layout.fillWidth here now spans the whole panel again,
    // sidebar included -- it's a sibling of the RowLayout below, not
    // inside it.
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

    // Grid (left) + filter sidebar (right) -- direct request ("on the
    // right side of the panel, theres some space left like a right
    // panel, can we use these to toggle between IMAGE and VIDEO and
    // then GIF too"), then moved below the search bar per this same
    // follow-up. The grid's own 170px cells never evenly divide this
    // panel's real content width (790px -> 4 full columns, 680px
    // used, ~110px dead on the right no matter how many wallpapers
    // exist) -- that's the "space left" the sidebar fills instead of
    // leaving it empty.
    RowLayout {
      // Layout.maximumWidth freed for the same reason as the sidebar's
      // own comment below -- a nested RowLayout/ColumnLayout's
      // maximumWidth defaults to its own implicitWidth (here, the
      // wrapper's fixed 680 + the sidebar's natural content width +
      // spacing), not unbounded, so without this the RowLayout itself
      // never actually reached the outer ColumnLayout's real 790px and
      // the sidebar had no genuine leftover space to grow into no
      // matter what its own fillWidth/maximumWidth said.
      Layout.fillWidth: true
      Layout.maximumWidth: Number.POSITIVE_INFINITY
      Layout.fillHeight: true
      spacing: 10

    ColumnLayout {
      // Fixed width (matches the grid's own real 4-column content, see
      // GridView's own comment), not fillWidth -- this wrapper needs
      // to stop claiming the leftover space too, or the sidebar below
      // still has nothing real to center within even after the
      // GridView itself stopped stretching past its own content.
      // Layout.fillWidth: false is NOT redundant with preferredWidth
      // here -- a nested ColumnLayout/RowLayout child defaults
      // Layout.fillWidth to true even when never set (the same gotcha
      // already hit once on the sidebar itself, see its own comment
      // below), so leaving this unset would silently keep it
      // competing for the RowLayout's leftover space regardless of
      // the preferredWidth given here.
      Layout.preferredWidth: 680
      Layout.fillWidth: false
      Layout.fillHeight: true
      spacing: 10

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
      // Fixed width (4 columns * 170 cellWidth), not fillWidth --
      // direct follow-up ("theres still a bit of a gap between where
      // the stats are and the last wallpaper column, i think try and
      // center middle the three stats, so its not too leaning to the
      // right edge"). fillWidth made the grid claim every pixel the
      // RowLayout gave it, even the ~32px slack past its own real
      // 4-column content (170 doesn't evenly divide the available
      // width) -- that slack, plus the RowLayout's own spacing, is
      // exactly what read as "a gap before the stats". Fixing the
      // grid's own width to what it actually uses frees that leftover
      // space for the sidebar to legitimately claim and center within
      // instead, rather than the sidebar just sitting flush against
      // the panel's own right edge past an unclaimed gap.
      Layout.preferredWidth: 680
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

      // Any deliberate scroll means the user is actively looking for
      // something further down -- bypass loadGate entirely rather
      // than making a manually-scrolled-to tile wait its turn behind
      // a drip-feed meant only to smooth out the passive initial
      // fill.
      onMovementStarted: root.loadGate = root.wallpaperPaths.length

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
        // Only used to gate the Image source below against
        // root.loadGate -- see its own comment for why.
        required property int index
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
            // Empty source until loadGate reaches this tile's index --
            // see root.loadGate's own comment for why. Once a tile's
            // source has been set it stays set even if the gate logic
            // changes later (reuseItems recycles this same Image for a
            // different index on scroll, which reassigns source to
            // that new tile's own path directly, gate or not -- see
            // GridView's onMovementStarted above).
            source: tile.index <= root.loadGate ? ("file://" + tile.modelData.display) : ""
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

  // Right sidebar -- narrowed 92 -> 68, and Layout.fillWidth: false
  // added explicitly -- direct follow-up ("can we make the right
  // panel narrower? theres a gap of 1 column between right panel
  // stats and wallpapaper"). Real cause of the gap, confirmed live
  // via a debug width readout, not guessed: a ColumnLayout child
  // defaults Layout.fillWidth to true even when never set (unlike a
  // plain Item/Rectangle, which default it false -- the exact same
  // gotcha this repo has hit before). So this sidebar was ALSO
  // competing for the RowLayout's leftover space alongside the grid's
  // own explicit fillWidth, not just taking its 92px preferredWidth
  // and stopping -- it had actually grown to 189px, leaving the grid
  // with only 591px (591/170 = 3 columns, not 4), which is exactly
  // the "gap of 1 column" reported. IMAGE/VIDEO/GIF, each a real
  // toggle (click again to clear back to "all", not a fixed always-
  // one-active segmented group -- there's a genuine "show everything"
  // state here that a plain radio-button set doesn't have). Centered
  // number-then-label per direct request ("we can do like center
  // kinda design so number of images and then label IMAGE etc").
  //
  // Follow-up fix ("theres still a bit of a gap between where the
  // stats are and the last wallpaper column, i think try and center
  // middle the three stats, so its not too leaning to the right edge
  // of the notch"): narrowing this sidebar to a fixed 68px left the
  // RowLayout's real leftover space (everything past the grid's own
  // fixed 680px content, see the two ColumnLayout/GridView comments
  // above) unclaimed by anyone -- it just sat as a gap in front of
  // the sidebar, which was itself still pinned to the panel's right
  // edge. Fixed at the source instead of by nudging this element:
  // this sidebar goes back to fillWidth: true (now safe, since the
  // grid's own wrapper no longer over-claims), so it legitimately
  // spans the whole leftover region: and each chip below switches
  // from fillWidth (which would stretch it edge-to-edge across that
  // now-wider region) to a fixed width + Qt.AlignHCenter, so the chip
  // stack renders as a centered column within the sidebar's real
  // space instead of stretching or sitting flush right.
  ColumnLayout {
    id: sidebar
    // Layout.maximumWidth explicitly freed -- a nested RowLayout/
    // ColumnLayout child has its OWN Layout.maximumWidth implicitly
    // bound to its implicitWidth by default (unlike a plain Item/
    // Rectangle, whose maximumWidth defaults to unbounded), so
    // fillWidth alone is a no-op here: without this, the sidebar
    // stayed pinned to its content's own natural width (76px, the
    // chip width below) instead of stretching into the real leftover
    // RowLayout space, leaving the same unclaimed gap this whole fix
    // is meant to close.
    Layout.fillWidth: true
    Layout.maximumWidth: Number.POSITIVE_INFINITY
    Layout.fillHeight: true
    Layout.alignment: Qt.AlignTop
    spacing: 8

    Repeater {
      model: [
        { kind: "image", label: "IMAGE", count: root.imageCount },
        { kind: "video", label: "VIDEO", count: root.videoCount },
        { kind: "gif", label: "GIF", count: root.gifCount }
      ]

      Rectangle {
        id: filterChip
        required property var modelData
        readonly property bool selected: root.kindFilter === modelData.kind

        Layout.preferredWidth: 76
        Layout.alignment: Qt.AlignHCenter
        Layout.preferredHeight: 64
        radius: 10
        color: filterChip.selected ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(1, 1, 1, 0.04)
        border.width: 1
        border.color: filterChip.selected ? root.accent : Qt.rgba(1, 1, 1, 0.12)

        ColumnLayout {
          anchors.centerIn: parent
          spacing: 2

          Text {
            Layout.alignment: Qt.AlignHCenter
            text: filterChip.modelData.count
            font.family: root.fontFamily
            font.pixelSize: 18
            font.weight: Font.DemiBold
            color: filterChip.selected ? root.accent : root.textColor
          }

          Text {
            Layout.alignment: Qt.AlignHCenter
            text: filterChip.modelData.label
            font.family: root.fontFamily
            font.pixelSize: 9
            color: root.muted
          }
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.kindFilter = filterChip.selected ? "all" : filterChip.modelData.kind
        }
      }
    }

    // Back to top -- direct follow-up ("theres still some room left
    // under the gif stat, you think we can do a back to top button, i
    // feel like when im all the way scrolled down, theres no way back
    // up to the top of the list"). Only shown once there's actually
    // somewhere to go back to (grid.contentY > 0) -- GridView is
    // itself a Flickable, so its own contentY is the real scroll
    // position, no separate tracking needed. Plain contentY
    // assignment on click, matching this repo's own existing
    // scroll-to-top convention (ruixen.tray's trayMenuFlick.contentY
    // = 0), not a new animated-scroll pattern.
    Rectangle {
      id: backToTopButton
      visible: grid.contentY > 0
      Layout.preferredWidth: 76
      Layout.alignment: Qt.AlignHCenter
      // Same 64px height as the filter chips above, not a smaller
      // 36px -- direct follow-up ("try and make it consistenly the
      // same size stat card") -- and the same number-then-label
      // two-line layout, with the arrow standing in for the number
      // and TOP standing in for the kind label, rather than a single
      // centered line.
      Layout.preferredHeight: 64
      radius: 10
      color: backToTopArea.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(1, 1, 1, 0.04)
      border.width: 1
      border.color: Qt.rgba(1, 1, 1, 0.12)

      ColumnLayout {
        anchors.centerIn: parent
        spacing: 2

        Text {
          Layout.alignment: Qt.AlignHCenter
          text: "↑"
          font.family: root.fontFamily
          font.pixelSize: 18
          font.weight: Font.DemiBold
          color: backToTopArea.containsMouse ? root.accent : root.textColor
        }

        Text {
          Layout.alignment: Qt.AlignHCenter
          text: "TOP"
          font.family: root.fontFamily
          font.pixelSize: 9
          color: root.muted
        }
      }

      MouseArea {
        id: backToTopArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: grid.contentY = 0
      }
    }

    Item { Layout.fillHeight: true }
  }
  }
  }
}
