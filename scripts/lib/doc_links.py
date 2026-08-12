#!/usr/bin/env python3
"""Check that every anchor link resolves to a heading.

`[`rules/`](#the-rules-live-somewhere-else)` pointed at a heading that does not
exist in README.md — a link that silently does nothing, in the paragraph
explaining why the engine ships no rules of its own.

Two kinds are checked:

- **Same-document** `#anchor` — the original case.
- **Cross-file** `some/path.md#anchor`, resolved relative to the file holding
  the link. This was added when the README was cut down to a pitch and its
  deep links became `docs/REFERENCE.md#…`: the whole "why this doesn't rot"
  section, which carries the trust argument, now resolves into another file,
  and a heading renamed there would break the pitch silently. Manual
  repointing is not a check.

What this deliberately does NOT cover, so its green is not read as broader
than it is:

- **External links.** Somebody else's uptime, not a claim this repo makes
  about itself.
- **A cross-file path that does not resolve.** Only the anchor is checked, and
  only once the file is found. A link naming a file that is not there is a
  real defect of a different shape — worth catching, not caught here — so a
  green run is not evidence that every linked path exists.

GitHub's slug rules: lowercase, spaces to hyphens, drop anything that is not
alphanumeric, hyphen or underscore.

Usage: doc_links.py FILE [FILE ...]   -> lines, or "clean". Exit 1 if any.
"""
import re, sys, pathlib

SAME_FILE = re.compile(r'\]\(#([A-Za-z0-9_-]+)\)')
CROSS_FILE = re.compile(r'\]\(([^)\s#]+)#([A-Za-z0-9_-]+)\)')
EXTERNAL = ("http://", "https://", "mailto:", "//")


def slug(text):
    text = re.sub(r'`|\*|_', '', text).strip().lower()
    text = re.sub(r'[^\w\s-]', '', text)
    return re.sub(r'\s+', '-', text)


_anchor_cache = {}


def anchors_of(path):
    """Every heading slug in one markdown file, or None if it cannot be read."""
    key = str(path)
    if key not in _anchor_cache:
        try:
            lines = path.read_text(encoding="utf-8").splitlines()
        except OSError:
            _anchor_cache[key] = None
            return None
        found, fence = set(), False
        for line in lines:
            if line.lstrip().startswith("```"):
                fence = not fence
                continue
            if not fence and line.startswith("#"):
                found.add(slug(line.lstrip("#")))
        _anchor_cache[key] = found
    return _anchor_cache[key]


bad = []
for arg in sys.argv[1:]:
    p = pathlib.Path(arg)
    own = anchors_of(p)
    if own is None:
        bad.append("%s: cannot be read" % arg)
        continue
    fence = False
    for i, line in enumerate(p.read_text(encoding="utf-8").splitlines(), 1):
        if line.lstrip().startswith("```"):
            fence = not fence
            continue
        if fence:
            continue
        for target in SAME_FILE.findall(line):
            if target not in own:
                bad.append("%s:%d: link to #%s, which is not a heading here"
                           % (arg, i, target))
        for rel, target in CROSS_FILE.findall(line):
            if rel.startswith(EXTERNAL):
                continue
            dest = (p.parent / rel).resolve()
            # An unresolvable path is out of scope — see the module docstring.
            if not dest.is_file():
                continue
            there = anchors_of(dest)
            if there is not None and target not in there:
                bad.append("%s:%d: link to %s#%s, which is not a heading in %s"
                           % (arg, i, rel, target, rel))

print("\n".join(bad) if bad else "clean")
sys.exit(1 if bad else 0)
