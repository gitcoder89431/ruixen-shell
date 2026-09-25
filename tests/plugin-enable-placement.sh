#!/usr/bin/env bash
# Re-enabling a Ruixen bar-widget through Omarchy's generic plugin command can
# place it outside Ruixen's curated pill groups. The post-enable repair helper
# must put canonical widgets back into their canonical section/order.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
helper="$repo_dir/lib/restore-canonical-plugin-layout.sh"
settings_service="$repo_dir/ruixen.settings/services/PluginService.qml"
launcher_service="$repo_dir/ruixen.launcher/services/PluginService.qml"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
shell_json="$tmpdir/shell.json"

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

cat >"$shell_json" <<'JSON'
{
  "bar": {
    "id": "ruixen.bar",
    "layout": {
      "left": [
        { "id": "ruixen.settingsbutton" },
        { "id": "ruixen.applauncher" }
      ],
      "center": [
        { "id": "ruixen.weather" },
        { "id": "omarchy.clock" }
      ],
      "right": [
        { "id": "ruixen.tray", "hidden": ["keep.me"] },
        { "id": "ruixen.pluginpins" },
        { "id": "omarchy.system-update" },
        { "id": "omarchy.power" },
        { "id": "ruixen.quickactions" }
      ]
    }
  },
  "plugins": []
}
JSON

"$helper" ruixen.settingsbutton "$shell_json" "$repo_dir/lib/ruixen-bar-canonical.json"

right_ids="$(python3 - "$shell_json" <<'PY'
import json, sys
d=json.load(open(sys.argv[1]))
print(",".join(e.get("id","") for e in d["bar"]["layout"]["right"]))
PY
)"
left_ids="$(python3 - "$shell_json" <<'PY'
import json, sys
d=json.load(open(sys.argv[1]))
print(",".join(e.get("id","") for e in d["bar"]["layout"]["left"]))
PY
)"
tray_hidden="$(python3 - "$shell_json" <<'PY'
import json, sys
d=json.load(open(sys.argv[1]))
print(",".join(d["bar"]["layout"]["right"][0].get("hidden", [])))
PY
)"

check "settingsbutton is removed from the wrong left-side placement" \
  "$left_ids" "ruixen.applauncher"
check "settingsbutton is restored after quickactions in the canonical right-side group" \
  "$right_ids" "ruixen.tray,ruixen.pluginpins,omarchy.system-update,omarchy.power,ruixen.quickactions,ruixen.settingsbutton"
check "repair preserves unrelated inline widget settings" \
  "$tray_hidden" "keep.me"

check "standalone settings service repairs canonical placement after enable" \
  "$(grep -cF 'restore-canonical-plugin-layout.sh' "$settings_service")" "1"
check "launcher settings service repairs canonical placement after enable" \
  "$(grep -cF 'restore-canonical-plugin-layout.sh' "$launcher_service")" "1"
check "standalone settings service allows reload failure without hiding enable failure" \
  "$(grep -cF '&& { omarchy-shell shell reloadConfig >/dev/null 2>&1 || true; }' "$settings_service")" "1"
check "launcher settings service allows reload failure without hiding enable failure" \
  "$(grep -cF '&& { omarchy-shell shell reloadConfig >/dev/null 2>&1 || true; }' "$launcher_service")" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
