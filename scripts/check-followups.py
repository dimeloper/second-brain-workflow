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

--brief goes one step further for the common case of standing in a repo: this
repo's items in full, every other repo as a count. That is still not a filter —
the total is unchanged, the counts say how many exist, and anything flagged
`blocked` or `credential` is listed in full whatever repo it belongs to, because
that kind of urgency has nothing to do with where you happen to be standing.

Usage:
  check-followups.py [--vault PATH] [--stale-days N | --recent [N]]
                     [--as-of YYYY-MM-DD] [--repo NAME | --no-repo-grouping]
                     [--brief]

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
from lib.followups import current_repo, display, flag_for  # noqa: E402
from lib.followups import group_for_repo  # noqa: E402
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


RECENT_SEARCH_CAP_DAYS = 90


def collect(notes, as_of, known_repos):
    out = []
    for note_date, path in notes:
        text = path.read_text(encoding="utf-8")
        # Resolved once per note, not once per item — every item in a note
        # shares it.
        context = note_context_repo(text, known_repos) if known_repos else None
        for item in open_followups(text):
            out.append({"date": note_date, "age": (as_of - note_date).days,
                        "item": item, "context": context, "flag": flag_for(item)})
    return out


def audit(vault, stale_days, as_of, known_repos=frozenset()):
    """Every open item in a note older than stale_days — the long-range sweep."""
    picked = [(d, p) for d, p in daily_notes(vault) if (as_of - d).days > stale_days]
    return collect(picked, as_of, known_repos)


def recent(vault, count, as_of, known_repos=frozenset()):
    """Every open item in the `count` most recent notes that exist.

    The check-follow-ups skill's window, implemented here rather than in prose so
    the skill and this script cannot disagree about it. **Notes back, not days
    back**: a day with no note (weekend, holiday, vacation) simply isn't in the
    list, so the window survives a two-week gap the same way it survives a
    Sunday. Age is still reported per item — it is what tells you something has
    been sitting — but it never decides membership, which is the whole difference
    from audit() above.

    Returns (items, notes_used). Search stops at RECENT_SEARCH_CAP_DAYS so a vault
    whose notes thin out reports what it found instead of walking its whole
    history; the caller says so rather than implying the window was full.
    """
    within = [(d, p) for d, p in daily_notes(vault)
              if 0 <= (as_of - d).days <= RECENT_SEARCH_CAP_DAYS]
    picked = sorted(within, key=lambda pair: pair[0], reverse=True)[:count]
    picked.sort(key=lambda pair: pair[0])
    return collect(picked, as_of, known_repos), [d for d, _ in picked]


def line_for(s):
    # The flag is a marker in place, never a second listing of the same item —
    # the contract is that every item appears exactly once, and a "blockers
    # first" section that then re-lists them under their repo breaks it.
    mark = f"[{s['flag']}] " if s.get("flag") else ""
    return f"  - {s['date'].isoformat()} ({s['age']} days open): {mark}{display(s['item'])}"


def basis_suffix(note):
    """How the item got attributed — the repo when it isn't obvious, the guess
    when it was one, and nothing at all when neither adds anything.

    An item under "This repo" attributed by a recorded `#repo/` tag needs no
    annotation: "[#repo tag]" repeated identically down fifteen lines is pure
    noise. An *inferred* attribution does need one, so a wrong grouping can be
    argued with rather than silently trusted. An item from another repo always
    keeps its repo name, since a collapsed report gives it no heading to sit under.
    """
    if not note:
        return ""
    repo, _, basis = note.partition(" — ")
    if not basis:                      # mine: `note` is the bare basis
        return "" if repo == "#repo tag" else f"   [{repo}]"
    if basis == "#repo tag":           # elsewhere, recorded: the repo is the news
        return f"   [{repo}]"
    return f"   [{repo} — {basis}]"


def elsewhere_tally(elsewhere, unknown):
    """[(label, count)] for the other-repo buckets, biggest first, then unknown.

    Counts are per-bucket totals — a flagged item listed above is still counted
    here, because these are how many exist, not how many are hidden.
    """
    per = {}
    for _, note in elsewhere:
        # note is "<repo> — <basis>"; the repo is what a reader navigates by.
        per[(note or "").split(" — ")[0] or "unknown"] = \
            per.get((note or "").split(" — ")[0] or "unknown", 0) + 1
    tally = sorted(per.items(), key=lambda kv: (-kv[1], kv[0]))
    if unknown:
        tally.append(("no repo identified", len(unknown)))
    return tally


