#!/usr/bin/env bash
# Covers ruixen.peripherals -- direct Discord ask, relayed: "battery
# percentage support for Bluetooth and wireless related devices," shown
# as pinnable icons on the bar (interaction modeled on ruixen.pluginpins).
#
# Detection logic (helper/status.py) is ported from
# github.com/xgborgeso/omarchy-peripheral-batteries (MIT license) --
# reading /sys/class/power_supply + /sys/class/hidraw directly, not
# Quickshell's own Bluetooth/UPower bindings, because both of those have
# real, live-confirmed coverage gaps: BlueZ's Battery1 D-Bus interface
# (what Quickshell.Bluetooth's own .battery property wraps) wasn't
# populated for a real connected Bluetooth keyboard despite UPower
# correctly reporting its battery, and neither binding sees non-Bluetooth
# USB wireless receivers (Logitech Bolt/Unifying/Lightspeed) at all.
#
# This exercises the ported Python helper directly against a synthetic
# sysfs tree (same technique the source repo's own tests/helper.test.py
# uses, via PERIPHERALS_SYSFS), plus static QML checks for the pin/glyph
# conventions this widget has to follow.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
helper_py="$repo_dir/ruixen.peripherals/helper/status.py"
widget_qml="$repo_dir/ruixen.peripherals/BarWidget.qml"
manifest_json="$repo_dir/ruixen.peripherals/manifest.json"

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

# --- synthetic sysfs tree ---------------------------------------------
tmp_root="$(mktemp -d)"
trap 'rm -rf "$tmp_root"' EXIT

# A real wireless keyboard's battery pack, no serial_number (matches the
# real hardware this was verified against live -- an empty serial falls
# back to the sys_name as the device id, not a crash).
kb_dir="$tmp_root/class/power_supply/hid-aa:bb:cc:dd:ee:ff-battery-1"
mkdir -p "$kb_dir"
printf 'Battery\n' > "$kb_dir/type"
printf 'Device\n' > "$kb_dir/scope"
printf '\n' > "$kb_dir/serial_number"
printf 'Wireless Keyboard\n' > "$kb_dir/model_name"
printf '\n' > "$kb_dir/manufacturer"
printf 'Discharging\n' > "$kb_dir/status"
printf '77\n' > "$kb_dir/capacity"

# The laptop's own battery -- must be excluded entirely.
laptop_dir="$tmp_root/class/power_supply/BAT0"
mkdir -p "$laptop_dir"
printf 'Battery\n' > "$laptop_dir/type"
printf 'System\n' > "$laptop_dir/scope"
printf '85\n' > "$laptop_dir/capacity"
printf 'Discharging\n' > "$laptop_dir/status"

# A Logitech receiver (hidraw) plus its own hidpp battery-reporting child
# device -- the receiver itself must be dropped once its child claims the
# connection (real dedup logic, the trickiest part of the ported code).
receiver_dir="$tmp_root/class/hidraw/hidraw0/device"
mkdir -p "$receiver_dir"
printf 'HID_NAME=Logitech USB Receiver\nHID_UNIQ=\nDRIVER=logitech-djreceiver\nHID_ID=0003:0000046D:0000C548\n' > "$receiver_dir/uevent"

child_dir="$tmp_root/class/hidraw/hidraw1/device"
mkdir -p "$child_dir"
printf 'HID_NAME=MX Master 3\nHID_UNIQ=aa-bb-cc-dd\nDRIVER=logitech-hidpp-device\nHID_ID=0003:0000046D:00004082\n' > "$child_dir/uevent"

mouse_pack_dir="$tmp_root/class/power_supply/hidpp_battery_5"
mkdir -p "$mouse_pack_dir"
printf 'Battery\n' > "$mouse_pack_dir/type"
printf 'Device\n' > "$mouse_pack_dir/scope"
printf 'aa-bb-cc-dd\n' > "$mouse_pack_dir/serial_number"
printf 'MX Master 3\n' > "$mouse_pack_dir/model_name"
printf 'Logitech\n' > "$mouse_pack_dir/manufacturer"
printf 'Unknown\n' > "$mouse_pack_dir/status"
# Empty capacity -- HID++ battery reporting is intermittent (confirmed
# live: a real MX Vertical mouse read back empty capacity between report
# events despite upower showing a cached last-known percentage). Output
# must mark this device unavailable ("--" in the UI), not crash or
# fabricate a number.
printf '\n' > "$mouse_pack_dir/capacity"

