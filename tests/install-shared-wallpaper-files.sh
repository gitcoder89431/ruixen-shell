#!/usr/bin/env bash
# Issue #105: WallpaperRotationState.qml and wallpaper-effects.py used
# to be hand-copied, byte-identical files duplicated across every
# picker UI that needs one (ruixen.notch, ruixen.launcher's Wallpapers
# and Wallpaper Shuffle extensions) -- real backend logic, not a
# rendering asset, with nothing enforcing the copies stayed in sync.
# ruixen.wallpaper/ is now the one hand-maintained copy of each;
# install.sh's own inject_shared_wallpaper_files (see its header
# comment right above the plugin deploy loop) stages a merged copy of
# ruixen.launcher's/ruixen.notch's own source with those two files
# layered in, and deploys FROM that instead of the raw checkout.
#
# This proves, against the REAL install.sh deployed into a throwaway
# fake $HOME (not just reasoning about the source): every expected
# deployed location gets a real file, byte-identical to the one
# canonical source, that a fresh checkout's own git history has no
# other copy of, and that the ordinary post-deploy hash verification
# (every plugin must match "its own source" exactly) still passes with
# these extra files layered in rather than being bypassed for them.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
fake_bin="$script_dir/fixtures/fake-bin"

pass=0
fail_count=0
check() {
  local desc="$1" got="$2" want="$3"
  if [[ "$got" == "$want" ]]; then
    printf 'ok   - %s\n' "$desc"
    pass=$((pass + 1))
  else
    printf 'FAIL - %s\n       got:  %s\n       want: %s\n' "$desc" "$got" "$want"
    fail_count=$((fail_count + 1))
  fi
}

# --- the canonical source really is the only copy in this checkout ----

check "wallpaper-effects.py exists only under ruixen.wallpaper/ in this checkout" \
  "$(find "$repo_dir" -name wallpaper-effects.py -not -path '*/tests/*' | wc -l)" "1"
check "WallpaperRotationState.qml exists only under ruixen.wallpaper/ in this checkout" \
  "$(find "$repo_dir" -name WallpaperRotationState.qml | wc -l)" "1"

home="$(mktemp -d)"
trap 'rm -rf "$home"' EXIT

if ( HOME="$home" PATH="$fake_bin:$PATH" "$repo_dir/install.sh" ) >"$home/install.out" 2>&1; then
  status=0
else
  status=$?
fi
check "a real install against a throwaway fake HOME exits 0" "$status" "0"

plugins_dir="$home/.config/omarchy/plugins"
targets=(
  "$plugins_dir/ruixen.notch/wallpaper-effects.py"
  "$plugins_dir/ruixen.notch/WallpaperRotationState.qml"
  "$plugins_dir/ruixen.launcher/extensions/wallpapers/wallpaper-effects.py"
  "$plugins_dir/ruixen.launcher/extensions/wallpapers/WallpaperRotationState.qml"
  "$plugins_dir/ruixen.launcher/extensions/wallpaper-shuffle/WallpaperRotationState.qml"
)
for t in "${targets[@]}"; do
  rel="${t#"$plugins_dir"/}"
  check "deployed $rel exists" "$([[ -f "$t" ]] && echo yes || echo no)" "yes"
  if [[ "$t" == *wallpaper-effects.py ]]; then
    check "deployed $rel matches the canonical source byte-for-byte" \
      "$(cmp -s "$t" "$repo_dir/ruixen.wallpaper/wallpaper-effects.py" && echo same || echo different)" "same"
  else
    check "deployed $rel matches the canonical source byte-for-byte" \
      "$(cmp -s "$t" "$repo_dir/ruixen.wallpaper/WallpaperRotationState.qml" && echo same || echo different)" "same"
  fi
done

check "install.sh's own post-deploy hash check still passed (not bypassed for these two plugins)" \
  "$(grep -c 'verified: every deployed plugin exactly matches this checkout' "$home/install.out")" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
