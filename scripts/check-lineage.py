#!/usr/bin/env python3
"""Cross-reference rules against the practice notes they were distilled from.

The capture side of this system is automated (update-second-brain writes
notes); the review side — does an `enforced` note actually have a rule,
does a rule's source note still justify it, is the evidence still real —
was entirely manual, which means it's the part that quietly stops happening.
This reports six things, none of which anything else currently checks:

  Unpromoted note   maturity: enforced with no rule tracing back to it
  Orphaned rule     a rule whose source note is gone, or demoted below
                    enforced — never promotes anything, only reports
  Provisional rule  a rule that *declares* it cites a source below enforced,
                    with the reason why that is permanent rather than a matter
                    of time (`provisional:` in its frontmatter). Reported on
                    every run, never fails. It excuses an immature source, never
                    a missing one — see docs/AUDIT.md#provisional-rules
  Stale claim       enforced, last-reviewed older than --stale-months
                    (default 6 — the same 180-day window review-queue.md
                    already uses for a different purpose)
  Maturity above    a maturity whose entry bar the note's repo count does not
  its evidence      meet — `trialing` under the idea->trialing bar, `enforced`
                    under the trialing->enforced one. Both bars are read from
                    the vault's own 00-maps/promotion-candidates.md rather than
                    a second hardcoded copy of the numbers. `idea` is the floor
                    and has no bar to miss. Exempt: a note whose
                    **Observed in:** line says exactly "enforced by
                    preference" — enforced by the user's own standing
                    default, not by clearing the repo-count bar. A note
                    that's close but doesn't match exactly (e.g. a typo) is
                    reported as a near-miss rather than silently losing the
                    exemption.
  Ready to promote  the same comparison in the other direction: a repo count
                    that already clears the *next* bar while the maturity still
                    says otherwise. promotion-candidates.md computes this in
                    Dataview, which renders in Obsidian and nowhere else, so it
                    could not be answered by `make audit` or in CI — which is
                    where a backlog is actually read. Reported, never acted on:
                    automated promotion was rejected deliberately, and a report
                    is what a human gate needs to keep being exercised.

Rules trace back to notes via a `source:` frontmatter field naming their
slugs (a slug is the filename, no extension — the same identifier every
`[[wikilink]]` in the vault already uses, since Obsidian's link namespace is
flat regardless of how notes are foldered). One slug or several, since a rule
is routinely distilled from more than one note:

    source: prefer-signal-apis
    source: [validate-at-the-boundary, fail-fast-env-validation]

A scalar is read as a one-element list, so both forms are equivalent and
neither is deprecated. Every slug is checked independently — a rule is
orphaned by any one of its sources going missing, and covers every note it
names. `practices/` itself is *not*
flat — notes sit in per-domain subdirectories — so slug uniqueness is
enforced when notes are loaded rather than assumed from the layout: two
notes with the same filename in different subdirectories are a hard error,
not a last-write-wins overwrite that would silently decide whether a rule
reads as orphaned. A rule with no `source:` is reported separately — this
script never guesses one.

Usage:
  check-lineage.py [--vault PATH] [--rules-dir PATH] [--stale-months N] [--as-of YYYY-MM-DD]

Exit status: 1 if any rule is orphaned, or if coverage is undetermined
(no rule declares a `source:` at all, so neither lineage direction can be
computed) — else 0. Both mean the same class of thing: a rule claiming
evidence that isn't there, or a check that couldn't run. Everything else is
a backlog to notice, not a reason to block.

If the idea->trialing->enforced threshold can't be read unambiguously from
promotion-candidates.md (file missing, pattern not found, or more than one
conflicting number), that's a hard error, same as a missing vault or rules
directory — never a silent skip. A check that quietly stops checking is
worse than one that isn't there, because the green result is misleading.

Read-only. Never writes to the vault or the rules directory. Stdlib only.
"""

import argparse
import re
import sys
from datetime import date
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from lib.config import load as load_config  # noqa: E402
from lib.config import origin_describe  # noqa: E402
from lib.vault_state import classify  # noqa: E402
from lib.frontmatter import parse_frontmatter  # noqa: E402

ENGINE = Path(__file__).resolve().parent.parent


def resolve_vault(explicit, cfg):
    if explicit:
        return Path(explicit).expanduser()
    return Path(cfg["SBW_VAULT"]).expanduser()


