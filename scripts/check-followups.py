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

A ticked item carrying `#outcome/dropped` or `#outcome/handed-off` is reported
too, in a bucket of its own. "Done" and "abandoned" look identical once ticked
and lead to opposite actions when the question comes back: one is finished work
you can cite, the other is an open risk in somebody else's backlog with nobody
watching. A bare `- [x]` closes exactly as it always did — the whole history of
every vault is bare ticks, and reopening those would be the change nobody asked
for.

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
from lib.followup_threads import as_threads, build  # noqa: E402
from lib.followups import OUTCOME_UNRESOLVED, annotate  # noqa: E402
from lib.followups import closes, current_repo, display  # noqa: E402
from lib.followups import done_followups, flag_for  # noqa: E402
from lib.followups import group_for_repo, outcome_for  # noqa: E402
from lib.followups import note_context_repo, open_followups  # noqa: E402
from lib.followups import repo_file_index, unmarked_ticks, vault_repos  # noqa: E402
from lib.landed import CLOSED, LANDED, UNCHECKED, evaluate, refs  # noqa: E402
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
    """(unresolved items, closing ticks, tick counts) across `notes`.

    The closing ticks are never reported. They are collected because an item
    ticked off in a later note closes the same task still sitting unchecked in an
    older one — see lib/followup_threads.build.

    A tick carrying `#outcome/dropped` or `#outcome/handed-off` is not one of
    them. It is an accurate statement that nobody is working on the item and an
    equally accurate statement that the work did not happen — an accepted risk,
    or somebody else's backlog with a name against it. Those go into the first
    list, thread like any open item, and carry their outcome to the report.
    A bare `- [x]`, which is what every note written before the convention
    contains, closes exactly as it always did.
    """
    out, done = [], []
    ticks = {"marked": 0, "unmarked": 0}
    for note_date, path in notes:
        text = path.read_text(encoding="utf-8")
        # Resolved once per note, not once per item — every item in a note
        # shares it.
        context = note_context_repo(text, known_repos) if known_repos else None

        def record(item, note_date=note_date, context=context):
            outcome, owner = outcome_for(item)
            return {"date": note_date, "age": (as_of - note_date).days,
                    "item": item, "context": context, "flag": flag_for(item),
                    "outcome": outcome, "owner": owner}

        out.extend(record(item) for item in open_followups(text))
        for item in done_followups(text):
            (done if closes(item) else out).append(record(item))
        unmarked = len(unmarked_ticks(text))
        ticks["unmarked"] += unmarked
        ticks["marked"] += len(done_followups(text)) - unmarked
    return out, done, ticks


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

    Returns (items, ticked, ticks, notes_used). Search stops at RECENT_SEARCH_CAP_DAYS so a vault
    whose notes thin out reports what it found instead of walking its whole
    history; the caller says so rather than implying the window was full.
    """
    within = [(d, p) for d, p in daily_notes(vault)
              if 0 <= (as_of - d).days <= RECENT_SEARCH_CAP_DAYS]
    picked = sorted(within, key=lambda pair: pair[0], reverse=True)[:count]
    picked.sort(key=lambda pair: pair[0])
    stale, done, ticks = collect(picked, as_of, known_repos)
    return stale, done, ticks, [d for d, _ in picked]


def outcome_mark(s):
    """What the tick actually said, when it said something other than "done".

    Rendered in words rather than echoed as the raw `#outcome/` tag, and only
    for the outcomes that leave work behind — a `done` or `superseded` item is
    not in this report at all, so labelling one would be labelling nothing.
    """
    outcome = s.get("outcome")
    if outcome not in OUTCOME_UNRESOLVED:
        return ""
    if outcome == "handed-off":
        owner = s.get("owner")
        return f"[handed off → {owner}] " if owner else "[handed off, no owner recorded] "
    return f"[{outcome}] "


def line_for(s):
    # The flag is a marker in place, never a second listing of the same item —
    # the contract is that every item appears exactly once, and a "blockers
    # first" section that then re-lists them under their repo breaks it.
    mark = outcome_mark(s) + (f"[{s['flag']}] " if s.get("flag") else "")
    return f"  - {s['date'].isoformat()} ({s['age']} days open): {mark}{display(s['item'])}"


def lines_for(s, note=None, show_repo=False):
    """Every line one thread occupies: the item, then what is known about it.

    The date is the thread's *first* mention and the age is measured from it,
    while the text is the *newest* wording — so the continuation line has to say
    which dates the restatements were, or a reader comparing the report against
    their notes finds text on 08-11 dated 08-08 and has no way to reconcile it.

    Both continuation lines are conditional, so an item mentioned once with
    nothing checkable in it renders exactly as it always did.
    """
    out = [line_for(s) + basis_suffix(note)]
    if s.get("restated"):
        trail = ", ".join(d.strftime("%m-%d") for d in s["dates"][1:])
        out.append(f"      restated {trail} — newest wording shown")
    for verdict in s.get("verdicts", ()):
        # The repo is named only where the line has no heading telling you it —
        # under "This repo" it would repeat identically all the way down, which
        # is what basis_suffix already refuses to do for the same reason.
        where = f" · {verdict.repo}" if show_repo and verdict.repo else ""
        out.append(f"      [{verdict.state}] {verdict.detail}{where}")
    return out


def already_done(thread):
    """Does the repo say this is finished? Merged, or a PR closed unmerged.

    Both belong in the same block and neither ticks anything off: a merged PR is
    almost certainly done and a closed one almost certainly isn't, and the report
    is not in a position to tell which of the two the item's other half — "and
    ship a TestFlight build" — is in. So it asks.
    """
    return any(v.state in (LANDED, CLOSED) for v in thread.get("verdicts", ()))


def counted(bucket):
    """"(3)" when nothing collapsed, "(3 threads, 6 items)" when it did.

    The item count never disappears. Collapsing restatements is the one thing
    here that makes a number go down, so the number it went down from stays on
    the line — an unexplained 3 where the notes plainly show 6 is exactly the
    kind of quiet arithmetic that makes a report untrustworthy.
    """
    items = sum(len(t["dates"]) for t, _ in bucket)
    if items == len(bucket):
        return f"{len(bucket)}"
    return f"{len(bucket)} threads, {items} items"


def lift_done(groups):
    """Pull the finished-looking threads out into a bucket of their own.

    A fourth bucket rather than a marker in place, because these are the only
    ones with an action attached — confirm and tick — and because they are worth
    reading whatever repo they belong to, the same reasoning that promotes a
    blocker or a live credential. Every thread still appears exactly once.
    """
    done, rest = [], []
    for bucket in groups:
        kept = []
        for thread, note in bucket:
            (done if already_done(thread) else kept).append((thread, note))
        rest.append(kept)
    # Stable across buckets: mine, elsewhere, unknown — then oldest first, which
    # is how everything else in this report is ordered.
    done.sort(key=lambda pair: pair[0]["date"])
    return done, tuple(rest)


def unresolved(thread):
    """Ticked, and not finished — an accepted risk or somebody else's backlog."""
    return thread.get("outcome") in OUTCOME_UNRESOLVED


