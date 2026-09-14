// Ported from bars/v1/ruixen.notch/WallpapersContent.qml -- same
// "plugin folders can't share a file" convention already used for
// AppLibrary.qml/AppSearch.js across ruixen.notch/ruixen.pinnedapps/
// ruixen.launcher. Direct request: a "Wallpapers" extension in the
// launcher's own landing list, ported rather than rebuilt ("its more
// of a port job, both can work and do the same thing for now") -- the
// notch's own copy is untouched, this is a second front door onto the
// exact same real omarchy-theme-bg-set/ruixen.wallpaper mechanism, not
// a fork of the underlying picker LOGIC (kindFilter, searchText,
// discovery, poster generation -- all identical). The one deliberate
// presentation difference is the removed right sidebar (see its own
// removal comment further down) -- keep both copies in sync by hand
// for everything else if this file's own picker logic changes.
import QtQuick
import QtQuick.Layouts
import Quickshell
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

  // Bumped on every select() call, passed to ruixen.wallpaper's own
  // playVideo/playGif/stop IPC calls so it can reject an out-of-order
  // arrival -- see that service's own selectGeneration/
  // acceptsGeneration comment for the full "why". Each of the three
  // kinds dispatches through its OWN Process (below), so nothing on
  // this side alone guarantees their independent `qs ipc call`
  // subprocesses arrive in click order when kinds are switched
  // rapidly; this is what actually closes that gap.
  //
  // Seeded from Date.now() (real, not int -- see below), not a plain
  // 0 -- direct review finding ("Make wallpaper selection generations
  // survive Notch reloads", #22): ruixen.wallpaper stays loaded and
  // keeps its OWN selectGeneration for its entire process lifetime,
  // but this WallpapersContent instance can be destroyed and recreated
  // independently of it -- ruixen.notch disabled/re-enabled, a plugin
  // reload. A freshly created instance restarting from 0 would send
  // generation 1 on its very first real click while the service might
  // already be sitting on, say, 15 from the PREVIOUS instance's
  // lifetime -- rejected as stale, and every click after it too, until
  // this counter climbed back past 15. Seeding from a wall-clock
  // timestamp instead means a brand-new instance's very first
  // generation is already astronomically larger than any plain
  // incrementing counter the old instance could plausibly have
  // reached, so it can never look older to the service. Still just a
  // plain +1 per click after that (see select() below), not a fresh
  // Date.now() read every time -- that keeps two clicks landing in the
  // same millisecond strictly ordered too, which re-reading the clock
  // on every click would not.
  //
  // `real`, not `int` -- confirmed empirically (isolated Quickshell
  // test), not assumed: Date.now()'s ~13-digit millisecond value
  // silently overflows QML's 32-bit `int` type. `real` (a JS double)
  // safely holds integers up to 2^53, comfortably covering millisecond
  // timestamps for millennia. ruixen.wallpaper/Service.qml's own
  // selectGeneration was widened to match -- see its own comment.
  property real selectGeneration: Date.now()

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
  // filename, not its poster's hashed cache name) -- a plain
  // independent filter, deliberately not carrying any per-screen/OLED/
  // tint/scheme state this notch doesn't have. kindFilter narrows
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
  // user's own persistent folder (~/Pictures/ruixen-wallpapers),
  // appended after -- direct request ("we can create /USER_wallpapper
  // and then show the images from that folder after the theme, and
  // then this folder survives theme changes").
  //
  // The actual discovery/classification/poster-caching pipeline lives
  // in list-wallpapers.sh, a sibling file in this same plugin
  // directory, not inline here -- direct review finding ("Extract
  // wallpaper discovery into shared production code so tests cannot
  // drift", #17): this used to be a raw inline Process.command string
  // with tests/wallpaper-discovery-format.sh keeping its own "faithful
  // copy" that had to be hand-kept in sync, a real risk of the test
  // silently drifting from what actually ships. That test now runs
  // this exact same script file, so there is only one implementation
  // to keep correct. See list-wallpapers.sh's own comment for the full
  // "why" behind the US-delimited record format, NUL-safe traversal,
  // and poster mtime-staleness logic -- unchanged from before, just
  // relocated. $HOME/.config/omarchy/plugins/ruixen.notch is where
  // install.sh's own `cp -r` always deploys this plugin (a fixed,
  // well-known location, unlike install.sh's own git checkout path,
  // which can live anywhere) -- same absolute-path-via-$HOME
  // convention this file already uses for favoritesPath below.
  Process {
    id: listProc
    command: [Quickshell.env("HOME") + "/.config/omarchy/plugins/ruixen.notch/list-wallpapers.sh"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text || "").split("\n").filter(function(line) { return line.length > 0 })
        root.wallpaperPaths = lines.map(function(line) {
          var parts = line.split("\u001f")
          // identity (#23): what to compare against currentBackground,
          // NOT necessarily what the tile renders (display) -- see
          // list-wallpapers.sh's own comment for why those diverge for
          // GIF specifically. Falls back to display if a 4th field is
          // ever missing (shouldn't happen -- this Process always runs
          // fresh -- but a silently-undefined identity would break
          // every GIF's CURRENT state instead of degrading gracefully
          // to the old, still-correct-for-image/video behavior).
          return { kind: parts[0], display: parts[1], real: parts[2], identity: parts[3] !== undefined ? parts[3] : parts[1] }
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
  // Harmless no-op if nothing was playing. No longer guarded by
  // `if (!stopVideoProc.running)` -- confirmed directly that
  // reassigning a Process's command while it's already running is
  // safe (the in-flight run finishes, then the reassigned command
  // fires), so skipping the reassignment here just meant a rapid
  // second stop could go out with a stale generation number instead
  // of the current one.
  Process {
    id: stopVideoProc
    stdout: StdioCollector { waitForEnd: true }
  }

  Process {
    id: playVideoProc
    stdout: StdioCollector { waitForEnd: true }
  }

  Process {
    id: playGifProc
    stdout: StdioCollector { waitForEnd: true }
  }

  // omarchy-shell, not a raw `qs -p /usr/share/omarchy/shell ipc call`
  // -- direct review finding ("Replace hardcoded /usr/share/omarchy/
  // shell IPC calls with omarchy-shell", #24): the raw form hardcodes
  // Omarchy's install path (breaks under a non-default OMARCHY_PATH)
  // and has no timeout at all, so a hung/unresponsive shell would hang
  // this Process indefinitely. omarchy-shell (confirmed by reading it
  // directly) resolves $OMARCHY_PATH itself, recovers WAYLAND_DISPLAY
  // for out-of-session callers, and wraps the call in a real timeout
  // (OMARCHY_SHELL_IPC_TIMEOUT, default 2s) -- this repo already uses
  // it elsewhere (ruixen.settingsbutton, ruixen-bar-mode.sh), this was
  // just the operational calls that predated it still using the old
  // form. No -q here: these are the actual functional action (playing
  // the video/gif IS the point of the click), so a real failure should
  // still show up in the journal even though nothing in this file
  // currently branches on the exit code either way.
  function select(entry) {
    // identity, not display (#23) -- optimistic immediate CURRENT
    // highlight the instant a tile is clicked, before the async IPC
    // call below even lands. For gif specifically, display is the raw
    // .gif (what the tile renders); identity is the cached poster path
    // Service.qml's own playGif() is about to actually write to
    // current/background, matching what a later refresh would read
    // back. Using display here for gif would highlight nothing at all
    // until the next refresh, since currentBackground would hold a
    // value (the raw gif) that no tile's own identity ever equals.
    root.currentBackground = entry.identity
    root.selectGeneration += 1
    var gen = String(root.selectGeneration)
    if (entry.kind === "video") {
      playVideoProc.command = ["omarchy-shell", "ruixen.wallpaper", "playVideo", entry.real, gen]
      playVideoProc.running = true
    } else if (entry.kind === "gif") {
      playGifProc.command = ["omarchy-shell", "ruixen.wallpaper", "playGif", entry.real, gen]
      playGifProc.running = true
    } else {
      stopVideoProc.command = ["omarchy-shell", "ruixen.wallpaper", "stop", gen]
      stopVideoProc.running = true
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

    // No inner search box here anymore -- direct request ("we dont need
    // two search box, use the launcher for wallpaper search input not
    // what we ported over"). Launcher.qml's own outer SearchHeader is
    // the single search input for this extension; it writes straight
    // into `searchText` below via a binding on this component's own
    // instance (`wallpapersContent.searchText: root.query`), the same
    // conditional-binding pattern already used there for selectedSourcePath/
    // sources/allOptionLabel. `searchText` itself and everything that
    // reads it (filteredPaths etc.) are untouched -- only this component's
    // own now-redundant text-entry UI is gone.

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
      // No sidebar to share this row with anymore in the launcher's own
      // copy (see the removed ColumnLayout's own former comment, right
      // before the grid wrapper below) -- fillWidth/maximumWidth existed
      // ONLY to give that sidebar real leftover space to grow into, so
      // both are gone too. Centered instead of stretched: the grid
      // wrapper below stays a fixed 680px (same 4-column content as the
      // notch's own copy), and this row now just wraps tightly around
      // it, so Qt.AlignHCenter on this row is what keeps it centered
      // within the launcher's own wider (920px) extension card instead
      // of sitting flush left with a bare gap where the sidebar used to
      // be.
      Layout.alignment: Qt.AlignHCenter
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

    // No inline "no results" Text here, unlike the notch's own copy --
    // direct report: "for the empty state instead of no result match
    // "" can it say like no result with the wallpaper icon, kinda like
    // the file search empty." Launcher.qml now overlays its own shared
    // EmptyState component (same one Search Files uses, just fed the
    // Wallpapers glyph) when filteredPaths is empty, reading straight
    // off this file's own filteredPaths/wallpaperPaths via its
    // wallpapersContent id -- no new property needed here.

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
      // put the hover frame's APPEARANCE on the same element that
      // holds the image, without keeping the image container itself
      // geometrically static. Animating a border directly on the
      // SAME ClippingRectangle that holds the image (animated
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
        // Compares against identity, not display (#23) -- for a video
        // entry, ruixen.wallpaper's own Service.qml sets
        // current/background to the POSTER, which for video already
        // equals display, so this used to just compare against display
        // directly. That broke for GIF specifically: Service.qml's
        // playGif() ALSO sets current/background to a cached poster
        // (#12, to avoid the ImageMagick memory blowup a raw
        // multi-frame GIF caused there), but a gif's display/real stay
        // the raw .gif (the tile thumbnail still renders the gif
        // directly, no poster file needed for that) -- so display could
        // never equal currentBackground for an active GIF, and it lost
        // its CURRENT state on every refresh/reopen. identity is
        // list-wallpapers.sh's own dedicated field for exactly this
        // comparison, computed with the same poster-hash formula
        // Service.qml uses, so it matches for all three kinds without a
        // branch here -- see that script's own comment for the full
        // "why" and how identity differs from display for GIF.
        //
        // Only read for the label's own text/color below -- the
        // frame itself (ring/band) stays hover-only regardless,
        // per direct request that active alone shouldn't keep it
        // lit at rest.
        readonly property bool active: tile.modelData.identity === root.currentBackground

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
            // actually-active wallpaper -- plain filename otherwise,
            // real's own (the video's real filename for a video
            // entry, not its poster's hashed cache name).
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

  // No right sidebar here, unlike the notch's own copy of this file --
  // direct report once this was live in the launcher's own wider card:
  // "instead of IMAGE GIF VIDEO AND TOP put these into the top part for
  // sources instead... make it drop down from All Types to Images
  // Video Gif picker instead." kindFilter (the property those chips
  // used to write) is unchanged and still the real filter -- Launcher.qml
  // now drives it through the same top-right dropdown Search Files uses
  // for its own source filter (see wallpaperTypeOptions there), reading
  // wallpapersContent.kindFilter directly by id. The notch's own
  // dashboard has no such dropdown to reuse and genuinely has "space
  // left... like a right panel" (its own original request), so its
  // copy keeps the sidebar as-is.
  }
  }
}