def resolve_rules_dir(explicit, cfg):
    """Same precedence as render.py: flag > SBW_RULES_DIR > engine-relative default."""
    if explicit:
        return Path(explicit).expanduser()
    if cfg.get("SBW_RULES_DIR"):
        return Path(cfg["SBW_RULES_DIR"]).expanduser()
    return ENGINE / "rules"


def load_notes(vault):
    practices = vault / "practices"
    if not practices.is_dir():
        sys.exit(f"No practices/ directory in {vault}")

    notes, problems = [], []
    # Slugs key `notes_by_slug`, which decides whether a rule's `source:`
    # resolves — so a collision doesn't just lose a note, it silently changes
    # a lineage verdict. practices/ is foldered, so basenames can collide;
    # uniqueness is enforced here rather than assumed. Hard error, same class
    # as an unparseable threshold: never last-write-wins.
    seen_slugs = {}
    for path in sorted(practices.rglob("*.md")):
        if path.name == "INDEX.md":
            continue
        rel = path.relative_to(practices)
        if path.stem in seen_slugs:
            sys.exit(
                f"Duplicate note slug '{path.stem}' — a slug must identify exactly "
                f"one note, since rules reference notes by slug alone:\n"
                f"  {seen_slugs[path.stem]}\n"
                f"  {path}\n"
                "Rename one of them."
            )
        seen_slugs[path.stem] = path
        text = path.read_text(encoding="utf-8")
        fm, warnings = parse_frontmatter(text)
        if fm is None:
            problems.append((str(rel), warnings[0]))
            fm = {}
        else:
            problems.extend((str(rel), w) for w in warnings)

        repos = fm.get("repos") or []
        observed_in = extract_observed_in(text)
        notes.append(
            {
                "slug": path.stem,
                "rel": str(rel),
                "maturity": fm.get("maturity") or "?",
                "last_reviewed": fm.get("last-reviewed") or "",
                "repos": repos if isinstance(repos, list) else [repos],
                # A note can be `enforced` by the user's own standing
                # preference rather than by clearing the repo-count bar —
                # an established, self-documented exception in this vault's
                # own convention (its **Observed in:** line says so in
                # exactly these words), not a gap "thin evidence" should flag.
                "preference_enforced": observed_in is not None
                and "enforced by preference" in observed_in.lower(),
                # Close but not exact (typo, reordered words, ...) — still
                # not exempt, but worth a human's attention rather than
                # silently falling into "thin evidence" with no explanation.
                "preference_near_miss": observed_in is not None
                and "enforced by preference" not in observed_in.lower()
                and "preference" in observed_in.lower(),
            }
        )
    return notes, problems


OBSERVED_IN_RE = re.compile(r'^\*\*Observed in:\*\*\s*(.*)', re.MULTILINE)


def extract_observed_in(text):
    """The content of a note's **Observed in:** line, or None if it has none."""
    m = OBSERVED_IN_RE.search(text)
    return m.group(1).strip() if m else None


def load_rules(rules_dir):
    if not rules_dir.is_dir():
        sys.exit(f"No rules directory: {rules_dir}")

    rules, problems = [], []
    for path in sorted(rules_dir.glob("*.md")):
        fm, warnings = parse_frontmatter(path.read_text(encoding="utf-8"))
        if fm is None:
            problems.append((path.name, warnings[0]))
            fm = {}
        else:
            problems.extend((path.name, w) for w in warnings)
        # `source:` accepts one slug or several. A rule is routinely distilled
        # from more than one note — the backend rule set descends from seven —
        # so a single-valued field couldn't express its lineage honestly, and
        # the alternative to a list is leaving it blank, which is what made
        # coverage undetermined in the first place. Scalars are coerced rather
        # than deprecated: same idiom as `repos` on the note side, so a rule
        # written either way keeps working and nothing needs migrating.
        sources = fm.get("source") or []
        if not isinstance(sources, list):
            sources = [sources]
        # Drop blanks: a bare `source:` with nothing after it, or a stray comma
        # in an inline list, means "declared nothing" — never a note named "".
        sources = [s.strip() for s in sources if isinstance(s, str) and s.strip()]
        # `provisional:` is a *reason*, never a boolean. A rule may legitimately
        # descend from a note that is not yet `enforced` — a constraint read off
        # what an external tool writes is as true on the first repo as the third,
        # so it has no evidence curve to climb and would sit orphaned forever.
        # Requiring prose rather than `true` is the whole design: a boolean gets
        # set once and outlives its reason invisibly, while a sentence can be
        # read back and judged, and is printed on every audit run so the
        # exemption stays visible instead of becoming silent.
        provisional = fm.get("provisional") or ""
        if isinstance(provisional, list):
            provisional = " ".join(str(p) for p in provisional)
        provisional = str(provisional).strip()
        rules.append({"file": path.name, "sources": sources, "provisional": provisional})
    return rules, problems


