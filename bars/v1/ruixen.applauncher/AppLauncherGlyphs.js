// Curated Nerd Font icon options for the app launcher's own mark --
// direct community pointer to github.com/Ryoku-dev/ryoku's own
// Identity/Launcher Mark picker ("a ton of good glyph people like to
// use as options"), ported from that project's own
// launcherLogoIconOptions/launcherLogoIconCodes table. Filtered to
// exactly the codepoints CONFIRMED present in this repo's own real
// JetBrainsMono Nerd Font (checked directly with fontTools against
// the installed .ttf, not assumed from Ryoku's own list, same "verify
// the actual font, don't guess" standard AppLauncher.qml's own arch
// glyph comment already holds itself to) -- Ryoku's own "ryoku"
// (U+529B) and "dragon" (U+2EEF) both need a CJK font this repo
// doesn't ship, so both are dropped rather than risk a tofu box.
// 111 of Ryoku's own 113 non-wordmark options survived that check
// unchanged.
var ICONS = {
  // Distros / OS -- "arch" deliberately keeps THIS repo's own existing
  // 0xF303 (linux-archlinux), not Ryoku's own different 0xE732 arch
  // glyph, so shipping this picker doesn't silently change the
  // current default's look for anyone who never touches this setting
  // (see AppLauncher.qml's own comment on why 0xF303 specifically was
  // chosen: a denser filled shape that reads better at this size than
  // a thinner outline glyph did).
  "arch": 0xF303, "hyprland": 0xF359, "ubuntu": 0xF31B, "debian": 0xF306,
  "fedora": 0xF30A, "gentoo": 0xF30D, "void": 0xF32E, "artix": 0xF31F,
  "manjaro": 0xF312, "suse": 0xF314, "alpine": 0xF300, "endeavour": 0xF322,
  "garuda": 0xF337, "cachyos": 0xF385, "freebsd": 0xF30C, "apple": 0xF302,
  "raspi": 0xF315, "elementary": 0xF309, "gnome": 0xF361, "alma": 0xF31D,
  "centos": 0xF304, "devuan": 0xF307, "arco": 0xF346, "ferris": 0xF323,
  "codeberg": 0xF330, "gitea": 0xF339, "tux": 0xF31A, "android": 0xE70E,
  "mint": 0xF30E, "kali": 0xF327, "popos": 0xF32A, "zorin": 0xF32F,
  "plasma": 0xF332, "wayland": 0xF367, "docker": 0xF308,
  // Generic marks
  "grid": 0xEEED, "spark": 0xE6A4, "power": 0xF011, "mark": 0xEE99,
  "nix": 0xF313, "branch": 0xE666, "rebel": 0xF1D0,
  // Dev tools / languages / apps
  "github": 0xE709, "git": 0xE702, "gitlab": 0xE7EB, "python": 0xE73C,
  "rust": 0xE7A8, "go": 0xE724, "node": 0xE719, "react": 0xE7BA,
  "vue": 0xE8DC, "kube": 0xE81D, "vim": 0xE7C5, "neovim": 0xE83A,
  "firefox": 0xE745, "chrome": 0xE743, "java": 0xE738, "js": 0xE781,
  "ts": 0xE8CA, "cpp": 0xE7A3, "ruby": 0xE739, "php": 0xE73D,
  "swift": 0xE755, "kotlin": 0xE81B, "lua": 0xE826, "haskell": 0xE777,
  "blender": 0xE766, "figma": 0xE7DA, "redis": 0xE76D, "postgres": 0xE76E,
  "steam": 0xF1B6, "spotify": 0xF1BC, "discord": 0xF1FF, "telegram": 0xF2C6,
  "slack": 0xF198,
  // Fun / thematic
  "empire": 0xF1D1, "jedi": 0xEECC, "sith": 0xEDDC, "mandalorian": 0xEDD9,
  "firstorder": 0xF2B0, "deathstar": 0xF08D8, "spaceinvaders": 0xF0BC9,
  "ghost": 0xEEFE, "pokeball": 0xF041D, "pokemon": 0xF0A09, "gamepad": 0xF11B,
  "retropad": 0xF0B82, "d20": 0xEEF5, "playstation": 0xED18, "xbox": 0xED3E,
  "switch": 0xF07E1, "minecraft": 0xF0373, "wizard": 0xEF01, "dungeon": 0xEEFA,
  "sword": 0xF04E5, "shield": 0xED25, "crown": 0xEDEB, "skull": 0xEE15,
  "crossbones": 0xEF0E, "ninja": 0xF0774, "robot": 0xEE0D, "alien": 0xF089A,
  "knight": 0xED63, "paw": 0xF1B0, "masks": 0xF0D02, "theater": 0xEEB6,
  "film": 0xF008, "spade": 0xF08D1, "superpowers": 0xF2DD, "reddit": 0xF1A1,
  "twitch": 0xF1E8
}

var DEFAULT_ICON_ID = "arch"

function iconIds() {
  return Object.keys(ICONS)
}

function iconValid(id) {
  return Object.prototype.hasOwnProperty.call(ICONS, id)
}

function defaultIconId() {
  return DEFAULT_ICON_ID
}

function iconGlyph(id) {
  var code = ICONS[iconValid(id) ? id : DEFAULT_ICON_ID]
  return String.fromCodePoint(code)
}
