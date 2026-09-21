#!/usr/bin/env python3
"""Project overviews whose "Where it stands" line names a version the repo left behind.

The gap this closes. `recent-work.py` reports what happened and is a chronology,
so it cannot go stale — a note about 2026-09-15 is still true in December. The
project docs are the other half: revised in place, present tense, and therefore
the one surface in the vault that *can* be wrong rather than merely old. They
are also the first thing a fresh session reads, because "where does this stand"
is the question a chronology deliberately does not answer.

Nothing checked them. On 2026-09-21 `projects/second-brain-workflow/_project.md`
opened with "**Where it stands.** v0.51.0, cut 2026-09-09, with #22 and #24
open" while the repo was on v0.57.0 — six releases and four merged PRs later,
and `check-followups.py` could not resolve #22 against GitHub at all. It had
been wrong for twelve days and was found by reading.

**Only the "Where it stands" sentence**, and this is the whole design. A project
doc is full of versions — a release history, a decision that shipped in v0.44.0,
a tag somebody linked. Every one of those is a claim about the past and is
supposed to stay where it is. Flagging them would make this check noise on its
first run, and a check people learn to ignore is worse than no check. One
sentence is marked present tense by convention, and that sentence is the claim.

**Only a repo that states its own version**, in a `VERSION` file at its root.
Without one there is nothing to compare against, and guessing from tags would
mean this tool deciding that the newest tag is what the doc should have said.
A project whose repos have no VERSION file is `skipped`, reported as its own
state so a silent pass cannot be mistaken for a clean answer.

Exit 1 when a doc trails by more than --allow-behind releases (default 1, so a
release cut an hour ago is not a finding against a doc nobody has revised yet).
Everything else exits 0. Read-only: never writes to the vault or the repo.

Usage:
  check-project-state.py [--vault PATH] [--project SLUG] [--allow-behind N] [--quiet]
"""

import argparse
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from lib.config import load as load_config  # noqa: E402
from lib.frontmatter import parse_frontmatter  # noqa: E402
from lib.landed import Resolver  # noqa: E402
from lib.projects import discover  # noqa: E402
from lib.vault_state import classify  # noqa: E402

# The sentence that is a claim about now. Bold or plain, and the version may sit
# anywhere in it — "v0.51.0, cut 2026-09-09" and "still on v0.51.0" are the same
# claim typed two ways.
STANDS_RE = re.compile(r'^\*{0,2}Where it stands\.?\*{0,2}\s*(.*)$', re.I)
VERSION_RE = re.compile(r'\bv?(\d+)\.(\d+)\.(\d+)\b')


def resolve_vault(explicit):
    if explicit:
        return Path(explicit).expanduser()
    cfg = load_config(warn=lambda m: print(f"warning: {m}", file=sys.stderr))
    return Path(cfg["SBW_VAULT"]).expanduser()


def parse_version(text):
    m = VERSION_RE.search(text or "")
    return tuple(int(g) for g in m.groups()) if m else None


def fmt(v):
    return "v%d.%d.%d" % v


def stated_version(path):
    """(version, line_number) claimed by the doc's "Where it stands" line.

    The first such line wins. A doc with two of them has a different problem,
    and `keep-one-header-per-section` is the shape that says so.
    """
    for i, line in enumerate(path.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
        m = STANDS_RE.match(line.strip())
        if not m:
            continue
        v = parse_version(m.group(1))
        if v:
            return v, i
    return None, None


def repo_version(repo):
    """The version a checkout states about itself, or None if it states none."""
    path = repo / "VERSION"
    if not path.is_file():
        return None
    return parse_version(path.read_text(encoding="utf-8", errors="replace").strip())


def releases_behind(stated, actual):
    """How many minor releases the doc trails by, counting the majors as 100.

    Crude on purpose. The question is "is this sentence stale enough to mislead
    somebody", not "what is the exact distance in the release graph", and a
    patch release is deliberately worth nothing here — v0.57.0 to v0.57.1 does
    not change where a project stands.
    """
    return (actual[0] - stated[0]) * 100 + (actual[1] - stated[1])


def check(vault, only=None):
    """[(slug, verdict, detail)] — one row per project with an overview."""
    rows = []
    resolve = Resolver()
    for project in discover(vault):
        if only and project["slug"] != only:
            continue
        overview = project["overview"]
        if overview is None:
            continue
        fm, _ = parse_frontmatter(overview.read_text(encoding="utf-8", errors="replace"))
        repos = (fm or {}).get("repos") or []
        if isinstance(repos, str):
            repos = [repos]

        stated, line_no = stated_version(overview)
        if stated is None:
            rows.append((project["slug"], "no-claim",
                         "no `Where it stands` line naming a version"))
            continue

        # The first repo that states a version answers the question. A project
        # spanning four repos has one of them it is versioned by, and the others
        # ship no VERSION file at all — which is what makes this unambiguous in
        # practice rather than a vote.
        found = None
        for name in repos:
            repo = resolve(name)
            if not repo:
                continue
            actual = repo_version(Path(repo))
            if actual:
                found = (name, actual)
                break
        if not found:
            rows.append((project["slug"], "skipped",
                         "no reachable repo with a VERSION file"))
            continue

        name, actual = found
        behind = releases_behind(stated, actual)
        detail = (f"line {line_no} says {fmt(stated)}, {name} is on "
                  f"{fmt(actual)}")
        rows.append((project["slug"], "behind" if behind > 0 else "current",
                     detail if behind > 0 else f"{fmt(stated)} matches {name}"))
        rows[-1] = rows[-1] + (behind,)
    return [r if len(r) == 4 else r + (0,) for r in rows]


def report(rows, allow_behind, quiet):
    findings = [r for r in rows if r[1] == "behind" and r[3] > allow_behind]
    lines = []
    if not quiet:
        for slug, verdict, detail, _ in rows:
            lines.append(f"  {verdict:<9} {slug}: {detail}")
    for slug, _, detail, behind in findings:
        lines.append(f"  STALE {slug}/_project.md — {detail} "
                     f"({behind} release(s) behind).")
        lines.append(f"        Revise the `Where it stands` sentence; it is the "
                     "first one a fresh session reads.")
    if not findings:
        lines.append("  ok    every `Where it stands` line is within "
                     f"{allow_behind} release(s) of its repo")
    return "\n".join(lines), bool(findings)


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--vault", help="vault path (default: $SBW_VAULT)")
    ap.add_argument("--project", help="check one project only")
    ap.add_argument("--allow-behind", type=int, default=1,
                    help="minor releases a doc may trail by before it is a "
                         "finding (default: 1)")
    ap.add_argument("--quiet", action="store_true",
                    help="findings only — no per-project rows")
    args = ap.parse_args()

    vault = resolve_vault(args.vault)
    state, message = classify(vault, "the --vault flag" if args.vault else "$SBW_VAULT")
    if state == "missing":
        sys.exit(message)

    print(f"second-brain-workflow project state — vault: {vault}")
    text, failed = report(check(vault, args.project), args.allow_behind, args.quiet)
    print(text)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