THRESHOLD_RE = re.compile(r'maturity\s*=\s*"trialing"\s+AND\s+length\(repos\)\s*>=\s*(\d+)')
TRIALING_THRESHOLD_RE = re.compile(r'maturity\s*=\s*"idea"\s+AND\s+length\(repos\)\s*>=\s*(\d+)')


def trialing_threshold(vault):
    """The idea->trialing bar, read the same way and failing the same way.

    Its absence is why "thin evidence" only ever reported on `enforced`: the
    script knew one bar, so it could only judge one rung, and the label said so
    honestly while the reader took the number for the whole vault.
    """
    return _threshold(vault, TRIALING_THRESHOLD_RE, "idea->trialing",
                      'idea" AND length(repos) >= N')


def enforced_threshold(vault):
    """Read the trialing->enforced repo-count bar from the vault's own
    00-maps/promotion-candidates.md rather than hardcoding a second copy of
    it — the number this script checks against must be the number the
    update-second-brain skill actually promotes on, or "thin evidence" would
    just be a second, driftable opinion about what the bar is.

    A prose source that can't be parsed unambiguously is a hard error, not a
    fallback or a silently skipped check: a green "thin evidence: 0" result
    that actually means "couldn't tell" would be worse than no check at all.
    """
    return _threshold(vault, THRESHOLD_RE, "trialing->enforced",
                      'trialing" AND length(repos) >= N')


def _threshold(vault, pattern, rung, wording):
    path = vault / "00-maps" / "promotion-candidates.md"
    if not path.is_file():
        sys.exit(f"{path}: not found — cannot determine the {rung} threshold")
    text = path.read_text(encoding="utf-8")
    matches = {int(n) for n in pattern.findall(text)}
    if not matches:
        sys.exit(
            f"{path}: could not find the {rung} threshold — "
            f"expected wording like `{wording}`"
        )
    if len(matches) > 1:
        sys.exit(
            f"{path}: found conflicting {rung} thresholds {sorted(matches)} — "
            "ambiguous, fix the wording so exactly one number matches"
        )
    return matches.pop()


def parse_date(value):
    try:
        return date.fromisoformat(value)
    except (TypeError, ValueError):
        return None


