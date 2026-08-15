#!/usr/bin/env python3
"""Find a heading that states a count over a list of a different length.

"Three rules worth knowing:" followed by five bullets. Prose and list drift
apart because one grows and the other is a sentence nobody re-reads — this has
now happened four times across two files, including one heading that said
"Three times now" over four entries in a list *about* wrong counts.

Proofreading is not the fix; the fix is that a claim about a list is checkable.
A heading ending in `:` whose text contains a count word or small number is
compared against the bullets that immediately follow it, at the indent of the
first bullet, so a nested list is measured against its own heading.

Fenced blocks are checked too, each as its own region — a heading inside a fence
is measured against the bullets inside that same fence, and the scan stops at
the fence boundary rather than running into the prose after it.

This used to skip fences entirely, on the reasoning that a transcript is a
record of what a tool printed rather than a claim the document makes. That is
true of the transcript, and false of a count *inside* it: `Adopted and scoped to
this repo: 5` above two entries is a claim about its own list, wrong in exactly
the way this file exists to catch, and the shape v0.4.2 recorded — a printed
example beside real behaviour, where the example was what misled a reader. It
was fixed by hand, because skipping the fence meant nothing else would.

What this still does NOT do, so its green is not read as broader than it is:
compare a sample against the tool's real output. A fenced sample whose counts
agree with its own bullets can still be a faithful record of a version that no
longer runs.

Usage: stated_counts.py FILE [FILE ...]   -> lines, or "clean". Exit 1 if any.
"""
import re, sys, pathlib
WORDS = {"two":2,"three":3,"four":4,"five":5,"six":6,"seven":7,"eight":8,"nine":9,"ten":10}
TOKEN = re.compile(r'\b(two|three|four|five|six|seven|eight|nine|ten|\d{1,2})\b', re.I)
TRAILING = re.compile(r':[ \t]*(\d{1,2})[ \t]*$')  # "Adopted …: 2" — tool output
ORDERED = re.compile(r'^\d{1,2}\.[ \t]+')          # a step's own list marker
DELIM = -1  # a ``` line: in no region, and a hard stop for any scan


def regions(lines):
    """Which fenced block each line belongs to — None outside, an id inside.

    Counting a region rather than a boolean is what lets a heading inside a
    fence be measured against that fence's own bullets: the forward scan stops
    where the region changes, so it can neither run out of a sample into the
    prose below it nor pull a later block's list into an earlier claim.
    """
    ids, cur, nxt = [], None, 0
    for line in lines:
        if line.lstrip().startswith("```"):
            if cur is None:
                cur, nxt = nxt, nxt + 1
            else:
                cur = None
            ids.append(DELIM)
            continue
        ids.append(cur)
    return ids


def stated(s):
    """The count a line claims over the list below it, or None.

    Two shapes, because prose and tool output put the number on opposite sides
    of the colon. Prose introduces a list — "Three rules worth knowing:" — while
    a tool labels one it just printed — "Adopted and scoped to this repo: 2".
    Only the first was ever recognised, which is the other half of why the
    `skills-for` sample drifted unchecked: even unfenced, its counts were not in
    a shape this looked at.

    A trailing count may be 0 ("…: 0" above two entries is wrong the same way);
    a prose count may not, since "one thing to note:" is a turn of phrase far
    more often than it is a claim about a list.
    """
    m = TRAILING.search(s)
    if m:
        n = int(m.group(1))
        return n if 0 <= n <= 20 else None
    if not s.endswith(":"): return None
    # "4. **Auth from that repo's `.env`**, not an interactive login:" claims
    # nothing — the 4 is the step's own list marker. Strip it before looking,
    # or every numbered step ending in a colon reads as a count of whatever
    # follows it.
    m = TOKEN.search(ORDERED.sub("", s))
    if not m: return None
    w = m.group(1).lower()
    n = WORDS.get(w) or (int(w) if w.isdigit() else None)
    return n if n is not None and 1 < n <= 20 else None


def check(path):
    lines = pathlib.Path(path).read_text(encoding="utf-8").splitlines()
    region = regions(lines)
    out = []
    for i, line in enumerate(lines):
        if region[i] == DELIM: continue
        # Only a heading *inside* a fence is bounded by it. Outside one, a
        # fenced block indented under a bullet is that bullet's continuation —
        # a `git clone` example between two options — and stopping there would
        # count the first option and miss the second.
        bounded = region[i] is not None
        s = line.strip()
        n = stated(s)
        if n is None: continue
        j = i + 1
        while j < len(lines) and not (bounded and region[j] != region[i]) \
                and not lines[j].strip(): j += 1
        # Bullets are counted at the indent of the first one, so a nested list
        # under a parent item is measured against its own heading rather than
        # collapsing into the outer level.
        bullets, indent = 0, None
        while j < len(lines):
            if bounded and region[j] != region[i]: break
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
