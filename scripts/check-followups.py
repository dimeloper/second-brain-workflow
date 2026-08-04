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

Usage:
  check-followups.py [--vault PATH] [--stale-days N] [--as-of YYYY-MM-DD]

Read-only. Never writes to the vault. Stdlib only.
"""

import argparse
import re
import sys
from datetime import date
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from lib.config import load as load_config  # noqa: E402

DATE_NOTE_RE = re.compile(r'^(\d{4})-(\d{2})-(\d{2})\.md$')
FOLLOWUP_ITEM_RE = re.compile(r'^-\s\[ \]\s+(.*)$')


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


def open_followups(text):
    """Verbatim text of every `- [ ]` item under `## Follow-ups`, in order."""
    lines = text.splitlines()
    items = []
    in_section = False
    for line in lines:
        if line.startswith("## "):
            in_section = line.strip() == "## Follow-ups"
            continue
        if not in_section:
            continue
        m = FOLLOWUP_ITEM_RE.match(line)
        if m:
            items.append(m.group(1).strip())
    return items


def audit(vault, stale_days, as_of):
    stale = []
    for note_date, path in daily_notes(vault):
        age = (as_of - note_date).days
        if age <= stale_days:
            continue
        for item in open_followups(path.read_text(encoding="utf-8")):
            stale.append({"date": note_date, "age": age, "item": item})
    return stale


def report(stale, vault, stale_days):
    lines = [f"second-brain-workflow follow-ups audit — vault: {vault}", ""]
    lines.append(f"Open follow-ups older than {stale_days} days: {len(stale)}")
    for s in stale:
        lines.append(f"  - {s['date'].isoformat()} ({s['age']} days open): {s['item']}")
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--vault", help="vault path (default: $SBW_VAULT)")
    ap.add_argument("--stale-days", type=int, default=30,
                     help="age past which an open follow-up is reported (default: 30)")
    ap.add_argument("--as-of", help="treat this ISO date as today (for reproducible runs/tests)")
    args = ap.parse_args()

    cfg = load_config(warn=lambda m: print(f"warning: {m}", file=sys.stderr))
    vault = resolve_vault(args.vault, cfg)
    as_of = parse_date(args.as_of) if args.as_of else date.today()
    if args.as_of and as_of is None:
        sys.exit(f"--as-of: not an ISO date: {args.as_of}")

    if not vault.is_dir():
        sys.exit(f"Vault not found: {vault}")

    stale = audit(vault, args.stale_days, as_of)
    print(report(stale, vault, args.stale_days))
    return 0


if __name__ == "__main__":
    sys.exit(main())
