#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

fail() {
  printf 'ruixen-shell update: %s\n' "$*" >&2
  exit 1
}

[[ -d "$script_dir/.git" ]] || fail "$script_dir isn't a git checkout -- clone the repo with git instead of copying files out of it"

command -v git >/dev/null 2>&1 || fail "git is required (command 'git' not found)"

printf '[1/2] Pulling latest changes\n'
git -C "$script_dir" pull || fail "git pull failed -- resolve manually (e.g. commit or stash local changes) and run this again"

printf '\n[2/2] Reinstalling\n'
"$script_dir/install.sh"