def lift_unresolved(groups):
    """Pull the dropped and handed-off threads out into a bucket of their own.

    They are not open work and they are not finished work, and putting them in
    either list misreports them: mixed into the open items they read as things
    still being carried, and hidden with the ticks they read as done. The whole
    point of recording the outcome is that those two lead to opposite actions.
    """
    out, rest = [], []
    for bucket in groups:
        kept = []
        for thread, note in bucket:
            (out if unresolved(thread) else kept).append((thread, note))
        rest.append(kept)
    out.sort(key=lambda pair: pair[0]["date"])
    return out, tuple(rest)


def unresolved_block(threads):
    """The "nobody is working on this, and it isn't done" section."""
    if not threads:
        return []
    lines = ["", f"Closed without being finished ({counted(threads)}) — "
                 "dropped, or somebody else's now"]
    for thread, note in threads:
        lines.extend(lines_for(thread, note, show_repo=True))
    return lines


GH_MISSING_SUFFIX = "gh not installed"


def check_landed(threads, only_repo=None):
    """Stamp each thread with what its repo says about it. -> footer lines.

    `only_repo` limits the probing to one repo's threads; None checks every one.
    Scoped to this repo by default, because that is where the report is already
    asking you to act — but the skipped ones are *counted and named* in a footer,
    since an unprobed item and a probed-and-open one look identical on the line
    and the difference is the whole point of the check.

    Refs are read from *every* member of a thread, not just the newest wording.
    A restatement routinely drops the branch name it opened with once the author
    stops needing the reminder, and the reference is still the best evidence
    available about the same task.

    The one reason hoisted out of the per-item lines is a missing `gh`: it is a
    fact about the machine rather than about any item, and printed in place it
    would repeat the same sentence under every pull request in the report.
    """
    def text_of(thread):
        return " ".join(m["item"] for m in thread["members"])

    in_scope, skipped = [], 0
    for i, thread in enumerate(threads):
        if only_repo is not None and thread.get("repo") != only_repo:
            # Only worth mentioning if there was something to check — an item
            # naming no PR, branch or commit was never going to be probed.
            if thread.get("repo") and refs(text_of(thread)):
                skipped += 1
            continue
        in_scope.append((i, text_of(thread), thread.get("repo")))

    results = evaluate(in_scope)

    gh_missing = 0
    for i, thread in enumerate(threads):
        kept = []
        for verdict in results.get(i, ()):
            if verdict.state == UNCHECKED and verdict.detail.endswith(GH_MISSING_SUFFIX):
                gh_missing += 1
                continue
            kept.append(verdict)
        thread["verdicts"] = kept

    footers = []
    if gh_missing:
        footers.extend(["", f"{gh_missing} item(s) name a pull request, but gh is "
                            "not installed — their state is unchecked."])
    if skipped:
        footers.extend(["", f"{skipped} item(s) in other repos name a PR, branch or "
                            "commit and were not checked — only this repo's were. "
                            "--landed-all checks them too."])
    return footers


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


