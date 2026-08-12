"""Collapsing a follow-up that was carried forward by hand into one thread.

    from lib.followup_threads import build
    threads, ticked = build(open_records, as_of, done=done_records)

There is no automatic carry-forward on the write side, so a still-open item gets
rewritten into today's note by hand — and reworded on the way, because the
person writing it knows more than they did yesterday. One task therefore appears
as three items:

    2026-08-08  Merge Flutter barcode PR #28 and ship TestFlight/store build
    2026-08-10  Merge Flutter barcode PR #28 and ship TestFlight IPA (`1.1.0+24` on `feature/…`)
    2026-08-11  Merge Flutter barcode PR #28 and ship TestFlight IPA (`1.1.0+25`)

Counted three times, and — worse — aged wrong: the report led with "1 day open"
because that is the newest restatement, when the task had been sitting for four.
The age is the whole reason to read this list, so getting it from the *first*
mention is the point of threading, not a side benefit of deduplication.

Exact matching cannot do this; the wording changes every day, and here even the
version number does. So the matching is deliberately layered, strongest signal
first, with two hard preconditions that hold for every merge:

- **same repo** — an unattributed item never merges into an attributed one
- **different notes** — two items written side by side in one day's section are
  two tasks by construction, whatever they look like

That second one is doing more work than it appears to. Two `Device retest: …`
lines in the same note are a real pair of distinct tests; the same clause on two
different days is one test restated. Without the guard, signal 4 below cannot
tell those apart, and a wrong merge *hides a task*, which is the one failure this
whole skill exists to prevent.

Read-only. Stdlib only.
"""

import re

from lib.followups import display
from lib.landed import refs

# A version, in any of the shapes these items use: `1.1.0`, `1.1.0+24`, `v0.27.0`.
# Collapsed to one token because a carried-forward item is *typically* rewritten
# for exactly this reason — the build number moved — and two items that differ
# only there are the same task on consecutive days.
VERSION_RE = re.compile(r'\bv?\d+\.\d+(?:\.\d+)?(?:[+-]\d+)?\b')
VERSION_TOKEN = " versiontoken "

WIKILINK_RE = re.compile(r'\[\[([^\]|]+?)(?:\|[^\]]*)?\]\]')
MDLINK_RE = re.compile(r'\[([^\]]*)\]\([^)]*\)')

# Small and closed on purpose. A large stopword list starts deciding that two
# items are similar because everything distinguishing them was filtered out.
STOPWORDS = frozenset("""
a an the and or but of to for on in into with without at by from as is are was
were be been being it its this that these those then than so if when while
""".split())

JACCARD_FLOOR = 0.6
# Jaccard punishes a restatement for saying *more*, and these restatements
# routinely do — yesterday's item grows a parenthetical explaining what it is
# now blocked on. Containment is the shape that actually describes them: nearly
# everything the shorter one says, the longer one says too. The floor on the
# shorter side is what stops a three-word item from being swallowed by any long
# item that happens to contain its words.
OVERLAP_FLOOR = 0.75
OVERLAP_MIN_TOKENS = 4
LEAD_MIN_TOKENS = 2
LEAD_MAX_TOKENS = 6


def clean(text):
    """Item text with the markup and the moving parts taken out, `:` preserved.

    `:` survives because the leading clause before it is signal 4 — it is how
    these items are actually written ("Device retest: …", "Stakeholder: …"), and
    it is the most stable part of an item that gets reworded every day.
    """
    s = display(text).lower()
    s = WIKILINK_RE.sub(r'\1', s)
    s = MDLINK_RE.sub(r'\1', s)
    s = s.replace("`", " ").replace("*", " ")
    return VERSION_RE.sub(VERSION_TOKEN, s)


def tokens(text):
    """Content tokens: alphanumeric runs, stopwords dropped, order preserved."""
    return [t for t in re.split(r'[^a-z0-9]+', text) if t and t not in STOPWORDS]


def norm(text):
    return " ".join(tokens(clean(text)))


def lead(text):
    """The leading clause's tokens, or None when there is no usable one.

    Bounded at both ends: one token is not a label (every item starting with
    "merge" would collapse), and more than six is a whole sentence rather than
    the heading of one.
    """
    head, sep, _ = clean(text).partition(":")
    if not sep:
        return None
    head_tokens = tokens(head)
    if LEAD_MIN_TOKENS <= len(head_tokens) <= LEAD_MAX_TOKENS:
        return tuple(head_tokens)
    return None


def jaccard(a, b):
    a, b = set(a), set(b)
    if not a or not b:
        return 0.0
    return len(a & b) / len(a | b)


def overlap(a, b):
    """How much of the shorter item the longer one also says."""
    a, b = set(a), set(b)
    if not a or not b:
        return 0.0
    return len(a & b) / min(len(a), len(b))


