#!/usr/bin/env bash
# Covers the manifest-checking half of "[P1] Add automated QA/CI for
# manifests, shell scripts, models, and installer lifecycle": for
# every ruixen.*/manifest.json, checks valid JSON, required fields
# present, id matches its own directory name, ids are unique across
# the whole plugin set, and every declared entry point file actually
# exists.
#
# Deliberately does NOT shell out to `omarchy plugin validate` --
# that's the real, stronger, install-time check install.sh already
# runs, but it needs a real Omarchy install to exist, which a plain CI
# runner won't have (the issue's own stated non-goal: don't try to
# fully emulate the Omarchy/Hyprland environment in this first CI
# pass). This is a self-contained, portable subset that runs anywhere
# jq does.
#
# Required fields below are the ones every manifest in this repo
# already has in common (checked directly, not assumed) -- license,
# barWidget, omarchy, and keepLoaded are real but kind-specific, not
# universal, so they're not enforced here.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"

pass=0
fail_count=0

ok() { printf 'ok   - %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf 'FAIL - %s\n' "$1"; fail_count=$((fail_count + 1)); }

required_fields=(author description entryPoints id kinds name schemaVersion version)

declare -A seen_ids

for dir in "$repo_dir"/ruixen.*/; do
  [[ -d "$dir" ]] || continue
  plugin_dir_name="$(basename "$dir")"
  manifest="$dir/manifest.json"

  if [[ ! -f "$manifest" ]]; then
    bad "$plugin_dir_name: missing manifest.json"
    continue
  fi

  if ! jq empty "$manifest" >/dev/null 2>&1; then
    bad "$plugin_dir_name: manifest.json is not valid JSON"
    continue
  fi
  ok "$plugin_dir_name: manifest.json is valid JSON"

  missing_fields=""
  for field in "${required_fields[@]}"; do
    if ! jq -e --arg f "$field" 'has($f)' "$manifest" >/dev/null 2>&1; then
      missing_fields="$missing_fields $field"
    fi
  done
  if [[ -n "$missing_fields" ]]; then
    bad "$plugin_dir_name: manifest.json missing required field(s):$missing_fields"
  else
    ok "$plugin_dir_name: manifest.json has all required fields"
  fi

  manifest_id="$(jq -r '.id // ""' "$manifest")"
  if [[ "$manifest_id" != "$plugin_dir_name" ]]; then
    bad "$plugin_dir_name: manifest id \"$manifest_id\" does not match its own directory name"
  else
    ok "$plugin_dir_name: manifest id matches its own directory name"
  fi

  if [[ -n "$manifest_id" ]]; then
    if [[ -n "${seen_ids[$manifest_id]:-}" ]]; then
      bad "$plugin_dir_name: id \"$manifest_id\" is already used by ${seen_ids[$manifest_id]}"
    else
      seen_ids["$manifest_id"]="$plugin_dir_name"
    fi
  fi

  entry_points="$(jq -r '.entryPoints // {} | to_entries[] | .key + "=" + .value' "$manifest" 2>/dev/null)"
  if [[ -z "$entry_points" ]]; then
    bad "$plugin_dir_name: entryPoints is missing or empty"
  else
    entry_points_ok=1
    while IFS= read -r kv; do
      [[ -n "$kv" ]] || continue
      entry_file="${kv#*=}"
      if [[ ! -f "$dir/$entry_file" ]]; then
        bad "$plugin_dir_name: declared entry point \"$entry_file\" does not exist"
        entry_points_ok=0
      fi
    done <<<"$entry_points"
    [[ "$entry_points_ok" -eq 1 ]] && ok "$plugin_dir_name: all declared entry points exist"
  fi

  kinds_count="$(jq '.kinds // [] | length' "$manifest" 2>/dev/null)"
  if [[ "${kinds_count:-0}" -lt 1 ]]; then
    bad "$plugin_dir_name: kinds is missing or empty"
  else
    ok "$plugin_dir_name: kinds is a non-empty array"
  fi
done

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
