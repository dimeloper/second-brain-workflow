#!/usr/bin/env python3
"""What recent daily notes say was achieved — this repo's first.

The mirror of check-followups.py. That one answers "what is still open"; this
one answers "what got done", from the same notes, with the same attribution and
the same refusal to hide an item it could not attribute.

The question comes round constantly — a standup, a status update to somebody
who was not there, a fresh session asking what happened in this repo last week —
and the honest answer is already written down across four or five daily notes.
Reconstructing it from `git log` instead gives you commits, which are a record
of what changed and not of what was decided, abandoned, or found out.

Two sections carry it, and they are not the same claim:

  ## Built        what the session said it did, on the day it did it
  ## Follow-ups   items ticked closed — work that was carried and then finished

A tick carrying `#outcome/dropped` or `#outcome/handed-off` is **not** here.
Nobody did that work; `check-follow-ups` reports those as unresolved, which is
what they are. `superseded` is included and labelled, because something did
happen — it was replaced by a different answer.

Newest first, unlike the follow-ups report. There, age is the finding; here the
most recent thing is the one a status update leads with.

Usage:
  recent-work.py [--vault PATH] [--recent [N] | --since YYYY-MM-DD]
                 [--as-of YYYY-MM-DD] [--repo NAME | --no-repo-grouping] [--full]

Read-only. Never writes to the vault, never ticks anything, never calls git in
another repo. Stdlib only.
"""

import argparse
import re
import sys
from datetime import date
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from lib.config import load as load_config  # noqa: E402
from lib.config import origin_describe  # noqa: E402
from lib.followups import BUILT_HEADING, CONTEXT_BASIS, annotate  # noqa: E402
from lib.followups import closes, current_repo, display  # noqa: E402
from lib.followups import done_followups, group_for_repo  # noqa: E402
from lib.followups import heading_repo, labelled_sections  # noqa: E402
from lib.followups import note_context_repo, outcome_for  # noqa: E402
from lib.followups import repo_file_index, section_items, vault_repos  # noqa: E402
from lib.vault_state import classify  # noqa: E402

DATE_NOTE_RE = re.compile(r'^(\d{4})-(\d{2})-(\d{2})\.md$')

# Same cap as the follow-ups window, and for the same reason: a vault whose
# notes thin out should report what it found rather than walk its whole history.
RECENT_SEARCH_CAP_DAYS = 90

# Wider than check-follow-ups' 4. That window is tuned for "what must I not
# drop today"; this one answers "what have I been doing lately", and a week of
# working days is the unit people actually ask in.
DEFAULT_NOTES = 6

# Read for the footer, not for the body: both say something about the window
# that no individual item does. Practices followed is the vault's own answer to
# "were the rules used", and vault writes is what the window taught.
PRACTICES_HEADING = "## Practices followed"
VAULT_WRITES_HEADING = "## Vault writes (approved)"

WIKILINK_RE = re.compile(r'\[\[([^\]|]+)')


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
        if not DATE_NOTE_RE.match(path.name):
            continue
        d = parse_date(path.stem)
        if d is None:
            continue  # shape matched but not a real calendar date
        notes.append((d, path))
    notes.sort(key=lambda pair: pair[0])
    return notes


def window(vault, as_of, count=None, since=None):
    """The notes to read. -> [(date, path)] oldest first.

    **Notes back, not days back** when counting, which is what makes the window
    survive a weekend, a holiday or a fortnight away without special-casing any
    of them — a day with no note simply is not in the list. `--since` is the
    other question ("what did I do this month"), and there the calendar *is* the
    unit, so it is a date filter and says so.
    """
    notes = daily_notes(vault)
    if since is not None:
        return [(d, p) for d, p in notes if since <= d <= as_of]
    within = [(d, p) for d, p in notes if 0 <= (as_of - d).days <= RECENT_SEARCH_CAP_DAYS]
    picked = sorted(within, key=lambda pair: pair[0], reverse=True)[:count]
    picked.sort(key=lambda pair: pair[0])
    return picked


def links_in(text, heading):
    """Wikilink targets (or bare bullets) under one section, deduped, in order."""
    out = []
    for item in section_items(text, heading):
        found = WIKILINK_RE.findall(item)
        for name in (found or [item]):
            name = name.strip()
            if name and name not in out:
                out.append(name)
    return out


