#!/usr/bin/env bash
# Pure function, no side effects: computes the restored `.bar` object
# uninstall.sh writes back, preserving third-party/foreign bar-layout
# entries a user added or moved while Ruixen was installed instead of
# wholesale-discarding them along with Ruixen's own. Direct review
# finding ("Preserve third-party bar widgets added while Ruixen is
# installed during uninstall", #26): uninstall.sh used to just
# `.bar = $pristineBar`, a full replace -- any widget a user added
# after Ruixen took over the bar slot (their own plugin, or one moved
# there from elsewhere) vanished from the layout the instant they
# uninstalled, even though the plugin's own files were untouched.
#
# Reads three JSON values as arguments:
#   $1 pristine bar object -- install.sh's own shell.json.pre-ruixen
#      snapshot's .bar, the user's real bar exactly as it was the
#      first time Ruixen ever touched shell.json.
#   $2 current bar object -- the LIVE shell.json's .bar, read by
#      uninstall.sh before anything is restored. Whatever the user's
#      desktop actually looks like right now: Ruixen's own widgets,
#      plus any foreign additions/moves made while Ruixen was active.
#   $3 the canonical Ruixen-owned bar object -- lib/ruixen-bar-
#      canonical.json's own content, the SAME file
#      lib/build-shell-json.sh reads, so "what Ruixen owns" can never
#      drift between install and uninstall.
#
# If the pristine bar has no `.layout` key at all (a genuinely
# different bar implementation that never used this
# {left,center,right}-region convention, e.g. tests/uninstall-bar-
# restore.sh's own local.neon-bar fixture), it's returned completely
# unchanged -- injecting a `.layout` key a bar doesn't understand
# wouldn't make any preserved widget actually appear anywhere real
# anyway, and this matches the exact-restoration behavior that existing
# test already expects.
#
# Otherwise, this is a GLOBAL merge across all three regions together,
# not three independent per-region ones -- an early version of this
# script did exactly that and got it wrong two different ways, both
# caught by testing against #26's own fixture list before this was ever
# wired into uninstall.sh:
#   - A widget present in BOTH baseline and current but with DIFFERENT
#     inline settings (the user changed something while Ruixen was
#     active) kept the STALE baseline settings, because "already in
#     baseline" alone was enough to skip it -- current's own edited
#     copy never got a chance to win.
#   - A widget the user dragged to a DIFFERENT region while Ruixen was
#     active came out DUPLICATED: once in its old baseline region
#     (nothing there recognized it had moved), and again in its new
#     current region (a legitimate "foreign survivor" for THAT region,
#     computed independently).
# The fix: resolve each non-Ruixen-owned id to exactly ONE final
# (region, entry) pair -- current's copy if the id still exists
# anywhere in current (reflects the user's latest intent: unchanged,
# moved, or edited), else baseline's copy -- before ever grouping
# anything back into left/center/right arrays.
#
# "Ruixen-owned" is that GLOBAL id set (every id anywhere in the
# canonical layout, regardless of which region it's canonically in),
# not a per-region one, and NOT inferred from an "omarchy." vs
# "ruixen." id prefix -- Ruixen's own canonical layout deliberately
# places several stock omarchy.* entries too (the clock, the menu,
# ...), and those must be recognized as Ruixen-managed here exactly
# the same way, never mistaken for something the user added.
#
# id-less entries can't be correlated across baseline/current at all
# (nothing to match on), so both sides pass straight through in their
# own original region unconditionally -- conservative in the sense
# that destroying a user's real (if oddly-shaped) entry would be worse
# than one appearing exactly where it already was, even at the cost of
# a possible duplicate if the same id-less entry happens to exist on
# both sides.
#
# A region's own current/baseline entries are deduped to unique ids
# (keeping the first occurrence, original order) before use --
# defensive against a genuinely malformed/duplicated live layout, not
# something expected in practice; caught live while testing this exact
# function against a synthetic duplicate-id fixture, not assumed.
set -Eeuo pipefail

pristine_bar="$1"
current_bar="$2"
ruixen_canonical_bar="$3"

jq -n \
  --argjson pristineBar "$pristine_bar" \
  --argjson currentBar "$current_bar" \
  --argjson ruixenBar "$ruixen_canonical_bar" \
  '
  def uniqueInOrder:
    reduce .[] as $x ([]; if any(.[]; . == $x) then . else . + [$x] end);

  def flattenRegions:
    [ ("left","center","right") as $r | (.layout[$r] // [])[] | {region: $r, entry: .} ];

  def taggedById:
    map(select(.entry.id != null)) | INDEX(.entry.id);

  if ($pristineBar.layout == null) then
    $pristineBar
  else
    ($ruixenBar | flattenRegions | map(select(.entry.id != null) | .entry.id)) as $ownedIds

    | ($pristineBar | flattenRegions) as $baselineFlat
    | ($currentBar | flattenRegions) as $currentFlat
    | ($baselineFlat | taggedById) as $baselineById
    | ($currentFlat | taggedById) as $currentById

    | ($baselineFlat | map(select(.entry.id != null) | .entry.id) | uniqueInOrder) as $baselineIdOrder
    | ($currentFlat | map(select(.entry.id != null) | .entry.id) | uniqueInOrder
        | map(select(($baselineById[.]) == null))) as $currentOnlyNewIds
    | ($baselineIdOrder + $currentOnlyNewIds) as $allIdsInOrder

    # Resolve each non-owned id to its FINAL {region, entry} -- current
    # wins if present, else baseline. `.id as $id |` is REQUIRED here,
    # not cosmetic: `$ownedIds | index(.id)` (no capture) re-binds `.`
    # to $ownedIds itself before `.id` evaluates, so `.id` tries to
    # index the ARRAY, not the id being tested -- caught live while
    # testing this exact function, not assumed: it fails with "Cannot
    # index array with string ("id")" every time without the capture.
    | ([ $allIdsInOrder[] | . as $id
        | select(($ownedIds | index($id)) == null)
        | (if $currentById[$id] != null then $currentById[$id] else $baselineById[$id] end)
      ]) as $resolvedNamedEntries

    | ($baselineFlat | map(select(.entry.id == null))) as $baselineIdless
    | ($currentFlat | map(select(.entry.id == null))) as $currentIdless

    | ($resolvedNamedEntries + $baselineIdless + $currentIdless) as $allResolved

    | $pristineBar
      + { layout: {
            left: [$allResolved[] | select(.region == "left") | .entry],
            center: [$allResolved[] | select(.region == "center") | .entry],
            right: [$allResolved[] | select(.region == "right") | .entry]
          }
        }
  end
  '
