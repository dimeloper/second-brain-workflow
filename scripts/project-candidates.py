#!/usr/bin/env python3
"""Which long-running initiatives already show up across the daily notes.

A vault that has been running for months has the material for a project doc
sitting in it already — a piece of work that turns up in fifteen notes across
six weeks, whose current state exists only as a thread through those notes, and
which nothing carries into a fresh session. This is the read side of writing one
down: it says what the notes actually evidence, so the drafting that follows
starts from a list rather than from memory.

**It writes nothing, and it is not the backfill.** The backfill is a step of
`update-second-brain`, invoked on request, which drafts a document per candidate,
shows each draft, and writes only the ones approved one at a time. Nothing here
or there constructs a project doc silently, and nothing promotes: a project doc
is not a practice note and never becomes one.

The unit is the repo, deliberately. An initiative is often narrower than its
repo, and this cannot tell the difference — what it can do is count, honestly,
how many notes across how many days mention each repo the vault already knows,
and let a reader who does know say which of those are one initiative and which
are three. A count is evidence; a guessed initiative name would not be.

Usage:
  project-candidates.py [--vault PATH] [--notes N] [--min-notes N]
                        [--min-span N] [--as-of YYYY-MM-DD] [--all]

Read-only. Never writes to the vault. Always exits 0. Stdlib only.
"""

import argparse
import sys
from datetime import date
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from lib.config import load as load_config  # noqa: E402
from lib.config import origin_describe  # noqa: E402
from lib.followups import REPO_TAG_RE, mention_re, vault_repos  # noqa: E402
from lib.frontmatter import parse_frontmatter  # noqa: E402
from lib.vault_state import classify  # noqa: E402

DEFAULT_NOTES = 20
# Thresholds, and why these. Three notes is the point where a subject stops
# being one day's work; a fortnight is the point where "spans dozens of daily
# notes" starts being true and a fresh session can no longer reconstruct the
# state by reading yesterday. Both are arguments, because a vault written four
# days a week is a different shape from one written every day.
DEFAULT_MIN_NOTES = 3
DEFAULT_MIN_SPAN = 14


def parse_date(value):
    try:
        return date.fromisoformat(value)
    except (TypeError, ValueError):
        return None


def daily_notes(vault):
    """(note_date, path) for every YYYY-MM-DD.md at the vault root, oldest first."""
    notes = []
    for path in vault.glob("*.md"):
        d = parse_date(path.stem)
        if d is None:
            continue
        notes.append((d, path))
    notes.sort(key=lambda pair: pair[0])
    return notes


def documented(vault):
    """Repos an existing project doc already claims — slug, and `repos:`.

    Both, because the two disagree in practice: a document named for the
    initiative rather than the repo is the normal case, and the frontmatter is
    where it says which repos it covers.
    """
    covered = {}
    projects = vault / "projects"
    if not projects.is_dir():
        return covered
    for path in sorted(projects.glob("*.md")):
        if path.name == "INDEX.md":
            continue
        fm, _ = parse_frontmatter(path.read_text(encoding="utf-8", errors="replace"))
        names = {path.stem}
        repos = (fm or {}).get("repos") or []
        if isinstance(repos, str):
            repos = [repos]
        names.update(r for r in repos if isinstance(r, str))
        for name in names:
            covered.setdefault(name, path.name)
    return covered


def mentions(text, known_repos):
    """Repo names this note is about: its `#repo/` tags and its `## Built` labels.

    Body prose is deliberately not searched. A repo named once in passing in a
    follow-up about something else is not evidence that the note is about that
    work, and at twenty notes those incidental mentions are what would turn every
    repo the vault has ever heard of into a candidate.
    """
    found = {m.group(1) for m in REPO_TAG_RE.finditer(text)}
    for line in text.splitlines():
        if line.startswith("## Built"):
            found.update(r for r in known_repos if mention_re(r).search(line))
    return found


def collect(notes, known_repos):
    """{repo: [note dates]} across the given notes, oldest first."""
    per = {}
    for note_date, path in notes:
        text = path.read_text(encoding="utf-8", errors="replace")
        for repo in mentions(text, known_repos):
            per.setdefault(repo, []).append(note_date)
    for dates in per.values():
        dates.sort()
    return per


