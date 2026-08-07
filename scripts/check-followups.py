#!/usr/bin/env python3
"""Find open `## Follow-ups` items whose daily note has aged past a window.

The capture side is automated (daily notes get a Follow-ups section as they're
written); the review side is the check-follow-ups skill, which walks back to
the last few notes that actually exist — deliberately narrow, so it survives
a weekend or a vacation gap without drowning in old news. That narrowness has
a cost: an item that's still `- [ ]` in a note outside that window has no
mechanism surfacing it again. It just stops being seen.

This is the long-range counterpart: every `YYYY-MM-DD.md` at the vault root,
not just the recent few, reported when the note's own date is older than
--stale-days. Same shape as check-lineage.py's stale/thin findings — a
backlog to notice, never a reason to block, so this always exits 0.

Findings are grouped by repo when run from inside one (or given --repo), because
one day's follow-ups routinely span several repos and an unsorted list of twenty
is read as noise. Grouping only — the count and every item are reported whatever
repo they belong to. See lib/followups.py for why filtering would be wrong.

Usage:
  check-followups.py [--vault PATH] [--stale-days N] [--as-of YYYY-MM-DD]
                     [--repo NAME | --no-repo-grouping]

Read-only. Never writes to the vault. Stdlib only.
"""

import argparse
import re
import sys
from datetime import date
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from lib.config import load as load_config  # noqa: E402
from lib.config import origin_describe  # noqa: E402
from lib.followups import current_repo, group_for_repo  # noqa: E402
from lib.followups import note_context_repo, open_followups  # noqa: E402
from lib.followups import repo_file_index, vault_repos  # noqa: E402
from lib.vault_state import classify  # noqa: E402

DATE_NOTE_RE = re.compile(r'^(\d{4})-(\d{2})-(\d{2})\.md$')


def resolve_vault(explicit, cfg):
    if explicit:
        return Path(explicit).expanduser()
    return Path(cfg["SBW_VAULT"]).expanduser()


def parse_date(value):
    try:
        return date.fromisoformat(value)
    except (TypeError, ValueError):
        return None


def daily_notes(vault):
    """(note_date, path) for every YYYY-MM-DD.md at the vault root, oldest first."""
    notes = []
    for path in vault.glob("*.md"):
        m = DATE_NOTE_RE.match(path.name)
        if not m:
            continue
        d = parse_date(path.stem)
        if d is None:
            continue  # shape matched but not a real calendar date
        notes.append((d, path))
    notes.sort(key=lambda pair: pair[0])
    return notes


def audit(vault, stale_days, as_of, known_repos=frozenset()):
    stale = []
    for note_date, path in daily_notes(vault):
        age = (as_of - note_date).days
        if age <= stale_days:
            continue
        text = path.read_text(encoding="utf-8")
        # Resolved once per note, not once per item — every item in a note
        # shares it.
        context = note_context_repo(text, known_repos) if known_repos else None
        for item in open_followups(text):
            stale.append({"date": note_date, "age": age, "item": item,
                          "context": context})
    return stale


def line_for(s):
    return f"  - {s['date'].isoformat()} ({s['age']} days open): {s['item']}"


def report(stale, vault, stale_days, repo=None, basis=None, groups=None):
    """The audit as text. Oldest first, and grouped by repo when we know one.

    The count line comes before any grouping and counts everything, so the
    number the reader acts on cannot be changed by how well attribution went.
    """
    lines = [f"second-brain-workflow follow-ups audit — vault: {vault}", ""]
    lines.append(f"Open follow-ups older than {stale_days} days: {len(stale)}")

    if not stale or groups is None:
        for s in stale:
            lines.append(line_for(s))
        return "\n".join(lines)

    mine, elsewhere, unknown = groups
    lines.append(f"Grouped by repo. This repo is `{repo}` (from {basis}); "
                 "every item above is listed below exactly once.")
    for title, bucket in (
        (f"This repo — {repo} ({len(mine)})", mine),
        (f"Other repos ({len(elsewhere)})", elsewhere),
        (f"No repo identified ({len(unknown)})", unknown),
    ):
        if not bucket:
            continue
        lines.extend(["", title])
        for s, note in bucket:
            suffix = f"   [{note}]" if note else ""
            lines.append(line_for(s) + suffix)
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--vault", help="vault path (default: $SBW_VAULT)")
    ap.add_argument("--stale-days", type=int, default=30,
                     help="age past which an open follow-up is reported (default: 30)")
    ap.add_argument("--as-of", help="treat this ISO date as today (for reproducible runs/tests)")
    ap.add_argument("--repo", help="group as if run from this repo "
                                   "(default: detect from the working directory)")
    ap.add_argument("--no-repo-grouping", action="store_true",
                    help="one flat list, oldest first, with no repo grouping")
    args = ap.parse_args()

    cfg = load_config(warn=lambda m: print(f"warning: {m}", file=sys.stderr))
    vault = resolve_vault(args.vault, cfg)
    as_of = parse_date(args.as_of) if args.as_of else date.today()
    if args.as_of and as_of is None:
        sys.exit(f"--as-of: not an ISO date: {args.as_of}")

    state, message = classify(
        vault, "the --vault flag" if args.vault else origin_describe("SBW_VAULT")
    )
    if state == "missing":
        sys.exit(message)

    repo, basis, groups = None, None, None
    if args.no_repo_grouping:
        known = frozenset()
    else:
        known = vault_repos(vault)
        if args.repo:
            repo, basis = args.repo, "the --repo flag"
        else:
            repo, basis = current_repo()

    stale = audit(vault, args.stale_days, as_of, known)

    # No repo to compare against means nothing could land in "this repo", and
    # three headings over one populated bucket is worse than no headings at all.
    # Fall back to the flat list and say why.
    if repo:
        groups = group_for_repo(stale, repo, known, repo_file_index(Path.cwd()),
                                text=lambda s: s["item"],
                                context=lambda s: s["context"])
    elif stale and not args.no_repo_grouping:
        print(f"note: not grouping by repo — {basis}.", file=sys.stderr)

    print(report(stale, vault, args.stale_days, repo, basis, groups))
    return 0


if __name__ == "__main__":
    sys.exit(main())