output="$(PERIPHERALS_SYSFS="$tmp_root" python3 "$helper_py")"

check "helper exits with valid JSON (ok: true)" \
  "$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['ok'])" "$output")" "True"

device_count="$(python3 -c "import json,sys; print(len(json.loads(sys.argv[1])['devices']))" "$output")"
check "exactly 2 devices reported (keyboard + mouse pack; laptop battery and bare receiver both excluded)" \
  "$device_count" "2"

kb_level="$(python3 -c "
import json,sys
d = json.loads(sys.argv[1])
row = next(r for r in d['devices'] if r['kind'] == 'keyboard')
print(row['level'])
" "$output")"
check "keyboard battery level read correctly from a serial-less pack" "$kb_level" "77"

kb_available="$(python3 -c "
import json,sys
d = json.loads(sys.argv[1])
row = next(r for r in d['devices'] if r['kind'] == 'keyboard')
print(row['available'])
" "$output")"
check "keyboard marked available (a real capacity value was present)" "$kb_available" "True"

mouse_row="$(python3 -c "
import json,sys
d = json.loads(sys.argv[1])
row = next(r for r in d['devices'] if r['brand'] == 'Logitech')
print(row['name'], row['available'], row['brand'])
" "$output")"
check "receiver correctly deduped against its own hidpp child (one Logitech row, not two)" \
  "$mouse_row" "MX Master 3 False Logitech"

check "laptop's own BAT0 pack never appears in the output" \
  "$(python3 -c "import json,sys; print(any('BAT0' in str(r) for r in json.loads(sys.argv[1])['devices']))" "$output")" \
  "False"

# --- static QML checks --------------------------------------------------
check "manifest declares both service and bar-widget kinds" \
  "$(grep -c '"service"' "$manifest_json")" "2"
check "manifest's bar-widget entry point is BarWidget.qml" \
  "$(grep -c '"barWidget": "BarWidget.qml"' "$manifest_json")" "1"

check "pin persistence uses mutateShellConfig, same primitive ruixen.pluginpins already uses" \
  "$(grep -c 'bar\.shell\.mutateShellConfig(function' "$widget_qml")" "1"
check "pinned ids are read back via the stock BarWidget base's own setting() helper" \
  "$(grep -c 'root\.setting("pinnedIds", \[\])' "$widget_qml")" "1"

# Every kind glyph and the trigger/pin glyphs must be QML \u escapes, not
# pasted Nerd Font characters -- direct precedent: a hidden/corrupted
# glyph byte has broken this exact thing multiple times already elsewhere
# in this repo.
#  (generic-device plug glyph) legitimately appears twice by design
# -- once as kindGlyph's own default case, once as the trigger button's
# own icon (intentionally the same "generic device" glyph both places).
declare -A expected_escape_counts=(
  ['\\uefba']=1 ['\\uf11c']=1 ['\\uf025']=1 ['\\uf11b']=1
  ['\\uf1e6']=2 ['\\uf005']=1
)
for esc in "${!expected_escape_counts[@]}"; do
  check "glyph $esc is a \\u escape, not a raw pasted character" \
    "$(grep -c "\"$esc\"" "$widget_qml")" "${expected_escape_counts[$esc]}"
done

# No literal multi-byte glyph characters anywhere in the file (the actual
# bug this session hit once while writing this same file: a first pass
# accidentally pasted the real glyphs instead of escaping them).
check "no raw pasted glyph characters anywhere in the widget source" \
  "$(python3 -c "
print('yes' if any(ord(c) > 0x2000 for c in open('$widget_qml', encoding='utf-8').read()) else 'no')
")" "no"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