def audit(vault, rules_dir, stale_months, as_of):
    notes, note_problems = load_notes(vault)
    rules, rule_problems = load_rules(rules_dir)

    notes_by_slug = {n["slug"]: n for n in notes}

    # Both lineage directions are computed from the rules that declare a
    # `source:`. If none does, `sourced_slugs` is empty and both go vacuous:
    # every enforced note reads as unpromoted (nothing claims it) and no rule
    # reads as orphaned (nothing is ever looked up). Those numbers are
    # artefacts of missing metadata, not findings — and the unpromoted count
    # is the dangerous one, being specific, plausible, and wrong in the
    # direction that generates work. Same principle as an unparseable
    # threshold: a check that couldn't do its job says so and exits non-zero,
    # rather than printing a count it never earned. Distinguish "parsed and
    # matched" from "parsed nothing and therefore didn't disagree."
    sourced_rules = [r for r in rules if r["sources"]]
    no_source = [r for r in rules if not r["sources"]]
    if not sourced_rules:
        coverage = "none"
    elif no_source:
        coverage = "partial"
    else:
        coverage = "full"

    if coverage == "none":
        # None, not [] — an undetermined result must not be reachable by any
        # code path that formats a count.
        unpromoted, orphaned, provisional = None, None, None
    else:
        sourced_slugs = {s for r in sourced_rules for s in r["sources"]}
        unpromoted = [
            n for n in notes if n["maturity"] == "enforced" and n["slug"] not in sourced_slugs
        ]
        # Every source is checked, not just the first: a rule descending from
        # seven notes is orphaned by any one of them going missing, and naming
        # only the first would hide the rest behind whichever got fixed.
        orphaned = []
        provisional = []
        for r in sourced_rules:
            for src in r["sources"]:
                note = notes_by_slug.get(src)
                if note is None:
                    # A missing note orphans a rule whether or not it declared
                    # itself provisional. `provisional` excuses an *immature*
                    # source, never an absent one: the note being gone means the
                    # lineage cannot be read at all, which is the state the check
                    # exists for, and letting a reason string suppress it would
                    # turn the field into the blanket opt-out it is written to
                    # avoid being.
                    orphaned.append((r, f"source '{src}' not found in practices/"))
                elif note["maturity"] != "enforced":
                    why = f"source '{src}' is {note['maturity']}, not enforced"
                    if r["provisional"]:
                        provisional.append((r, f"{why} — {r['provisional']}"))
                    else:
                        orphaned.append((r, why))

    stale_cutoff_days = stale_months * 30
    stale = []
    for n in notes:
        if n["maturity"] != "enforced":
            continue
        reviewed = parse_date(n["last_reviewed"])
        if reviewed is None:
            continue  # malformed/missing date already surfaced via note_problems
        if (as_of - reviewed).days > stale_cutoff_days:
            stale.append(n)

    threshold = enforced_threshold(vault)  # exits on an unparseable vault source
    trialing_bar = trialing_threshold(vault)

    # The bar a note's *current* maturity had to clear to be set. Judged for
    # every rung that has one, not only `enforced`: a note promoted to
    # `trialing` without clearing the idea->trialing bar is the same claim
    # unsupported by the same evidence, and it was reported by nothing. `idea`
    # is the floor and has no entry bar, so it is absent rather than zero.
    entry_bar = {"trialing": trialing_bar, "enforced": threshold}
    thin = [
        n for n in notes
        if n["maturity"] in entry_bar
        and len(n["repos"]) < entry_bar[n["maturity"]]
        and not n["preference_enforced"]
    ]
    for n in thin:
        n["missed_bar"] = entry_bar[n["maturity"]]
    near_miss = [n for n in thin if n["preference_near_miss"]]

    # The other direction, and the one nothing outside Obsidian could answer:
    # a repo count that already clears the *next* bar while the maturity still
    # says otherwise. promotion-candidates.md computes this in Dataview, which
    # renders in Obsidian and nowhere else — so it was invisible to `make audit`
    # and to CI, which is where the backlog is actually read.
    #
    # Reported, never acted on. Automated promotion was rejected deliberately:
    # the human gate is the point, and a report is what a gate needs to be
    # exercised rather than a thing that quietly stops happening.
    next_bar = {"idea": trialing_bar, "trialing": threshold}
    ready = [
        n for n in notes
        if n["maturity"] in next_bar and len(n["repos"]) >= next_bar[n["maturity"]]
    ]

    return {
        "ready": ready,
        "trialing_bar": trialing_bar,
        "coverage": coverage,
        "sourced_rules": len(sourced_rules),
        "unpromoted": unpromoted,
        "orphaned": orphaned,
        "provisional": provisional,
        "no_source": no_source,
        "stale": stale,
        "thin": thin,
        "near_miss": near_miss,
        "threshold": threshold,
        "note_problems": note_problems,
        "rule_problems": rule_problems,
    }


