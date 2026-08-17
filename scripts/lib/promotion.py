#!/usr/bin/env python3
"""The vault's own idea->trialing->enforced repo-count bars.

Read from `00-maps/promotion-candidates.md` rather than hardcoded, because the
vault is the authority on its own promotion rules and a second copy of the
numbers here would be a copy that can disagree with the queries the user actually
reads in Obsidian.

An unparseable file is a hard error, never a default. A promotion report computed
against a guessed bar is worse than no report: it looks like a measurement and is
an assumption, and it would name specific notes as ready when they are not.

`check-lineage.py` carries its own `enforced_threshold` for the same file;
tests/test-practices-for.sh asserts the two agree, which is cheaper than
refactoring a tested file and catches the drift that matters.
"""

import re
import sys

# The queries are Dataview, so the numbers sit inside a `length(<field>) >= N`
# comparison next to the maturity they gate.
#
# Two fields, because a note is promoted on the evidence it actually claims.
# `repos:` answers "does this hold outside the codebase that produced it", which
# is the right question for a rule carrying a real `applies-to` glob and the
# wrong one for a process rule about how you work — that can only ever be
# re-encountered in the same place, so a repo-only bar made it unpromotable
# however often it was applied. `applications:` counts deliberate
# re-applications instead. Same numbers, different denominator.
def _bar_re(field):
    return re.compile(
        r'"?(?P<maturity>idea|trialing)"?[^\n]*?length\(\s*'
        + field
        + r'\s*\)\s*>=\s*(?P<n>\d+)',
        re.IGNORECASE,
    )


BAR_RE = _bar_re("repos")
APPLICATION_BAR_RE = _bar_re("applications")


def bars(vault):
    """(trialing_bar, enforced_bar) — the repo counts that clear each rung.

    `idea` gates promotion *to* trialing, `trialing` gates promotion *to*
    enforced, so the maturity named in the query is the rung being left, not the
    one being reached. Naming the return value after the rung reached is
    deliberate: every caller asks "what does this need to become X".
    """
    return _read_bars(vault, BAR_RE, "repos")


def application_bars(vault, required=True):
    """The same two rungs, counted in `applications:` for process notes.

    Separate function rather than a flag on `bars`: the caller has to know
    which kind of note it is holding to pick a bar at all, so making that
    choice explicit at the call site is the point. A note with
    `applies-to: ""` takes these.

    `required=False` returns None when the vault declares no applications bar,
    and that is the **opt-in switch for the whole two-bar model**. A vault that
    has not declared one keeps the single repo bar it was built under: its
    index renders the same bytes and its audit stays exactly as strict.

    Silently applying the new model to such a vault would be worse than a hard
    error. Process notes would move out of "maturity above its evidence" and
    into "uncounted", so an audit that used to flag an `enforced` note on one
    repo would stop — a check getting quietly *weaker* on upgrade, in a repo
    whose owner never asked for a different model and would have no reason to
    look. The vault is the authority on its own promotion rules; not declaring
    a bar is an answer.
    """
    if not required and not _declares(vault, APPLICATION_BAR_RE):
        return None
    return _read_bars(vault, APPLICATION_BAR_RE, "applications")


def _declares(vault, pattern):
    path = vault / "00-maps" / "promotion-candidates.md"
    if not path.is_file():
        return False
    return bool(pattern.search(path.read_text(encoding="utf-8")))


def _read_bars(vault, pattern, field):
    path = vault / "00-maps" / "promotion-candidates.md"
    if not path.is_file():
        sys.exit(
            "Cannot read the promotion bars: no %s\n"
            "The vault is the authority on its own promotion rules, and a "
            "hardcoded fallback here would report notes as ready against a bar "
            "nobody set." % path
        )

    found = {}
    for m in pattern.finditer(path.read_text(encoding="utf-8")):
        rung = m.group("maturity").lower()
        n = int(m.group("n"))
        if rung in found and found[rung] != n:
            sys.exit(
                "Ambiguous promotion bar for '%s' in %s: found both %d and %d. "
                "Fix the file rather than letting this pick one."
                % (rung, path, found[rung], n)
            )
        found[rung] = n

    missing = [r for r in ("idea", "trialing") if r not in found]
    if missing:
        sys.exit(
            "Cannot read the promotion bars from %s: no `length(%s) >= N` "
            "found for %s. Reworded past recognition, or the queries changed — "
            "either way this must not guess."
            % (path, field, " and ".join(missing))
        )
    return found["idea"], found["trialing"]
