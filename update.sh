#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

fail() {
  printf 'ruixen-shell update: %s\n' "$*" >&2
  exit 1
}

[[ -d "$script_dir/.git" ]] || fail "$script_dir isn't a git checkout -- clone the repo with git instead of copying files out of it"

command -v git >/dev/null 2>&1 || fail "git is required (command 'git' not found)"

# Direct review finding ("safer release update behavior"): a bare
# `git pull` merges by default, which for a checkout with local commits
# (a user's own experiment, or a dev workflow) silently creates a merge
# commit rather than telling them their history has diverged from
# upstream. Local uncommitted changes are surfaced explicitly instead
# of being carried along into whatever gets installed next, or lost if
# the pull happens to conflict with them.
if [[ -n "$(git -C "$script_dir" status --porcelain 2>/dev/null)" ]]; then
  fail "this checkout has local changes (git status) -- commit, stash, or discard them before updating, so it's clear what's actually being installed"
fi

before_sha="$(git -C "$script_dir" rev-parse --short HEAD 2>/dev/null || echo unknown)"
before_version="$(git -C "$script_dir" log -1 --format=%cd --date=short 2>/dev/null || echo unknown)"

printf '[1/2] Pulling latest changes (currently at %s, %s)\n' "$before_sha" "$before_version"
# --ff-only refuses outright rather than merging if history has
# diverged (a force-pushed rewrite upstream, or local commits this
# checkout made itself) -- exactly the "avoid silently merging" ask,
# and a clearer failure than an unexpected merge commit or conflict
# markers appearing in a script that's supposed to be non-interactive.
git -C "$script_dir" pull --ff-only \
  || fail "git pull --ff-only failed -- this checkout's history has diverged from upstream (a force-push, or local commits here). Resolve manually (e.g. git log, git reset --hard origin/master if you're sure) and run this again"

after_sha="$(git -C "$script_dir" rev-parse --short HEAD 2>/dev/null || echo unknown)"
if [[ "$before_sha" == "$after_sha" ]]; then
  printf '  already up to date (%s)\n' "$after_sha"
else
  printf '  updated %s -> %s\n' "$before_sha" "$after_sha"
fi

printf '\n[2/2] Reinstalling\n'
# Deliberately no lock taken in THIS script -- install.sh below is what
# actually mutates anything, and it takes its own lock (see its own
# comment, "Add an install/update/uninstall lock and collision-safe run
# identifiers", #16). Locking only there, not also here, is exactly
# what avoids a parent/child self-deadlock: update.sh never holds the
# lock, so install.sh always gets a genuinely fresh one, whether it was
# invoked from here or run directly. A second update.sh (or a manual
# install.sh) started while this one is mid-pull still can't race this
# run's own install.sh -- its child will contend for the same lock and
# fail with a clear message instead of interleaving.
"$script_dir/install.sh"
