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

# The queries are Dataview, so the numbers sit inside a `length(repos) >= N`
# comparison next to the maturity they gate.
BAR_RE = re.compile(
    r'"?(?P<maturity>idea|trialing)"?[^\n]*?length\(\s*repos\s*\)\s*>=\s*(?P<n>\d+)',
    re.IGNORECASE,
)


def bars(vault):
    """(trialing_bar, enforced_bar) — the repo counts that clear each rung.

    `idea` gates promotion *to* trialing, `trialing` gates promotion *to*
    enforced, so the maturity named in the query is the rung being left, not the
    one being reached. Naming the return value after the rung reached is
    deliberate: every caller asks "what does this need to become X".
    """
    path = vault / "00-maps" / "promotion-candidates.md"
    if not path.is_file():
        sys.exit(
            "Cannot read the promotion bars: no %s\n"
            "The vault is the authority on its own promotion rules, and a "
            "hardcoded fallback here would report notes as ready against a bar "
            "nobody set." % path
        )

    found = {}
    for m in BAR_RE.finditer(path.read_text(encoding="utf-8")):
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
            "Cannot read the promotion bars from %s: no `length(repos) >= N` "
            "found for %s. Reworded past recognition, or the queries changed — "
            "either way this must not guess."
            % (path, " and ".join(missing))
        )
    return found["idea"], found["trialing"]
