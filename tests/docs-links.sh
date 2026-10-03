#!/usr/bin/env bash
# Documentation link check. The README, docs/ and dev/ README are a
# three-layer manual that links between itself heavily; a moved or renamed
# file silently breaks those links on GitHub. This resolves every relative
# markdown link and image src in those files (file must exist, and a
# `#fragment` must match a heading in the target) and fails on any that
# does not. External http(s) links are not fetched.
set -Eeuo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"

python3 - "$repo_dir" <<'PY'
import os
import re
import sys

root = sys.argv[1]
files = ["README.md", "dev/README.md", "AGENTS.md", "COMPATIBILITY.md"]
files += sorted("docs/" + f for f in os.listdir(os.path.join(root, "docs")) if f.endswith(".md"))

link = re.compile(r"!?\[[^\]]*\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)|<img[^>]+src=\"([^\"]+)\"|<a[^>]+href=\"([^\"]+)\"")


def slug(heading):
    s = heading.strip().lower()
    s = re.sub(r"[^\w\s-]", "", s)
    return re.sub(r"\s", "-", s)


def anchors(path):
    out = set()
    in_code = False
    for line in open(path, encoding="utf-8"):
        if line.startswith("```"):
            in_code = not in_code
        elif not in_code and re.match(r"^#{1,6}\s", line):
            out.add(slug(re.sub(r"^#{1,6}\s+", "", line)))
    return out


bad = 0
checked = 0
for f in files:
    base = os.path.dirname(os.path.join(root, f))
    in_code = False
    for n, line in enumerate(open(os.path.join(root, f), encoding="utf-8"), 1):
        if line.startswith("```"):
            in_code = not in_code
            continue
        if in_code:
            continue
        for m in link.finditer(line):
            target = next(g for g in m.groups() if g)
            if re.match(r"^[a-z][a-z0-9+.-]*:", target):
                continue
            path, _, frag = target.partition("#")
            dest = os.path.normpath(os.path.join(base, path)) if path else os.path.join(root, f)
            checked += 1
            if not os.path.exists(dest):
                print(f"FAIL {f}:{n} -> {target} (no such file)")
                bad += 1
            elif frag and dest.endswith(".md") and frag not in anchors(dest):
                print(f"FAIL {f}:{n} -> {target} (no such heading)")
                bad += 1

print(f"{checked - bad} passed, {bad} failed")
sys.exit(1 if bad else 0)
PY
