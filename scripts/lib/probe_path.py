#!/usr/bin/env python3
"""Choosing a rule to prove context injection with, and a path its glob matches.

Extracted from `verify-claude-load.sh`, where it lived as an `awk` one-liner
that took the *first* scoped rule's *first* glob and built `probe` + the glob's
basename with a leading `*` stripped. That is correct for `**/*.tsx` and
silently wrong for any glob whose basename is literal: `**/lib/auth.ts` became
`probeauth.ts`, which matches nothing.

The check then reported `FAIL — the rule never loaded`, which is
indistinguishable, to whoever reads it, from path scoping actually being broken
— the one conclusion that check exists to rule out. Nothing in the script had
changed. The *rule set* had: a rule was split, another added, a different one
sorted first, and a probe that had passed on 2026-08-02 began failing on a
machine where everything was fine.

So the shape here is deliberate in two ways. It scans every rule and every glob
rather than trusting whichever sorts first, because a check whose subject is
chosen for it rots when the subjects move. And it returns nothing rather than
guess at a glob shape it does not recognise — a probe that might not match is
worth less than no probe, since its failure is reported in the same words as a
real one.

Pure and importable so it can be tested without the two model calls that keep
`verify-claude-load.sh` out of `make check`. That the untested half was exactly
the half that broke is the argument for the split.
"""

import re

# A `**/` prefix means "at any depth", so the probe gets a directory under it.
# Matching at depth zero is not portable across glob implementations, and a rule
# file at the repo root is not what the glob was written to describe anyway.
ANY_DEPTH = "**/"

# `*.tsx`, `*.component.ts` — a single leading star, then a literal extension.
# Anchored, so `*.foo*` and `a*b.ts` fall through to "not recognised" rather
# than being approximated.
_EXT_ONLY = re.compile(r"\*(\.[A-Za-z0-9.]+)\Z")

# `name  [scoped: glob, glob]` — the shape `render.py --explain` prints.
_EXPLAIN = re.compile(r"^(\S+)\s+\[scoped: (.+)\]\s*\Z")


def probe_for_glob(glob):
    """A repo-relative path this glob matches, or None if the shape is unknown.

    None is a real answer and must stay distinguishable from a path: the caller
    is expected to keep looking, and to refuse loudly if every glob returns it.
    """
    anydepth = glob.startswith(ANY_DEPTH)
    rest = glob[len(ANY_DEPTH):] if anydepth else glob

    # A `**` left anywhere else (`targets/**/*.swift`) is not handled: the
    # number of directories it stands for is a choice, and a wrong guess is a
    # probe that silently matches nothing.
    if "**" in rest or not rest:
        return None

    if "*" not in rest:
        probe = rest                       # **/lib/auth.ts, data/db.ts, app.json
    else:
        m = _EXT_ONLY.match(rest)
        if not m:
            return None                    # app.config.*, a*.ts — not recognised
        probe = "probe" + m.group(1)       # **/*.tsx -> probe.tsx

    return "src/" + probe if anydepth else probe


def select(explain_output):
    """First (rule, glob, probe) triple that can be built, or None.

    Ordering follows `--explain` so the choice is reproducible on a given rule
    set, while no longer being *fixed* to whichever rule happens to sort first.
    """
    for line in explain_output.splitlines():
        m = _EXPLAIN.match(line.strip())
        if not m:
            continue
        rule = m.group(1)
        for glob in (g.strip() for g in m.group(2).split(",")):
            probe = probe_for_glob(glob)
            if probe:
                return rule, glob, probe
    return None


if __name__ == "__main__":
    import sys

    picked = select(sys.stdin.read())
    if not picked:
        sys.exit(1)
    print(*picked)
