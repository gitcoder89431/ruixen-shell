#!/usr/bin/env bash
# Restore one Ruixen-owned bar widget to its canonical bar.layout position.
# Used after `omarchy plugin enable <id>` because Omarchy's generic enable
# path can re-add a bar-widget in a generic standalone position, while Ruixen
# groups some widgets into structural pills.
set -Eeuo pipefail

plugin_id="${1:-}"
shell_json="${2:-$HOME/.config/omarchy/shell.json}"
canonical_json="${3:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/ruixen-bar-canonical.json}"

[[ -n "$plugin_id" ]] || exit 0
[[ -f "$shell_json" && -f "$canonical_json" ]] || exit 0

python3 - "$plugin_id" "$shell_json" "$canonical_json" <<'PY'
import json
import pathlib
import sys

plugin_id, shell_path, canonical_path = sys.argv[1:4]
shell_file = pathlib.Path(shell_path)
canonical_file = pathlib.Path(canonical_path)
sections = ("left", "center", "right")

try:
    data = json.loads(shell_file.read_text())
    canonical = json.loads(canonical_file.read_text())
except Exception:
    sys.exit(0)

bar = data.get("bar")
canonical_bar = canonical
if not isinstance(bar, dict) or bar.get("id") != "ruixen.bar":
    sys.exit(0)
if not isinstance(bar.get("layout"), dict) or not isinstance(canonical_bar.get("layout"), dict):
    sys.exit(0)

target_section = None
target_entry = None
for section in sections:
    for entry in canonical_bar["layout"].get(section, []) or []:
        if isinstance(entry, dict) and entry.get("id") == plugin_id:
            target_section = section
            target_entry = dict(entry)
            break
    if target_section:
        break

if not target_section or target_entry is None:
    sys.exit(0)

def entry_id(entry):
    if isinstance(entry, str):
        return entry
    if isinstance(entry, dict):
        return str(entry.get("id", ""))
    return ""

changed = False
layout = bar["layout"]

for section in sections:
    current = layout.get(section, [])
    if not isinstance(current, list):
        current = []
        changed = True
    filtered = [entry for entry in current if entry_id(entry) != plugin_id]
    if len(filtered) != len(current):
        changed = True
    layout[section] = filtered

target_list = layout.setdefault(target_section, [])
if not isinstance(target_list, list):
    target_list = []
    layout[target_section] = target_list
    changed = True

canonical_ids = [
    entry_id(entry)
    for entry in (canonical_bar["layout"].get(target_section, []) or [])
]
target_index = canonical_ids.index(plugin_id)

insert_at = len(target_list)
found_anchor = False
for following_id in canonical_ids[target_index + 1:]:
    for i, entry in enumerate(target_list):
        if entry_id(entry) == following_id:
            insert_at = i
            found_anchor = True
            break
    if found_anchor:
        break
else:
    for previous_id in reversed(canonical_ids[:target_index]):
        for i, entry in enumerate(target_list):
            if entry_id(entry) == previous_id:
                insert_at = i + 1
                found_anchor = True
                break
        if found_anchor:
            break

target_list.insert(insert_at, target_entry)
changed = True

if changed:
    shell_file.write_text(json.dumps(data, indent=2) + "\n")
PY