def collect(notes, known_repos):
    """(records, summary) across `notes`.

    A record is one thing that happened: `kind` says which section said so, and
    the two are kept apart all the way to the report because they are different
    evidence. A `## Built` bullet is the session's own account of its day; a
    ticked follow-up is a commitment that survived long enough to be carried and
    then met.
    """
    records = []
    summary = {"notes": len(notes), "no_built": 0, "practices": [], "writes": []}
    for note_date, path in notes:
        text = path.read_text(encoding="utf-8")
        # One context per note, shared by every item in it — the note's own
        # ## Built section names a repo far more often than an item does.
        context = note_context_repo(text, known_repos) if known_repos else None

        built = 0
        for label, items in labelled_sections(text, BUILT_HEADING):
            # The section's own label beats the note-wide fallback: a day that
            # ran two work streams says which is which on each heading, and
            # that is the most deliberate statement of a repo in the note.
            labelled = heading_repo(label, known_repos) if known_repos else None
            for item in items:
                built += 1
                records.append({
                    "date": note_date, "item": item, "kind": "built",
                    "outcome": None,
                    "context": labelled or context,
                    "basis_note": (f"the `{label}` heading" if labelled
                                   else CONTEXT_BASIS),
                })
        if not built:
            summary["no_built"] += 1

        for item in done_followups(text):
            if not closes(item):
                continue  # dropped / handed-off: nobody did that work
            outcome, _ = outcome_for(item)
            records.append({"date": note_date, "item": item, "kind": "closed",
                            "outcome": outcome, "context": context,
                            "basis_note": CONTEXT_BASIS})

        for name in links_in(text, PRACTICES_HEADING):
            if name not in summary["practices"]:
                summary["practices"].append(name)
        for name in links_in(text, VAULT_WRITES_HEADING):
            if name not in summary["writes"]:
                summary["writes"].append(name)

    records.sort(key=lambda r: r["date"], reverse=True)
    return records, summary


def basis_suffix(record, show_repo):
    """How this item got here — the repo when its heading does not say, the
    guess when it was one, and nothing at all when neither adds anything.

    An item under "This repo" attributed by a recorded `#repo/` tag needs no
    annotation; the same suffix repeated down fifteen lines is noise. An
    *inferred* one does, so a wrong grouping can be argued with instead of
    silently trusted — and for a Built item the inference is usually the
    section's own `## Built (repo: …)` label, which the basis names.
    """
    repo, basis = record.get("repo"), record.get("basis")
    if show_repo and repo:
        return f"   [{repo}]" if basis == "#repo tag" else f"   [{repo} — {basis}]"
    if basis and basis != "#repo tag":
        return f"   [{basis}]"
    return ""


def line_for(record, show_repo=False):
    mark = "[superseded] " if record["outcome"] == "superseded" else ""
    return (f"    {record['date'].isoformat()}  {mark}{display(record['item'])}"
            f"{basis_suffix(record, show_repo)}")


def kind_block(records, title, indent="  ", show_repo=False):
    if not records:
        return []
    lines = [f"{indent}{title} ({len(records)})"]
    lines.extend(line_for(r, show_repo) for r in records)
    return lines


def split_kinds(pairs):
    """[(record, basis)] -> (built, closed), keeping the report's order."""
    built = [r for r, _ in pairs if r["kind"] == "built"]
    closed = [r for r, _ in pairs if r["kind"] == "closed"]
    return built, closed


def tally(elsewhere, unknown):
    """[(label, count)] for the other-repo buckets, biggest first, then unknown."""
    per = {}
    for _, note in elsewhere:
        name = (note or "").split(" — ")[0] or "unknown"
        per[name] = per.get(name, 0) + 1
    out = sorted(per.items(), key=lambda kv: (-kv[1], kv[0]))
    if unknown:
        out.append(("no repo identified", len(unknown)))
    return out


def plural(n, word, suffix="s"):
    return f"{n} {word}" if n == 1 else f"{n} {word}{suffix}"


def header_line(records, notes, asked, since):
    built = sum(1 for r in records if r["kind"] == "built")
    closed = len(records) - built
    counts = f"{plural(len(records), 'item')} ({built} built, {closed} closed)"
    if not notes:
        if since:
            return f"Recent work since {since.isoformat()}: none — no daily note in that range"
        return ("Recent work in the last 0 notes: none — no daily note in the "
                f"last {RECENT_SEARCH_CAP_DAYS} days")
    dates = [d for d, _ in notes]
    span = (dates[0].isoformat() if len(dates) == 1
            else f"{dates[0].isoformat()}..{dates[-1].isoformat()}")
    if since:
        return (f"Recent work since {since.isoformat()} "
                f"({plural(len(dates), 'note')}, {span}): {counts}")
    short = "" if len(dates) == asked else (
        f" — only {plural(len(dates), 'note')} "
        f"{'exists' if len(dates) == 1 else 'exist'} within "
        f"{RECENT_SEARCH_CAP_DAYS} days")
    return (f"Recent work in the last {plural(len(dates), 'note')} "
            f"({span}): {counts}{short}")


def footers(summary, repo):
    out = []
    if summary["no_built"]:
        # Said out loud, because a thin window and a quiet week look identical
        # in a summary and lead to opposite conclusions about the record.
        have = "has" if summary["no_built"] == 1 else "have"
        out.append(f"{summary['no_built']} of the "
                   f"{plural(summary['notes'], 'note')} in this window {have} "
                   "no ## Built section — the record is thinner than the window "
                   "suggests.")
    if summary["practices"]:
        out.append(f"Practices followed in this window ({len(summary['practices'])}, "
                   "whatever repo): " + ", ".join(summary["practices"]))
    if summary["writes"]:
        out.append(f"Vault writes approved in this window ({len(summary['writes'])}): "
                   + ", ".join(summary["writes"]))
    engine = Path(__file__).resolve().parent
    if repo:
        out.append(f"Where this stands now, rather than what happened: "
                   f"{engine}/project-for.py --repo <path>")
    out.append("What is still open: "
               f"{engine}/check-followups.py --recent --brief")
    return out


