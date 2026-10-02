#!/usr/bin/env python3
"""Report any `anchors.<prop>` set twice inside one QML object block.

QML does not error on a duplicate property assignment -- it warns and drops
the type, so the whole plugin fails to load and silently falls back. That
happened live in ruixen.shelf: a bulk anchor edit gave `list` two topMargin
lines, the journal said only "Property value set multiple times", and both
`omarchy plugin validate` and every grep-based test still passed, because it
is a compile-time diagnostic neither of them runs.

Prints one line per duplicate and exits 1 if any were found.
"""
import re
import sys

BLOCK_OPEN = re.compile(r"^\s*[A-Za-z][A-Za-z0-9]*\s*\{\s*$")
CLOSE = re.compile(r"^\s*\}\s*$")
ANCHOR = re.compile(r"^\s*anchors\.([A-Za-z]+)")
NESTED = re.compile(r":\s*\{\s*$")


def check(path):
    findings = []
    depth = 0
    seen = {}
    for lineno, line in enumerate(open(path, encoding="utf-8"), 1):
        if BLOCK_OPEN.match(line) or NESTED.search(line):
            depth += 1
            seen[depth] = set()
            continue
        if CLOSE.match(line):
            if depth > 0:
                depth -= 1
            continue
        m = ANCHOR.match(line)
        if depth > 0 and m:
            prop = m.group(1)
            if prop in seen.get(depth, ()):
                findings.append(f"{path}:{lineno}: anchors.{prop} set twice")
            seen.setdefault(depth, set()).add(prop)
    return findings


if __name__ == "__main__":
    all_findings = [f for path in sys.argv[1:] for f in check(path)]
    for f in all_findings:
        print(f)
    sys.exit(1 if all_findings else 0)