def same_thread(older, newer):
    """Is `newer` a restatement of `older`? (str, str) -> bool

    Signals in order of how much they are trusted. Each one alone is sufficient;
    none of them is applied without the caller's same-repo and different-note
    preconditions already holding.
    """
    # 1. A shared hard reference. Two items naming PR #28 are about PR #28 —
    #    this is the signal that survives a complete rewording, and it is the
    #    same extractor the landed check uses, so an item that can be threaded
    #    on a ref can also be checked on it.
    if set(refs(older)) & set(refs(newer)):
        return True

    a, b = clean(older), clean(newer)
    ta, tb = tokens(a), tokens(b)

    # 2. The plain restatement: identical once the version number is collapsed.
    if ta and ta == tb:
        return True

    # 3. Mostly the same words, opening the same way. The first-token
    #    requirement is what keeps two different tasks in one subsystem apart —
    #    they share vocabulary, they do not share the verb.
    if ta and tb and ta[0] == tb[0]:
        if jaccard(ta, tb) >= JACCARD_FLOOR:
            return True
        if (min(len(set(ta)), len(set(tb))) >= OVERLAP_MIN_TOKENS
                and overlap(ta, tb) >= OVERLAP_FLOOR):
            return True

    # 4. The same leading clause. Weakest, and the only one that can be right
    #    about the label while wrong about the work — which is exactly what the
    #    different-note precondition is protecting.
    la, lb = lead(older), lead(newer)
    return la is not None and la == lb


def _new_thread(record):
    thread = dict(record)
    thread["dates"] = [record["date"]]
    thread["restated"] = 0
    thread["members"] = [record]
    return thread


def _absorb(thread, record, as_of):
    """Fold a newer restatement in: newest wording, oldest age."""
    first = thread["dates"][0]
    thread["dates"].append(record["date"])
    thread["members"].append(record)
    thread["item"] = record["item"]          # the newest wording is the current one
    thread["context"] = record.get("context")
    thread["date"] = first                   # ...but the age is from the first
    thread["age"] = (as_of - first).days
    thread["restated"] = len(thread["dates"]) - 1
    # A flag is a property of the task, not of one day's phrasing of it: an item
    # that said "blocked on the API key" on Monday is still blocked on Tuesday
    # even if Tuesday's rewrite dropped the word. Keep the first one seen.
    thread["flag"] = thread.get("flag") or record.get("flag")


def _match(threads, record):
    """The earliest thread `record` restates, or None.

    Compared against each thread's newest member only. Matching against every
    member would let a thread drift: A matches B, B matches C, and C ends up in a
    thread with an A it has nothing in common with.
    """
    for thread in threads:
        if thread.get("repo") != record.get("repo"):
            continue
        if thread["dates"][-1] == record["date"]:
            continue  # same note: two tasks written side by side
        if same_thread(thread["item"], record["item"]):
            return thread
    return None


def build(records, as_of, done=()):
    """(threads, ticked_later) — carried-forward items collapsed.

    `records` are the open items, each already stamped with `repo` (see
    lib.followups.annotate). `done` are the `- [x]` items from the same notes.

    A thread is a superset of a record — same `date`, `age`, `item`, `flag`,
    `repo` keys — so a caller that does not care about threading can print one
    exactly as it prints the other. `date` is the first mention and `age` is
    measured from it; `item` is the newest wording, because that is the one that
    reflects what the task is now.

    `ticked_later` is the threads dropped because a later note ticks them off.
    That is the only thing this function removes, and it is returned rather than
    swallowed so the caller can say how many and offer to show them.
    """
    threads = []
    for record in sorted(records, key=lambda r: r["date"]):
        match = _match(threads, record)
        if match is None:
            threads.append(_new_thread(record))
        else:
            _absorb(match, record, as_of)

    # An item ticked off in a *later* note closes the thread, even though an
    # older note still shows it unchecked. Without this the report reopens work
    # the vault already records as finished, purely because the older wording was
    # never gone back and edited — which nobody does, and nobody should have to.
    open_threads, ticked = [], []
    for thread in threads:
        closer = _closed_by(thread, done)
        if closer is None:
            open_threads.append(thread)
        else:
            thread["closed_by"] = closer
            ticked.append(thread)
    return open_threads, ticked


def _closed_by(thread, done):
    last = thread["dates"][-1]
    for record in sorted(done, key=lambda r: r["date"]):
        if record["date"] <= last:
            continue  # same note or earlier: a different item, not this one done
        if record.get("repo") != thread.get("repo"):
            continue
        if same_thread(thread["item"], record["item"]):
            return record["date"]
    return None


def as_threads(records):
    """Records in thread shape, with nothing collapsed — the `--no-threads` path.

    So the report has exactly one code path to print, and turning threading off
    cannot quietly change anything else about the output.
    """
    return [_new_thread(record) for record in sorted(records, key=lambda r: r["date"])]
