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

# Apple Bluetooth keyboard stuck at a stale 0% after a re-pair -- real bug,
# ruixen-shell issue #37. manufacturer and model_name are both blank, and
# the hid's own vendor id is 0x004C, not Apple's USB vendor id 0x05AC --
# all three match real hardware exactly (confirmed live against the real
# keyboard's own /sys entries after this test was first written blind
# with a wrong vid and a fabricated "Apple" manufacturer field, which
# made the guard pass here while never actually firing on real hardware).
# Bluetooth's HID_ID vendor field is a Bluetooth SIG company id, a
# separate namespace from USB vendor ids -- Apple, Inc. is company id
# 0x004C there. Brand must resolve from BRAND_FROM_VID's 0x004C entry,
# not the manufacturer field, or this test would not have caught the
# real gap.
apple_kb_dir="$tmp_root/class/power_supply/hid-11:22:33:44:55:66-battery"
mkdir -p "$apple_kb_dir"
printf 'Battery\n' > "$apple_kb_dir/type"
printf 'Device\n' > "$apple_kb_dir/scope"
printf '11:22:33:44:55:66\n' > "$apple_kb_dir/serial_number"
printf 'Magic Keyboard\n' > "$apple_kb_dir/model_name"
printf '\n' > "$apple_kb_dir/manufacturer"
printf 'Discharging\n' > "$apple_kb_dir/status"
printf '0\n' > "$apple_kb_dir/capacity"

apple_hid_dir="$tmp_root/class/hidraw/hidraw2/device"
mkdir -p "$apple_hid_dir"
printf 'HID_NAME=Magic Keyboard\nHID_UNIQ=11:22:33:44:55:66\nDRIVER=apple\nHID_ID=0005:0000004C:00000267\n' > "$apple_hid_dir/uevent"

# A second Apple Bluetooth pack with a real nonzero level -- must NOT be
# touched by the same guard (only exactly-zero is treated as suspicious).
apple_trackpad_dir="$tmp_root/class/power_supply/hid-77:88:99:aa:bb:cc-battery"
mkdir -p "$apple_trackpad_dir"
printf 'Battery\n' > "$apple_trackpad_dir/type"
printf 'Device\n' > "$apple_trackpad_dir/scope"
printf '77:88:99:aa:bb:cc\n' > "$apple_trackpad_dir/serial_number"
printf 'Magic Trackpad\n' > "$apple_trackpad_dir/model_name"
printf '\n' > "$apple_trackpad_dir/manufacturer"
printf 'Discharging\n' > "$apple_trackpad_dir/status"
printf '64\n' > "$apple_trackpad_dir/capacity"

apple_trackpad_hid_dir="$tmp_root/class/hidraw/hidraw3/device"
mkdir -p "$apple_trackpad_hid_dir"
printf 'HID_NAME=Magic Trackpad\nHID_UNIQ=77:88:99:aa:bb:cc\nDRIVER=apple\nHID_ID=0005:0000004C:00000265\n' > "$apple_trackpad_hid_dir/uevent"

# A non-Apple device legitimately at 0% -- must NOT be reinterpreted by the
# same guard (it is brand/transport-scoped, not a blanket "zero means
# unavailable" rule).
generic_zero_dir="$tmp_root/class/power_supply/hid-de:ad:be:ef:00:01-battery"
mkdir -p "$generic_zero_dir"
printf 'Battery\n' > "$generic_zero_dir/type"
printf 'Device\n' > "$generic_zero_dir/scope"
printf 'de:ad:be:ef:00:01\n' > "$generic_zero_dir/serial_number"
printf 'Generic Controller\n' > "$generic_zero_dir/model_name"
printf 'Generic Corp\n' > "$generic_zero_dir/manufacturer"
printf 'Discharging\n' > "$generic_zero_dir/status"
printf '0\n' > "$generic_zero_dir/capacity"

generic_zero_hid_dir="$tmp_root/class/hidraw/hidraw4/device"
mkdir -p "$generic_zero_hid_dir"
printf 'HID_NAME=Generic Controller\nHID_UNIQ=de:ad:be:ef:00:01\nDRIVER=generic-bluetooth\nHID_ID=0005:00001234:00005678\n' > "$generic_zero_hid_dir/uevent"

output="$(PERIPHERALS_SYSFS="$tmp_root" python3 "$helper_py")"

check "helper exits with valid JSON (ok: true)" \
  "$(python3 -c "import json,sys; print(json.loads(sys.argv[1])['ok'])" "$output")" "True"

device_count="$(python3 -c "import json,sys; print(len(json.loads(sys.argv[1])['devices']))" "$output")"
check "exactly 5 devices reported (keyboard + mouse pack + 2 Apple packs + 1 generic-zero pack; laptop battery and bare receiver both excluded)" \
  "$device_count" "5"

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