def brief_report(stale, vault, header, repo, basis, groups):
    """This repo in full; every other repo as a count. Nothing dropped.

    The asymmetry is the point: run from a repo, the items you can act on now are
    the ones worth reading in full, and thirteen fully-described items from three
    other repos is the noise that made the ungrouped list unreadable in the first
    place. What survives collapsing is anything flagged — a blocker or a live
    credential — because that urgency is not about which repo you are in, and
    hiding it behind a count would be the one genuinely harmful omission here.
    """
    mine, elsewhere, unknown = groups
    lines = [f"second-brain-workflow follow-ups audit — vault: {vault}", "", header]
    lines.append(f"Brief: `{repo}` (from {basis}) in full, other repos as counts. "
                 "Nothing is filtered — run without --brief for every item.")

    promoted = [(s, note) for s, note in (elsewhere + unknown) if s.get("flag")]
    if promoted:
        lines.extend(["", f"Whatever repo it is in ({len(promoted)})"])
        for s, note in promoted:
            lines.append(line_for(s) + basis_suffix(note))

    lines.extend(["", f"This repo — {repo} ({len(mine)})"])
    if mine:
        for s, note in mine:
            lines.append(line_for(s) + basis_suffix(note))
    else:
        lines.append("  (nothing open for this repo)")

    rest = len(elsewhere) + len(unknown)
    if rest:
        note = (f" — {len(promoted)} of them listed above"
                if promoted else "")
        lines.extend(["", f"Elsewhere ({rest}){note}"])
        lines.append("  " + " · ".join(f"{name} {n}" for name, n in
                                       elsewhere_tally(elsewhere, unknown)))
    return "\n".join(lines)


def report(stale, vault, stale_days, repo=None, basis=None, groups=None,
           window=None, brief=False):
    """The audit as text. Oldest first, and grouped by repo when we know one.

    The count line comes before any grouping and counts everything, so the
    number the reader acts on cannot be changed by how well attribution went.
    """
    lines = [f"second-brain-workflow follow-ups audit — vault: {vault}", ""]
    if window is not None:
        asked, dates = window
        if not dates:
            lines.append("Open follow-ups in the last 0 notes: 0 "
                         f"(no daily note in the last {RECENT_SEARCH_CAP_DAYS} days)")
        else:
            span = (f"{dates[0].isoformat()}"
                    if len(dates) == 1
                    else f"{dates[0].isoformat()}..{dates[-1].isoformat()}")
            short = "" if len(dates) == asked else \
                f" — only {len(dates)} exist within {RECENT_SEARCH_CAP_DAYS} days"
            lines.append(f"Open follow-ups in the last {len(dates)} notes "
                         f"({span}): {len(stale)}{short}")
    else:
        lines.append(f"Open follow-ups older than {stale_days} days: {len(stale)}")

    if not stale or groups is None:
        for s in stale:
            lines.append(line_for(s))
        return "\n".join(lines)

    if brief:
        return brief_report(stale, vault, lines[-1], repo, basis, groups)

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
            lines.append(line_for(s) + basis_suffix(note))
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
    ap.add_argument("--brief", action="store_true",
                    help="this repo's items in full, every other repo as a count. "
                         "Anything flagged blocked or credential is still shown in "
                         "full whatever repo it is in. Nothing is filtered.")
    ap.add_argument("--recent", type=int, metavar="N", nargs="?", const=4,
                    help="the check-follow-ups window instead of an age cutoff: "
                         "every open item in the N most recent notes that exist "
                         "(default 4 — today plus the 3 before it). Ignores "
                         "--stale-days, and includes today, which --stale-days "
                         "cannot.")
    args = ap.parse_args()
    # ap.error, not sys.exit: an invalid argument exits 2 like every other
    # argparse rejection, rather than 1, which is what a real finding uses.
    if args.recent is not None and args.recent < 1:
        ap.error("--recent: needs at least 1 note")
    # --brief collapses *other* repos relative to this one, so it means nothing
    # without a repo to be relative to. Refuse rather than quietly print the full
    # list under a heading promising brevity.
    if args.brief and args.no_repo_grouping:
        ap.error("--brief and --no-repo-grouping are opposites; pick one")

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

    window = None
    if args.recent is not None:
        stale, dates = recent(vault, args.recent, as_of, known)
        window = (args.recent, dates)
    else:
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
        if args.brief:
            print("note: --brief needs a repo to be brief relative to; "
                  "showing every item.", file=sys.stderr)

    print(report(stale, vault, args.stale_days, repo, basis, groups, window,
                 brief=args.brief and groups is not None))
    return 0


if __name__ == "__main__":
    sys.exit(main())