def report(result, vault, rules_dir, stale_months):
    lines = [f"second-brain-workflow lineage audit — vault: {vault}  rules: {rules_dir}", ""]

    if result["coverage"] == "none":
        # No count, in either direction — see audit(). The categories below
        # are computed from the notes alone and stay valid, so they still run.
        lines.append(
            f"Coverage undetermined: no rule in {rules_dir} declares a `source:`, "
            "so neither unpromoted notes nor orphaned rules can be computed."
        )
        lines.append("")
    else:
        if result["coverage"] == "partial":
            lines.append(
                "Unpromoted notes (enforced, no covering rule among the "
                f"{result['sourced_rules']} rule(s) that declare a source): "
                f"{len(result['unpromoted'])}"
            )
            lines.append(
                f"  upper bound — {len(result['no_source'])} rule(s) declare no "
                "source and were excluded; a note listed here may be covered by one"
            )
        else:
            lines.append(
                f"Unpromoted notes (enforced, no covering rule): {len(result['unpromoted'])}"
            )
        for n in result["unpromoted"]:
            lines.append(f"  - {n['slug']}")
        lines.append("")

        lines.append(f"Orphaned rules (source note gone or demoted): {len(result['orphaned'])}")
        for r, why in result["orphaned"]:
            lines.append(f"  - {r['file']}: {why}")
        lines.append("")

        # Printed on every run, including when the count is zero. An exemption
        # that only appears when someone goes looking is one that stops being
        # read, and the reason is the whole value of the field — a line the
        # reader can disagree with beats a check that silently passed.
        lines.append(
            f"Provisional rules (source deliberately not yet enforced): "
            f"{len(result['provisional'])}"
        )
        for r, why in result["provisional"]:
            lines.append(f"  - {r['file']}: {why}")
        lines.append("")

    lines.append(f"Rules with no recorded source: {len(result['no_source'])}")
    for r in result["no_source"]:
        lines.append(f"  - {r['file']}")
    lines.append("")

    lines.append(
        f"Maturity above its evidence (trialing needs {result['trialing_bar']}, "
        f"enforced needs {result['threshold']}): {len(result['thin'])}"
    )
    for n in result["thin"]:
        lines.append(
            f"  - {n['slug']} ({n['maturity']}, {len(n['repos'])} of "
            f"{n['missed_bar']} repo(s))"
        )
    lines.append("")

    # Printed at zero like every other count here. The caveat is printed at zero
    # too: a reader who only ever sees it when it bites will read the number
    # underneath as exact.
    lines.append(
        f"Ready to promote (repo count already clears the next bar): "
        f"{len(result['ready'])}"
    )
    for n in result["ready"]:
        nxt = "trialing" if n["maturity"] == "idea" else "enforced"
        lines.append(
            f"  - {n['slug']}: {n['maturity']} -> {nxt} ({len(n['repos'])} repo(s))"
        )
    lines.append(
        "  counted as distinct `repos:` entries. The vault's own "
        "one-lineage-counts-once rule is prose in\n"
        "  00-maps/promotion-candidates.md and is not applied here, so a note "
        "naming two repos that\n"
        "  share a history is counted twice — check the list before promoting "
        "on this number."
    )
    lines.append("")

    lines.append(
        f"Thin evidence with a near-miss preference marker "
        f"(check for a typo — not exempted as-is): {len(result['near_miss'])}"
    )
    for n in result["near_miss"]:
        lines.append(f"  - {n['slug']}")
    lines.append("")

    lines.append(f"Stale claims (enforced, last-reviewed > {stale_months} months ago): "
                  f"{len(result['stale'])}")
    for n in result["stale"]:
        lines.append(f"  - {n['slug']} (last-reviewed {n['last_reviewed']})")

    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--vault", help="vault path (default: $SBW_VAULT)")
    ap.add_argument("--rules-dir", help="rules directory (default: $SBW_RULES_DIR, or <engine>/rules)")
    ap.add_argument("--stale-months", type=int, default=6,
                     help="staleness window for enforced notes (default: 6)")
    ap.add_argument("--as-of", help="treat this ISO date as today (for reproducible runs/tests)")
    args = ap.parse_args()

    cfg = load_config(warn=lambda m: print(f"warning: {m}", file=sys.stderr))
    vault = resolve_vault(args.vault, cfg)
    rules_dir = resolve_rules_dir(args.rules_dir, cfg)
    as_of = parse_date(args.as_of) if args.as_of else date.today()
    if args.as_of and as_of is None:
        sys.exit(f"--as-of: not an ISO date: {args.as_of}")

    state, message = classify(
        vault, "the --vault flag" if args.vault else origin_describe("SBW_VAULT")
    )
    if state == "missing":
        sys.exit(message)

    result = audit(vault, rules_dir, args.stale_months, as_of)

    for rel, problem in result["note_problems"]:
        print(f"warning: {rel}: {problem}", file=sys.stderr)
    for name, problem in result["rule_problems"]:
        print(f"warning: {name}: {problem}", file=sys.stderr)

    print(report(result, vault, rules_dir, args.stale_months))

    return 1 if result["coverage"] == "none" or result["orphaned"] else 0


if __name__ == "__main__":
    sys.exit(main())