# Apple Bluetooth keyboard reporting exactly 0 -- ruixen-shell issue #37
# regression: treated as unavailable, not a real 0%, so the bar falls
# back to the keyboard glyph instead of a confidently-wrong "0%".
apple_kb_row="$(python3 -c "
import json,sys
d = json.loads(sys.argv[1])
row = next(r for r in d['devices'] if r['name'] == 'Magic Keyboard')
print(row['available'], row['level'], row['status'], row['brand'], row['transport'])
" "$output")"
check "Apple Bluetooth keyboard at a stale 0% is reported unavailable, not a real 0%" \
  "$apple_kb_row" "False -1 unknown Apple bluetooth"

# The same guard must not touch a real nonzero reading from another
# Apple Bluetooth device -- only exactly-zero is ever suspicious.
apple_trackpad_row="$(python3 -c "
import json,sys
d = json.loads(sys.argv[1])
row = next(r for r in d['devices'] if r['name'] == 'Magic Trackpad')
print(row['available'], row['level'])
" "$output")"
check "Apple Bluetooth trackpad with a real nonzero level is reported as-is" \
  "$apple_trackpad_row" "True 64"

# Nor a non-Apple device that legitimately reports 0% -- the guard is
# brand/transport-scoped, not a blanket zero-means-unavailable rule.
generic_zero_row="$(python3 -c "
import json,sys
d = json.loads(sys.argv[1])
row = next(r for r in d['devices'] if r['name'] == 'Generic Controller')
print(row['available'], row['level'])
" "$output")"
check "non-Apple device legitimately at 0% is unaffected by the Apple-only guard" \
  "$generic_zero_row" "True 0"

# --- static QML checks --------------------------------------------------
check "manifest declares both service and bar-widget kinds" \
  "$(grep -c '"service"' "$manifest_json")" "2"
check "manifest's bar-widget entry point is BarWidget.qml" \
  "$(grep -c '"barWidget": "BarWidget.qml"' "$manifest_json")" "1"

# Single-selection redesign, direct follow-up: "the pin ability kinda
# sucks... can we collapse it into this so the main icon shows the
# battery icon always" -- one selectedId string (mutateShellConfig, same
# primitive ruixen.pluginpins already uses for its own pin persistence),
# not a pinnedIds array.
check "selection persistence uses mutateShellConfig, same primitive ruixen.pluginpins already uses" \
  "$(grep -c 'bar\.shell\.mutateShellConfig(function' "$widget_qml")" "1"
check "selectedId is read back via the stock BarWidget base's own setting() helper" \
  "$(grep -c 'root\.setting("selectedId", "")' "$widget_qml")" "1"
check "no leftover pinnedIds (the retired multi-pin design)" \
  "$(grep -c 'pinnedIds' "$widget_qml" || true)" "0"

# The battery-glyph icon set and its right-click percentage toggle were
# both retired in a later follow-up: "instead of showing the same
# battery icon as the laptop power battery, can be confusing, can it
# just show the % number" -- the main bar icon now shows plain percent
# text (mainText()) instead of a battery-shaped glyph, so there's
# nothing left to toggle between icon-only and icon-plus-percent.
check "no leftover showPercentage/togglePercentage (retired with the battery-glyph icon)" \
  "$(grep -c 'showPercentage\|togglePercentage' "$widget_qml" || true)" "0"
check "no leftover battery-glyph arrays/function (retired for plain percent text)" \
  "$(grep -c 'chargingIcons\|defaultIcons\|batteryGlyph' "$widget_qml" || true)" "0"
check "the bar icon's own slot width is fixed while a real percentage is showing, independent of the number's own digit count" \
  "$(grep -c 'root\.selectedDevice && root\.selectedDevice\.available && !vertical ? 1\.6 : 1' "$widget_qml")" "1"
check "the bar icon's own font is smaller than the default icon size, for the percent text specifically" \
  "$(grep -c 'fontSize: Style\.font\.bodySmall' "$widget_qml")" "1"

# Every kind glyph and the select glyph must be QML \u escapes, not
# pasted Nerd Font characters -- direct precedent: a hidden/corrupted
# glyph byte has broken this exact thing multiple times already
# elsewhere in this repo. The generic-device plug glyph legitimately
# appears twice by design -- once as kindGlyph's own default case, once
# as mainText's own "nothing selected yet" fallback.
declare -A expected_escape_counts=(
  ['\\uefba']=1 ['\\uf11c']=1 ['\\uf025']=1 ['\\uf11b']=1
  ['\\uf1e6']=2 ['\\uf00c']=1
)
for esc in "${!expected_escape_counts[@]}"; do
  check "glyph $esc is a \u escape, not a raw pasted character" \
    "$(grep -c "\"$esc\"" "$widget_qml")" "${expected_escape_counts[$esc]}"
done

# All of the old battery-glyph surrogate pairs (both the 10-level
# default/charging icons and the md-battery_unknown fallback) must be
# gone entirely now, not just unused.
for esc in '\\udb80\\udc79' '\\udb80\\udc85' '\\udb82\\udc9c' '\\udb80\\udc91'; do
  check "retired battery-glyph surrogate pair $esc is gone" \
    "$(grep -c "$esc" "$widget_qml" || true)" "0"
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