def report(records, notes, asked, since, vault, repo, basis, groups, brief):
    lines = [f"second-brain-workflow recent work — vault: {vault}", "",
             header_line(records, notes, asked, since)]

    if not records:
        lines.append("")
        lines.append("  Nothing recorded as built or closed in this window.")
        lines.extend([""] + footers({"notes": len(notes), "no_built": 0,
                                     "practices": [], "writes": []}, repo))
        return "\n".join(lines)

    if groups is None:
        lines.append("Newest first. Not grouped by repo.")
        built, closed = split_kinds([(r, None) for r in records])
        lines.extend([""] + kind_block(built, "Built", indent=""))
        lines.extend([""] + kind_block(closed, "Closed follow-ups", indent=""))
        return "\n".join(lines)

    mine, elsewhere, unknown = groups
    lines.append(f"Newest first. This repo is `{repo}` (from {basis}); every item "
                 "above is listed below exactly once.")
    if brief:
        lines.append("Brief: this repo in full, other repos as counts. Nothing is "
                     "filtered — --full lists every item.")

    built, closed = split_kinds(mine)
    lines.extend(["", f"This repo — {repo} ({len(mine)})"])
    if mine:
        lines.extend(kind_block(built, "Built"))
        lines.extend(kind_block(closed, "Closed follow-ups"))
    else:
        lines.append("    (nothing recorded for this repo in this window)")

    rest = elsewhere + unknown
    if rest and brief:
        lines.extend(["", f"Elsewhere ({len(rest)})"])
        lines.append("  " + " · ".join(f"{name} {n}" for name, n in
                                       tally(elsewhere, unknown)))
    elif rest:
        for title, bucket in (("Other repos", elsewhere),
                              ("No repo identified", unknown)):
            if not bucket:
                continue
            b, c = split_kinds(bucket)
            lines.extend(["", f"{title} ({len(bucket)})"])
            lines.extend(kind_block(b, "Built", show_repo=True))
            lines.extend(kind_block(c, "Closed follow-ups", show_repo=True))
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--vault", help="vault path (default: $SBW_VAULT)")
    ap.add_argument("--recent", type=int, metavar="N", nargs="?", const=DEFAULT_NOTES,
                    help=f"the N most recent notes that exist (default {DEFAULT_NOTES}). "
                         "Notes back, not days back, so a weekend or a holiday "
                         "costs nothing.")
    ap.add_argument("--since", metavar="YYYY-MM-DD",
                    help="every note on or after this date instead of a note count "
                         "— the calendar question, for a month or a sprint")
    ap.add_argument("--as-of", help="treat this ISO date as today (for reproducible runs/tests)")
    ap.add_argument("--repo", help="report as if run from this repo "
                                   "(default: detect from the working directory)")
    ap.add_argument("--no-repo-grouping", action="store_true",
                    help="one flat list, newest first, with no repo grouping")
    ap.add_argument("--full", action="store_true",
                    help="list every repo's items in full instead of tallying "
                         "the other repos")
    args = ap.parse_args()

    if args.recent is not None and args.recent < 1:
        ap.error("--recent: needs at least 1 note")
    if args.recent is not None and args.since:
        ap.error("--recent counts notes and --since reads a calendar; pick one")
    if args.full and args.no_repo_grouping:
        ap.error("--full lists every repo's items, which --no-repo-grouping "
                 "already does; pick one")

    cfg = load_config(warn=lambda m: print(f"warning: {m}", file=sys.stderr))
    vault = resolve_vault(args.vault, cfg)
    as_of = parse_date(args.as_of) if args.as_of else date.today()
    if args.as_of and as_of is None:
        sys.exit(f"--as-of: not an ISO date: {args.as_of}")
    since = parse_date(args.since) if args.since else None
    if args.since and since is None:
        sys.exit(f"--since: not an ISO date: {args.since}")

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
            repo, basis = current_repo(known=known)

    asked = args.recent if args.recent is not None else DEFAULT_NOTES
    notes = window(vault, as_of, count=asked, since=since)
    records, summary = collect(notes, known)

    repo_files = repo_file_index(Path.cwd()) if repo else None
    annotate(records, known, repo, repo_files,
             text=lambda r: r["item"], context=lambda r: r["context"],
             context_basis=lambda r: r["basis_note"])

    if repo:
        groups = group_for_repo(records, repo, known, repo_files,
                                text=lambda r: r["item"],
                                context=lambda r: r["context"])
    elif records and not args.no_repo_grouping:
        print(f"note: not grouping by repo — {basis}.", file=sys.stderr)

    print(report(records, notes, asked, since, vault, repo, basis, groups,
                 brief=not args.full))
    if records:
        print("\n" + "\n".join(footers(summary, repo)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
