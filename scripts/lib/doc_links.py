#!/usr/bin/env python3
"""Check that every in-document anchor link resolves to a heading.

`[`rules/`](#the-rules-live-somewhere-else)` pointed at a heading that does not
exist in README.md — a link that silently does nothing, in the paragraph
explaining why the engine ships no rules of its own.

Only same-document `#anchor` links are checked. Cross-file and external links
are somebody else's uptime; this is about a claim the document makes about
itself. GitHub's slug rules: lowercase, spaces to hyphens, drop anything that
is not alphanumeric, hyphen or underscore.

Usage: doc_links.py FILE [FILE ...]   -> lines, or "clean". Exit 1 if any.
"""
import re, sys, pathlib

def slug(text):
    text = re.sub(r'`|\*|_', '', text).strip().lower()
    text = re.sub(r'[^\w\s-]', '', text)
    return re.sub(r'\s+', '-', text)

bad = []
for path in sys.argv[1:]:
    p = pathlib.Path(path)
    lines = p.read_text(encoding="utf-8").splitlines()
    anchors, fence = set(), False
    for line in lines:
        if line.lstrip().startswith("```"):
            fence = not fence
            continue
        if not fence and line.startswith("#"):
            anchors.add(slug(line.lstrip("#")))
    fence = False
    for i, line in enumerate(lines, 1):
        if line.lstrip().startswith("```"):
            fence = not fence
            continue
        if fence:
            continue
        for target in re.findall(r'\]\(#([A-Za-z0-9_-]+)\)', line):
            if target not in anchors:
                bad.append("%s:%d: link to #%s, which is not a heading here" % (path, i, target))

print("\n".join(bad) if bad else "clean")
sys.exit(1 if bad else 0)
