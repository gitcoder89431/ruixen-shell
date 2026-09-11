#!/usr/bin/env bash
# Issue #66: conservative disk-cache hygiene for the shared poster cache
# ($HOME/.cache/ruixen/wallpaper-posters). Three real producers write
# into it -- ruixen.wallpaper/Service.qml's own video/GIF poster
# generation (play()/playGif()), ruixen.launcher/FileSearchProvider.qml's
# own Search Files video preview, and ruixen.notch/list-wallpapers.sh's
# own picker thumbnails -- all keyed by an md5 hash of the SOURCE path.
# That's a one-way hash: a poster whose source has since been deleted,
# renamed, or moved can never be proven stale from its filename alone.
# Nothing currently prunes an orphaned entry, so a long-lived system
# with many changing videos/wallpapers accumulates unbounded disk-cache
# cruft over time. Not a RAM leak, not urgent -- pure disk hygiene.
#
# Migration-compatible two-tier policy:
#   - A NEW poster (this fix's own "<poster>.src" sidecar, written
#     alongside <hash>.jpg only when it's actually (re)generated -- see
#     each of the three producers' own comment) records its real source
#     path directly, so this script can check [ -e "$source" ] instead
#     of guessing. Pruned only when the source is confirmed gone AND the
#     poster itself has aged past STALE_GRACE_DAYS -- the grace period
#     specifically protects a disconnected removable/network source
#     (an unplugged USB drive, an unmounted rclone remote) from looking
#     "deleted" and getting pruned within a normal reconnect cycle: "A
#     disconnected rclone/USB source must not immediately cause its
#     cached posters to disappear."
#   - A LEGACY poster (written before this fix, no sidecar at all) can't
#     be proven stale OR still active -- kept unless it's aged past the
#     much more generous LEGACY_GRACE_DAYS on its own mtime alone, the
#     "keep unless safely old" policy for exactly this migration case.
#
# Bounded and safe by construction:
#   - -maxdepth 1 into one flat directory, never recurses -- cannot
#     delete or even look outside the exact poster cache root.
#   - -type f (no -L) -- a symlinked ".jpg" is silently skipped, never
#     followed or deleted ("reject/safely ignore symlinked or malformed
#     cache paths").
#   - NUL-delimited throughout (find -print0 / read -d '') -- a poster
#     filename (always a plain hex md5 in practice) or a source path
#     read back from a ".src" sidecar (which can legally contain
#     anything a real filesystem path can) is never split or
#     reinterpreted as multiple arguments, and never gets pasted into a
#     second shell command -- only ever used as a literal `-e`/`rm --`
#     argument.
#   - Failure-tolerant: an unreadable/malformed sidecar or a stat
#     failure just skips that one candidate (`continue`), never aborts
#     the whole pass -- "cleanup failure must never break launcher/
#     wallpaper behavior."
#   - Invoked in the background by list-wallpapers.sh (already an
#     occasional, not per-keystroke/per-result, real Ruixen maintenance
#     surface -- it only runs when the wallpaper picker itself opens),
#     so this never adds latency to a live search or wallpaper listing.
set -uo pipefail

poster_dir="${1:-$HOME/.cache/ruixen/wallpaper-posters}"
# Overridable via env for tests -- real production behavior never sets
# these, so it always gets the real defaults below.
stale_grace_days="${RUIXEN_POSTER_STALE_GRACE_DAYS:-30}"
legacy_grace_days="${RUIXEN_POSTER_LEGACY_GRACE_DAYS:-90}"

[[ -d "$poster_dir" ]] || exit 0

now=$(date +%s)
stale_cutoff=$(( now - stale_grace_days * 86400 ))
legacy_cutoff=$(( now - legacy_grace_days * 86400 ))

find "$poster_dir" -maxdepth 1 -type f -iname '*.jpg' -print0 2>/dev/null |
while IFS= read -r -d '' poster; do
  sidecar="$poster.src"
  mtime=$(stat -c '%Y' "$poster" 2>/dev/null) || continue

  if [[ -f "$sidecar" ]]; then
    source_path=$(cat "$sidecar" 2>/dev/null) || continue
    [[ -n "$source_path" ]] || continue
    # Still referenced by a real, currently-reachable source -- keep,
    # regardless of age. Covers the common case (source untouched) AND
    # a temporarily-unavailable removable/network source that just
    # happens to be reachable again by the time this runs.
    [[ -e "$source_path" ]] && continue
    (( mtime < stale_cutoff )) && rm -f -- "$poster" "$sidecar"
  else
    (( mtime < legacy_cutoff )) && rm -f -- "$poster"
  fi
done