def done_block(done):
    """The "confirm and tick" section, or nothing at all.

    Printed above everything else because it is the only part of the report with
    a cheap action attached, and because it is the part most likely to be wrong
    in the reader's favour — an item they have been carrying for four days that
    the repo says landed on Tuesday.
    """
    if not done:
        return []
    lines = ["", f"Looks already done ({counted(done)}) — confirm before ticking"]
    for thread, note in done:
        lines.extend(lines_for(thread, note, show_repo=True))
    return lines


def brief_report(stale, vault, header, repo, basis, groups, done=(), unres=(),
                 footers=()):
    """This repo in full; every other repo as a count. Nothing dropped.

    The asymmetry is the point: run from a repo, the items you can act on now are
    the ones worth reading in full, and thirteen fully-described items from three
    other repos is the noise that made the ungrouped list unreadable in the first
    place. What survives collapsing is anything flagged — a blocker or a live
    credential — because that urgency is not about which repo you are in, and
    hiding it behind a count would be the one genuinely harmful omission here.
    Something the repo says has already landed survives it for the same reason.
    """
    mine, elsewhere, unknown = groups
    lines = [f"second-brain-workflow follow-ups audit — vault: {vault}", "", header]
    lines.append(f"Brief: `{repo}` (from {basis}) in full, other repos as counts. "
                 "Nothing is filtered — run without --brief for every item.")

    lines.extend(done_block(done))
    # Above the count-collapsed groups for the same reason a blocker is: what a
    # dropped or handed-off item needs is a decision, and it is the one kind of
    # item nobody will go looking for, since it no longer reads as open.
    lines.extend(unresolved_block(unres))

    promoted = [(s, note) for s, note in (elsewhere + unknown) if s.get("flag")]
    if promoted:
        lines.extend(["", f"Whatever repo it is in ({len(promoted)})"])
        for s, note in promoted:
            lines.extend(lines_for(s, note, show_repo=True))

    lines.extend(["", f"This repo — {repo} ({counted(mine)})"])
    if mine:
        for s, note in mine:
            lines.extend(lines_for(s, note))
    else:
        lines.append("  (nothing open for this repo)")

    rest = len(elsewhere) + len(unknown)
    if rest:
        note = (f" — {len(promoted)} of them listed above"
                if promoted else "")
        lines.extend(["", f"Elsewhere ({counted(elsewhere + unknown)}){note}"])
        lines.append("  " + " · ".join(f"{name} {n}" for name, n in
                                       elsewhere_tally(elsewhere, unknown)))
    lines.extend(footers)
    return "\n".join(lines)


def total_phrase(threads):
    """The count on the summary line: items, and threads when they differ.

    Items first and always, because that is the number that matches what the
    reader can count in their own notes. The thread count is what the rest of the
    report is organised by, so both have to be on the line or one of them looks
    like an error.
    """
    items = sum(len(t["dates"]) for t in threads)
    if items == len(threads):
        return str(items)
    return f"{items} in {len(threads)} threads"


