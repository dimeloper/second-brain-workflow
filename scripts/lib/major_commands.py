#!/usr/bin/env python3
"""Check that every command a changelog **Major** entry names actually exists.

A Major entry is the one place in this repo whose whole job is to tell an
adopter what to *do*, and `upgrade.sh` prints those sections verbatim — so a
command named there is handed to every future reader upgrading past that
release. v0.20.0's entry named `make render`, which did not exist; every other
reference in the repo was `./scripts/render.py <repo>`.

`test-release-consistency.sh` already covers VERSION / changelog / ENGINE_REF.
Nothing covered the part a reader is asked to type.

Checks `make <target>` against the Makefile's own .PHONY list and target
definitions, and `./scripts/<name>` against the filesystem. Anything else is
left alone: this is a spelling check on commands, not a shell parser.

Usage: major_commands.py   -> lines, or "clean". Exit 1 if any.
"""
import re, sys, pathlib

root = pathlib.Path(__file__).resolve().parent.parent.parent
changelog = (root / "CHANGELOG.md").read_text(encoding="utf-8")
makefile = (root / "Makefile").read_text(encoding="utf-8")

targets = set(re.findall(r'^([a-z][a-z0-9-]*):', makefile, re.M))

# Every ### Major block, to the next heading of the same or higher level.
blocks = re.findall(r'^### Major\n(.*?)(?=^#{2,3} )', changelog, re.M | re.S)

bad = []
for block in blocks:
    for cmd in set(re.findall(r'`make ([a-z][a-z0-9-]*)', block)):
        if cmd not in targets:
            bad.append("CHANGELOG.md: a Major entry names `make %s`, "
                       "which is not a Makefile target" % cmd)
    for script in set(re.findall(r'`\./(scripts/[A-Za-z0-9_.-]+)', block)):
        if not (root / script).exists():
            bad.append("CHANGELOG.md: a Major entry names ./%s, which does not exist" % script)

print("\n".join(sorted(set(bad))) if bad else "clean")
sys.exit(1 if bad else 0)
