#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

fail() {
  printf 'ruixen-shell update: %s\n' "$*" >&2
  exit 1
}

[[ -d "$script_dir/.git" ]] || fail "$script_dir isn't a git checkout -- clone the repo with git instead of copying files out of it"

command -v git >/dev/null 2>&1 || fail "git is required (command 'git' not found)"

# Issue #31: a completely separate, early code path, same shape as
# install.sh/uninstall.sh's own --dry-run branches -- exits before the
# lifecycle lock is acquired or git pull ever runs. The one git
# operation here (fetch) only updates the local origin/<branch>
# remote-tracking ref, never the working tree, so "no checkout/
# worktree mutation" holds even though this isn't purely offline --
# the same reasoning ruixen-doctor.sh's own real-fetch fix already
# established (a --dry-run fetch never actually refreshes that ref,
# which would make this report stale/wrong the moment it mattered).
if [[ "${1:-}" == "--dry-run" ]]; then
  printf '=== Ruixen Update -- dry run, nothing will be changed ===\n\n'

  current_sha="$(git -C "$script_dir" rev-parse --short HEAD 2>/dev/null || echo unknown)"
  branch="$(git -C "$script_dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
  printf 'Current revision: %s (branch %s)\n' "$current_sha" "$branch"

  if [[ -n "$(git -C "$script_dir" status --porcelain 2>/dev/null)" ]]; then
    printf 'Local changes: yes -- a real update would refuse to run until this checkout is clean\n\nNo files changed.\n'
    exit 0
  fi
  printf 'Local changes: none\n'

  if ! git -C "$script_dir" fetch --quiet origin "$branch" >/dev/null 2>&1; then
    printf 'Candidate revision: could not reach the remote (offline?) -- nothing else can be previewed\n\nNo files changed.\n'
    exit 0
  fi

  candidate_sha="$(git -C "$script_dir" rev-parse --short "origin/$branch" 2>/dev/null || echo unknown)"
  behind="$(git -C "$script_dir" rev-list --count "HEAD..origin/$branch" 2>/dev/null || echo '?')"
  if [[ "$current_sha" == "$candidate_sha" ]]; then
    printf 'Candidate revision: %s -- already up to date, nothing would be pulled\n\n' "$candidate_sha"
  else
    printf 'Candidate revision: %s (%s commit(s) ahead of current)\n\n' "$candidate_sha" "$behind"
    printf 'Note: the plugin/config preview below reflects the CURRENTLY checked-out\n'
    printf 'code, not the %s commit(s) that would actually be pulled first -- an exact\n' "$behind"
    printf 'preview of code not yet on disk is not possible without pulling it.\n\n'
  fi

  printf -- '--- What a real reinstall (install.sh) would then do, against the code currently on disk ---\n\n'
  exec "$script_dir/install.sh" --dry-run
fi

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

# Direct review finding ("Hold the lifecycle lock while update.sh
# changes the source checkout", #21): the dirty-checkout check above is
# read-only (a concurrent reader isn't dangerous on its own), but
# `git pull` below rewrites this checkout's actual files -- a manual
# install.sh running at the same time could previously read a torn mix
# of pre-pull and post-pull files from the very tree it's copying
# plugins out of. Acquired here, BEFORE the pull, and held all the way
# through install.sh below (acquire_lifecycle_lock exports a flag that
# script inherits and trusts, rather than re-locking and self-
# contending against its own parent) -- see
# lib/acquire-lifecycle-lock.sh's own comment for the full "why" and
# how this avoids the exact parent/child self-deadlock #16 originally
# sidestepped by having update.sh hold no lock at all.
state_dir="$HOME/.local/state/ruixen"
mkdir -p "$state_dir"
# shellcheck source=lib/acquire-lifecycle-lock.sh
source "$script_dir/lib/acquire-lifecycle-lock.sh"
acquire_lifecycle_lock "$state_dir" || exit 1

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
# The lock acquired above is still held here (released automatically
# only when THIS process eventually exits) -- install.sh inherits the
# RUIXEN_LIFECYCLE_LOCK_HELD flag acquire_lifecycle_lock exported and
# trusts it instead of trying to acquire a second, separate lock on the
# same file (which would otherwise self-contend against the one this
# script already holds). A second update.sh, or a manual install.sh,
# started while this one is running still can't race it -- its own
# fresh acquire_lifecycle_lock call finds the lock genuinely held and
# fails with a clear message instead of interleaving.
"$script_dir/install.sh"
