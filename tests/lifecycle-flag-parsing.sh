#!/usr/bin/env bash
# Issue #90: update.sh and uninstall.sh used to compare "$1" against one
# or two exact strings and let everything else -- --help, a typo like
# --dryrun, --acknowledge-interrupted -- fall through to the real
# (irreversible, for uninstall) operation, and update.sh then called
# install.sh with no arguments at all. These cover, for all three
# lifecycle scripts, that an unknown option is a hard error that touches
# nothing, that --help is safe, and that the flags install.sh honors
# survive the update.sh -> install.sh handoff.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
fake_bin="$script_dir/fixtures/fake-bin"

command -v jq >/dev/null 2>&1 || {
  printf 'lifecycle-flag-parsing: jq is required (command "jq" not found)\n' >&2
  exit 1
}

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

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

git config --global user.email >/dev/null 2>&1 || git config --global user.email "test@example.invalid"
git config --global user.name >/dev/null 2>&1 || git config --global user.name "Test"

# run_script <script> <args...> -- real script, isolated empty $HOME, fake
# omarchy on PATH; sets out/status and leaves $home populated only if the
# script wrote anything.
run_script() {
  local script="$1"; shift
  home="$(mktemp -d "$work/home.XXXX")"
  if out="$( cd "$repo_dir" && HOME="$home" PATH="$fake_bin:$PATH" "./$script" "$@" 2>&1 )"; then
    status=0
  else
    status=$?
  fi
}

head_before="$(git -C "$repo_dir" rev-parse HEAD)"

for script in install.sh update.sh uninstall.sh; do
  run_script "$script" --dryrun
  check "$script: a typo'd flag exits non-zero" "$([[ "$status" -ne 0 ]] && echo yes)" "yes"
  check "$script: a typo'd flag is named as unknown" "$(printf '%s' "$out" | grep -c 'unknown option: --dryrun')" "1"
  check "$script: a typo'd flag touched nothing under \$HOME" "$(find "$home" -mindepth 1 | wc -l | tr -d ' ')" "0"

  run_script "$script" --dry-run --bogus
  check "$script: an unknown flag after a valid one is still rejected" "$([[ "$status" -ne 0 ]] && echo yes)" "yes"
done

for script in install.sh update.sh uninstall.sh; do
  run_script "$script" --help
  check "$script: --help exits 0" "$status" "0"
  check "$script: --help prints usage" "$(printf '%s' "$out" | grep -c '^Usage:')" "1"
  check "$script: --help mentions --acknowledge-interrupted" "$([[ "$(printf '%s' "$out" | grep -c -- '--acknowledge-interrupted')" -ge 1 ]] && echo yes)" "yes"
  check "$script: --help touched nothing under \$HOME" "$(find "$home" -mindepth 1 | wc -l | tr -d ' ')" "0"
done

run_script update.sh --dry-run --check-json
check "update.sh: --dry-run and --check-json together are rejected" "$([[ "$status" -ne 0 ]] && echo yes)" "yes"

check "the repo checkout itself was never moved by a rejected update.sh" \
  "$(git -C "$repo_dir" rev-parse HEAD)" "$head_before"

# --- the update.sh -> install.sh handoff ---------------------------------
# A fake upstream + checkout whose install.sh just records its argv --
# update.sh's own flag handling is what's under test, not install.sh's
# (covered by install-lifecycle.sh / lifecycle-journal-recovery.sh).
upstream="$work/upstream.git"
checkout="$work/checkout"
git init --bare -q -b master "$upstream"
git clone -q "$upstream" "$checkout"
printf '#!/usr/bin/env bash\nprintf "install args: [%%s]\\n" "$*"\n' > "$checkout/install.sh"
chmod +x "$checkout/install.sh"
cp "$repo_dir/update.sh" "$checkout/update.sh"
chmod +x "$checkout/update.sh"
mkdir -p "$checkout/lib"
cp "$repo_dir/lib/acquire-lifecycle-lock.sh" "$checkout/lib/acquire-lifecycle-lock.sh"
git -C "$checkout" add -A
git -C "$checkout" commit -q -m initial
git -C "$checkout" push -q origin master 2>/dev/null || git -C "$checkout" push -q origin HEAD:master

fake_home="$work/handoff-home"
mkdir -p "$fake_home"
run_update() { ( cd "$checkout" && HOME="$fake_home" ./update.sh "$@" ) 2>&1; }

check "handoff: no flags -> install.sh gets no arguments" \
  "$(run_update | grep 'install args:')" "install args: []"
check "handoff: --acknowledge-interrupted reaches install.sh" \
  "$(run_update --acknowledge-interrupted | grep 'install args:')" "install args: [--acknowledge-interrupted]"
check "handoff: --with-launcher-keybind reaches install.sh" \
  "$(run_update --with-launcher-keybind | grep 'install args:')" "install args: [--with-launcher-keybind]"
check "handoff: several flags reach install.sh in order" \
  "$(run_update --with-launcher-keybind --acknowledge-interrupted | grep 'install args:')" \
  "install args: [--with-launcher-keybind --acknowledge-interrupted]"
check "handoff: --dry-run forwards --dry-run and the other flags" \
  "$(run_update --dry-run --with-launcher-keybind | grep 'install args:')" "install args: [--dry-run --with-launcher-keybind]"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