def report(stale, vault, stale_days, repo=None, basis=None, groups=None,
           window=None, brief=False, done=(), unres=(), footers=()):
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
                         f"({span}): {total_phrase(stale)}{short}")
    else:
        lines.append(f"Open follow-ups older than {stale_days} days: "
                     f"{total_phrase(stale)}")

    if not stale or groups is None:
        for s in stale:
            lines.extend(lines_for(s, show_repo=True))
        lines.extend(footers)
        return "\n".join(lines)

    if brief:
        return brief_report(stale, vault, lines[-1], repo, basis, groups, done,
                            unres, footers)

    mine, elsewhere, unknown = groups
    lines.append(f"Grouped by repo. This repo is `{repo}` (from {basis}); "
                 "every item above is listed below exactly once.")
    lines.extend(done_block(done))
    lines.extend(unresolved_block(unres))
    for title, bucket, show_repo in (
        (f"This repo — {repo} ({counted(mine)})", mine, False),
        (f"Other repos ({counted(elsewhere)})", elsewhere, True),
        (f"No repo identified ({counted(unknown)})", unknown, True),
    ):
        if not bucket:
            continue
        lines.extend(["", title])
        for s, note in bucket:
            lines.extend(lines_for(s, note, show_repo))
    lines.extend(footers)
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
    ap.add_argument("--no-threads", action="store_true",
                    help="report every restatement of a carried-forward item "
                         "separately, instead of collapsing them into one thread "
                         "aged from when it was first raised")
    ap.add_argument("--landed", action="store_true",
                    help="check items naming a PR, branch or commit against that "
                         "repo's main branch. On by default with --recent.")
    ap.add_argument("--no-landed", action="store_true",
                    help="never look at another repo, and never call gh. This is "
                         "the default for the --stale-days audit.")
    ap.add_argument("--landed-all", action="store_true",
                    help="check every repo's refs, not just this repo's. Slower, "
                         "and the point of it is spotting work already done "
                         "somewhere you are not standing.")
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
    if args.landed and args.no_landed:
        ap.error("--landed and --no-landed are opposites; pick one")

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
            repo, basis = current_repo(known=known)

    window = None
    if args.recent is not None:
        items, ticked, ticks, dates = recent(vault, args.recent, as_of, known)
        window = (args.recent, dates)
    else:
        items, ticked, ticks = audit(vault, args.stale_days, as_of, known)

    # Attribution happens here rather than inside the grouping, because
    # threading needs each item's repo before there is anything to group.
    repo_files = repo_file_index(Path.cwd()) if repo else None
    for records in (items, ticked):
        annotate(records, known, repo, repo_files,
                 text=lambda s: s["item"], context=lambda s: s["context"])

    footers = []
    if args.no_threads:
        stale = as_threads(items)
    else:
        stale, closed_later = build(items, as_of, ticked)
        if closed_later:
            footers.extend(["", f"{len(closed_later)} thread(s) left unchecked in an "
                                "older note are ticked off in a newer one, and are "
                                "not listed. --no-threads shows them."])

    # Default on for the skill's window, off for the long-range audit — which is
    # what `make audit` and the vault's CI job run, on a machine with no repo
    # checkouts and no gh auth. An audit that started making network calls would
    # be a different tool than the one those two agreed to run.
    if args.landed or (args.recent is not None and not args.no_landed):
        # Scoped to this repo unless widened — or unless there is no "this repo"
        # to scope to, where restricting would silently check nothing at all.
        scope = None if (args.landed_all or not repo) else repo
        footers.extend(check_landed(stale, scope))

    # No repo to compare against means nothing could land in "this repo", and
    # three headings over one populated bucket is worse than no headings at all.
    # Fall back to the flat list and say why.
    # Only reported once the vault has started recording outcomes at all.
    # Every note written before the convention is full of bare ticks, and a
    # count of those on every run is a number nobody can act on — it would read
    # as a backlog when it is just history.
    if ticks["marked"] and ticks["unmarked"]:
        footers.extend(["", f"{ticks['unmarked']} ticked item(s) in this window "
                            "carry no #outcome/ tag — `- [x]` alone does not say "
                            "whether the work was done, dropped, superseded or "
                            "handed off."])

    done, unres = (), ()
    if repo:
        groups = group_for_repo(stale, repo, known, repo_files,
                                text=lambda s: s["item"],
                                context=lambda s: s["context"])
        # Before lift_done: an item its author recorded as dropped is dropped,
        # whatever a PR probe says about the ref it happens to name.
        unres, groups = lift_unresolved(groups)
        done, groups = lift_done(groups)
    elif stale and not args.no_repo_grouping:
        print(f"note: not grouping by repo — {basis}.", file=sys.stderr)
        if args.brief:
            print("note: --brief needs a repo to be brief relative to; "
                  "showing every item.", file=sys.stderr)

    print(report(stale, vault, args.stale_days, repo, basis, groups, window,
                 brief=args.brief and groups is not None, done=done, unres=unres,
                 footers=footers))
    return 0


if __name__ == "__main__":
    sys.exit(main())