def report(vault, window, per, covered, min_notes, min_span, show_all):
    lines = [f"second-brain-workflow project candidates — vault: {vault}", ""]
    if not window:
        lines.append("No daily notes found — nothing to read.")
        return "\n".join(lines)

    span = (f"{window[0].isoformat()}"
            if len(window) == 1
            else f"{window[0].isoformat()}..{window[-1].isoformat()}")
    lines.append(f"Read the {len(window)} most recent notes ({span}).")

    rows = []
    for repo, dates in per.items():
        days = (dates[-1] - dates[0]).days
        rows.append({
            "repo": repo,
            "notes": len(dates),
            "first": dates[0],
            "last": dates[-1],
            "span": days,
            "doc": covered.get(repo),
            "qualifies": len(dates) >= min_notes and days >= min_span,
        })
    # Longest-running first: the whole question is which piece of work has been
    # going on long enough that its state no longer fits in a day's note.
    rows.sort(key=lambda r: (-r["span"], -r["notes"], r["repo"]))

    candidates = [r for r in rows if r["qualifies"] and not r["doc"]]
    have = [r for r in rows if r["qualifies"] and r["doc"]]
    short = [r for r in rows if not r["qualifies"]]

    lines.append(f"Bar: {min_notes}+ notes spanning {min_span}+ days.")
    lines.append("")
    if candidates:
        lines.append(f"Candidates with no project doc ({len(candidates)})")
        for r in candidates:
            lines.append(f"  - {r['repo']}: {r['notes']} notes, "
                         f"{r['first'].isoformat()}..{r['last'].isoformat()} "
                         f"({r['span']} days)")
    else:
        lines.append("Candidates with no project doc (0)")
        lines.append("  (nothing in this window clears the bar)")

    if have:
        lines.extend(["", f"Already documented ({len(have)})"])
        for r in have:
            lines.append(f"  - {r['repo']}: projects/{r['doc']} — "
                         f"{r['notes']} notes in this window, last {r['last'].isoformat()}")

    if short:
        lines.extend(["", f"Below the bar ({len(short)})"])
        if show_all:
            for r in short:
                lines.append(f"  - {r['repo']}: {r['notes']} notes, {r['span']} days")
        else:
            lines.append("  " + " · ".join(f"{r['repo']} {r['notes']}" for r in short))
            lines.append("  --all lists these in full.")

    lines.extend([
        "",
        "This writes nothing. A candidate is a repo that keeps turning up, not a",
        "drafted document and not a decision that one is worth having — say",
        "\"backfill project docs\" to have update-second-brain draft one per",
        "candidate, show you each draft, and write only the ones you approve.",
    ])
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--vault", help="vault path (default: $SBW_VAULT)")
    ap.add_argument("--notes", type=int, default=DEFAULT_NOTES,
                    help=f"how many recent daily notes to read (default: {DEFAULT_NOTES})")
    ap.add_argument("--min-notes", type=int, default=DEFAULT_MIN_NOTES,
                    help=f"notes an initiative must appear in (default: {DEFAULT_MIN_NOTES})")
    ap.add_argument("--min-span", type=int, default=DEFAULT_MIN_SPAN,
                    help="days between first and last mention "
                         f"(default: {DEFAULT_MIN_SPAN})")
    ap.add_argument("--as-of", help="treat this ISO date as today (for reproducible runs)")
    ap.add_argument("--all", action="store_true",
                    help="list the below-the-bar repos in full instead of tallying them")
    args = ap.parse_args()
    if args.notes < 1:
        ap.error("--notes: needs at least 1 note")

    cfg = load_config(warn=lambda m: print(f"warning: {m}", file=sys.stderr))
    vault = (Path(args.vault).expanduser() if args.vault
             else Path(cfg["SBW_VAULT"]).expanduser())
    state, message = classify(
        vault, "the --vault flag" if args.vault else origin_describe("SBW_VAULT")
    )
    if state == "missing":
        sys.exit(message)

    as_of = parse_date(args.as_of) if args.as_of else None
    if args.as_of and as_of is None:
        sys.exit(f"--as-of: not an ISO date: {args.as_of}")

    notes = daily_notes(vault)
    if as_of:
        notes = [(d, p) for d, p in notes if d <= as_of]
    picked = notes[-args.notes:]

    known = vault_repos(vault)
    per = collect(picked, known)
    print(report(vault, [d for d, _ in picked], per, documented(vault),
                 args.min_notes, args.min_span, args.all))
    return 0


if __name__ == "__main__":
    sys.exit(main())
