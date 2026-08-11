#!/usr/bin/env python3
"""Find a heading that states a count over a list of a different length.

"Three rules worth knowing:" followed by five bullets. Prose and list drift
apart because one grows and the other is a sentence nobody re-reads — this has
now happened four times across two files, including one heading that said
"Three times now" over four entries in a list *about* wrong counts.

Proofreading is not the fix; the fix is that a claim about a list is checkable.
A heading ending in `:` whose text contains a count word or small number is
compared against the bullets that immediately follow it, at the indent of the
first bullet, so a nested list is measured against its own heading. Fenced code
blocks are skipped: sample output is a transcript, not a claim about the
document.

Usage: stated_counts.py FILE [FILE ...]   -> lines, or "clean". Exit 1 if any.
"""
import re, sys, pathlib
WORDS = {"two":2,"three":3,"four":4,"five":5,"six":6,"seven":7,"eight":8,"nine":9,"ten":10}
TOKEN = re.compile(r'\b(two|three|four|five|six|seven|eight|nine|ten|\d{1,2})\b', re.I)
def check(path):
    lines = pathlib.Path(path).read_text(encoding="utf-8").splitlines()
    out, fence = [], False
    for i, line in enumerate(lines):
        if line.lstrip().startswith("```"):
            fence = not fence; continue
        if fence: continue
        s = line.strip()
        if not s.endswith(":"): continue
        m = TOKEN.search(s)
        if not m: continue
        w = m.group(1).lower()
        n = WORDS.get(w) or (int(w) if w.isdigit() else None)
        if n is None or not (1 < n <= 20): continue
        j = i + 1
        while j < len(lines) and not lines[j].strip(): j += 1
        # Bullets are counted at the indent of the first one, so a nested list
        # under a parent item is measured against its own heading rather than
        # collapsing into the outer level.
        bullets, indent = 0, None
        while j < len(lines):
            t = lines[j]
            m2 = re.match(r'^(\s*)(?:[-*] |\d+\. )', t)
            if m2:
                if indent is None: indent = len(m2.group(1))
                if len(m2.group(1)) == indent: bullets += 1
            elif t.strip() == "" or (indent is not None and t.startswith(" " * (indent + 1))): pass
            else: break
            j += 1
        if bullets and bullets != n:
            out.append(f"{path}:{i+1}: claims {n}, list has {bullets} — {s[:64]}")
    return out
bad = []
for p in sys.argv[1:]:
    bad += check(p)
print("\n".join(bad) if bad else "clean")
sys.exit(1 if bad else 0)
