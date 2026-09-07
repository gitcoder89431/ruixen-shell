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

# ruixen.settings' own Plugins page "check for updates" icon -- a
# stable machine-readable sibling of --dry-run above, not a replacement
# for it. Deliberately its own flag rather than reusing --dry-run's
# prose output: that text is already covered by tests/update-dry-run.sh
# and free to keep changing wording-wise, which would be a bad contract
# for a UI to parse. Same read-only fetch-then-compare (never mutates
# the working tree) as --dry-run, plus one thing --dry-run doesn't
# report: WHICH of this monorepo's own ruixen.* plugin directories are
# actually among the pending commits, even though update.sh always
# pulls (and install.sh reinstalls) every plugin together as one unit
# regardless of which ones actually changed.
if [[ "${1:-}" == "--check-json" ]]; then
  if [[ -n "$(git -C "$script_dir" status --porcelain 2>/dev/null)" ]]; then
    printf '{"error":"dirty checkout"}\n'
    exit 0
  fi

  branch="$(git -C "$script_dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"
  if [[ -z "$branch" ]] || ! git -C "$script_dir" fetch --quiet origin "$branch" >/dev/null 2>&1; then
    printf '{"error":"fetch failed"}\n'
    exit 0
  fi

  current_sha="$(git -C "$script_dir" rev-parse HEAD 2>/dev/null || echo "")"
  candidate_sha="$(git -C "$script_dir" rev-parse "origin/$branch" 2>/dev/null || echo "")"
  if [[ -z "$current_sha" || -z "$candidate_sha" ]]; then
    printf '{"error":"could not resolve revisions"}\n'
    exit 0
  fi

  if [[ "$current_sha" == "$candidate_sha" ]]; then
    printf '{"upToDate": true, "changedPlugins": []}\n'
    exit 0
  fi

  # Top-level ruixen.* directory names only, deduped -- a plugin
  # touched by more than one changed file must only show up once.
  changed_plugins="$(git -C "$script_dir" diff --name-only "$current_sha..$candidate_sha" \
    | grep -oE '^ruixen\.[^/]+' | sort -u || true)"
  changed_json="$(printf '%s\n' "$changed_plugins" | awk 'NF{printf "%s\"%s\"", (NR>1?",":""), $0}')"
  printf '{"upToDate": false, "changedPlugins": [%s]}\n' "$changed_json"
  exit 0
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
# fetch + merge --ff-only, NOT `git pull --ff-only` -- live user
# report: a raw "fatal: cannot rebase onto multiple branches" from git
# itself, printed right before this script's own clearer failure
# message below, confusing to read as one blob. Root cause NOT
# confirmed -- tried reproducing it here with a couple of plausible
# local-git-config culprits (branch.master.merge with two entries plus
# pull.rebase=true; a `pull = pull --rebase` alias) and --ff-only
# correctly overrode both every time, so whatever triggered it on that
# specific machine remains unknown. Switched anyway: `git fetch` +
# `git merge` are separate top-level commands with no rebase-related
# config path at all (rebase is a categorically different subcommand
# from merge), so this sequence can't hit that class of surprise
# regardless of the actual mechanism, known or not.
# --ff-only itself is unchanged: refuses outright rather than merging
# if history has diverged (a force-pushed rewrite upstream, or local
# commits this checkout made itself) -- exactly the "avoid silently
# merging" ask, and a clearer failure than an unexpected merge commit
# or conflict markers appearing in a script that's supposed to be
# non-interactive.
current_branch="$(git -C "$script_dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"
[[ -n "$current_branch" ]] || fail "could not determine the current branch (detached HEAD?) -- resolve manually and run this again"
git -C "$script_dir" fetch origin "$current_branch" \
  || fail "git fetch failed -- check your network connection and try again"
if ! git -c advice.diverging=false -C "$script_dir" merge --ff-only "origin/$current_branch" 2>/dev/null; then
  # -c advice.diverging=false above suppresses git's own multi-line
  # "hint:" block (confirmed live: 7+ lines of generic merge/rebase
  # advice ahead of the one line that actually matters) -- the Plugins
  # settings page's own error display only shows the LAST 3 lines of
  # this script's stderr, and that hint noise was crowding out (or at
  # least badly cluttering) this message right when a user needed it
  # clearest. Named and counted here instead of just "local commits
  # here" -- direct follow-up ("so they made a change to the git
  # cloned repo, and then they commit it... how can we get out of
  # this"): the actual, by far most likely cause for this specific
  # distribution model (clone + run scripts, not a personal fork) is a
  # commit made directly in the checkout, not a force-push, so the
  # message leads with that and gives the exact count instead of
  # leaving the reader to go figure out which of two vague
  # possibilities applies to them. origin/$current_branch, not a
  # hardcoded origin/master -- correct even for someone who's on a
  # different branch for whatever reason.
  local_only="$(git -C "$script_dir" rev-list --count "origin/$current_branch..HEAD" 2>/dev/null || echo "some")"
  fail "this checkout has $local_only local commit(s) not on origin/$current_branch, so it can't be fast-forwarded. Most likely cause: something was edited and committed directly in this checkout (this repo is meant to stay a clean clone in sync with origin, not a personal fork -- use Ruixen Settings or the toggle scripts in this repo for customization instead). If you don't need to keep that commit: git reset --hard origin/$current_branch, then run this again. If you DO need to keep it: resolve it by hand (rebase, or move it to your own branch) before this script can proceed"
fi

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
