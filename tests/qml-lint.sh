#!/usr/bin/env bash
# Issue #107: neither `omarchy plugin validate` nor the rest of this test
# suite actually compiles/loads QML, so a missing import or a broken type
# reference can survive every static check here and only show up after a
# real `omarchy restart shell` (dev/README.md's own local-workflow step 2
# already warns about exactly this). This runs Qt's real QML linter over
# every .qml file in the repo as a strongest-practical-without-a-live-
# desktop gate, not a replacement for that live check.
#
# Two things this intentionally does and does not do, decided after
# testing against this repo's actual files (not assumed):
#
# 1. Real syntax/parse errors (an unmatched brace, invalid QML) always
#    make qmllint exit non-zero AND tag the specific finding [syntax],
#    regardless of any configured warning level -- confirmed directly
#    against a deliberately corrupted copy of a real file in this repo.
#    This alone, with zero extra filtering, catches the "basic QML
#    parse/syntax failures" this issue asks for. A non-zero exit with NO
#    [syntax] tag anywhere in the output is treated as non-fatal instead
#    (see the loop below) -- confirmed live in CI that a total base-
#    module resolution failure (even plain QtQuick failing to resolve,
#    not just this repo's own Quickshell/Omarchy types) can produce
#    exactly that shape without any file actually failing to parse.
#
# 2. A broken *local relative* import (`import "SomeFile.js"`, a quoted
#    path) produces an unambiguous, distinctly-worded message ("File or
#    directory you are trying to import does not exist") that this
#    script treats as a hard failure even though qmllint itself only
#    warns by default. This message shape is unique to quoted relative
#    imports -- this repo's own Quickshell/Omarchy modules are always
#    referenced via dotted module imports (`import Quickshell.Io`,
#    `import qs.Commons`), confirmed never to produce this exact wording.
#
# What this deliberately does NOT fail the build on: a bare *sibling
# component reference* that no longer resolves (e.g. `WallpaperGlitch {
# ... }` after that file is renamed), or any Quickshell/Omarchy module
# that genuinely can't resolve here because the real desktop isn't
# installed (always true in CI; only sometimes true on a dev machine with
# quickshell installed, see QMLLINT_IMPORT_DIR below). Both surface
# through the identical "X was not found. Did you add all imports and
# dependencies?" wording qmllint gives an unresolvable Quickshell/Omarchy
# type -- there is no reliable way to tell those two apart from qmllint's
# own output alone without vendoring real Quickshell/Omarchy type stubs
# into this repo, which is a bigger, separate undertaking. That class of
# bug still only reliably surfaces via a real restart + journal check.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"

# The Qt5 `qmllint` that may be first on PATH (installed by qt5-declarative
# on this project's own dev machine, among others) silently exits 255 on
# every file -- confirmed directly, including against files with no
# problems at all -- so it is actively worse than not running a linter:
# it would either mark every file as broken, or (if anyone "fixed" that by
# ignoring its exit code) silently lint nothing. Only ever trust a binary
# that actually reports itself as qmllint 6.x.
find_qt6_qmllint() {
  local candidate ver
  for candidate in /usr/lib/qt6/bin/qmllint qmllint6 qmllint; do
    command -v "$candidate" >/dev/null 2>&1 || continue
    ver="$("$candidate" --version 2>/dev/null | grep -oE '[0-9]+' | head -1)"
    if [[ "$ver" == "6" ]]; then
      printf '%s' "$candidate"
      return 0
    fi
  done
  return 1
}

if ! qmllint_bin="$(find_qt6_qmllint)"; then
  printf 'note - no Qt 6 qmllint found locally (tried /usr/lib/qt6/bin/qmllint, qmllint6, qmllint), skipped (CI always installs qt6-declarative-dev-tools)\n' >&2
  exit 0
fi

import_args=()
# Only genuinely useful on a machine with quickshell itself installed
# (its own package drops Quickshell/*.qmltypes here) -- harmless and
# simply omitted otherwise, including in CI, where it never exists.
if [[ -d /usr/lib/qt6/qml ]]; then
  import_args=(-I /usr/lib/qt6/qml)
fi

mapfile -t qml_files < <(cd "$repo_dir" && find . -name '*.qml' -not -path './.git/*' | sed 's#^\./##' | sort)

pass=0
fail_count=0

for rel in "${qml_files[@]}"; do
  out="$(mktemp)"
  if "$qmllint_bin" "${import_args[@]}" "$repo_dir/$rel" >"$out" 2>&1; then
    qmllint_exit=0
  else
    qmllint_exit=$?
  fi

  if [[ "$qmllint_exit" -ne 0 ]]; then
    if grep -q '\[syntax\]' "$out"; then
      printf 'FAIL - %s: qmllint exited %d (parse/syntax error)\n' "$rel" "$qmllint_exit"
      cat "$out" >&2
      fail_count=$((fail_count + 1))
    else
      # Confirmed live (CI, first real run of this gate): a total base-
      # module resolution failure -- even plain QtQuick/Quickshell
      # failing to resolve AT ALL, not just this repo's own custom
      # types -- can make qmllint exit non-zero with no [syntax]-tagged
      # finding anywhere in its own output. That is a real, confirmed
      # difference from the narrower partial-unresolved-import case this
      # script already tolerates as non-fatal on its own (exit 0) --
      # same underlying gap (the real desktop/Quickshell isn't
      # installed here), just one that happens to escalate qmllint's own
      # exit code when NOTHING resolves instead of only SOME things.
      # Nothing here actually says this file's own QML failed to parse,
      # so it is not treated as one.
      printf 'note - %s: qmllint exited %d with no [syntax] finding -- import-resolution failure, not a real parse error (see this script own header)\n' "$rel" "$qmllint_exit" >&2
      pass=$((pass + 1))
    fi
  elif grep -q 'File or directory you are trying to import does not exist' "$out"; then
    printf 'FAIL - %s: broken local relative import\n' "$rel"
    grep 'File or directory you are trying to import does not exist' "$out" >&2
    fail_count=$((fail_count + 1))
  else
    printf 'ok   - %s\n' "$rel"
    pass=$((pass + 1))
  fi
  rm -f "$out"
done

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
