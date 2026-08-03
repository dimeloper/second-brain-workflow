#!/usr/bin/env python3
"""Cross-reference rules against the practice notes they were distilled from.

The capture side of this system is automated (update-second-brain writes
notes); the review side — does an `enforced` note actually have a rule,
does a rule's source note still justify it, is the evidence still real —
was entirely manual, which means it's the part that quietly stops happening.
This reports four things, none of which anything else currently checks:

  Unpromoted note   maturity: enforced with no rule tracing back to it
  Orphaned rule     a rule whose source note is gone, or demoted below
                    enforced — never promotes anything, only reports
  Stale claim       enforced, last-reviewed older than --stale-months
                    (default 6 — the same 180-day window review-queue.md
                    already uses for a different purpose)
  Thin evidence     enforced with fewer repos than the actual idea->trialing->
                    enforced threshold, read from the vault's own
                    00-maps/promotion-candidates.md rather than a second
                    hardcoded copy of the number. Exempt: a note whose
                    **Observed in:** line says "enforced by preference" is
                    enforced by the user's own standing default, not by
                    clearing the repo-count bar — that phrase is this
                    vault's own established way of saying so, not a gap.

Rules trace back to a note via a `source:` frontmatter field naming the
note's slug (its filename, no extension — the same identifier every
`[[wikilink]]` in the vault already uses, since Obsidian's link namespace is
flat and slugs are already unique vault-wide). A rule with no `source:` is
reported separately — this script never guesses one.

Usage:
  check-lineage.py [--vault PATH] [--rules-dir PATH] [--stale-months N] [--as-of YYYY-MM-DD]

Exit status: 1 if any rule is orphaned, else 0 — orphaned rules are the one
finding that means a rule is actively claiming evidence that no longer
exists. Everything else is a backlog to notice, not a reason to block.

Read-only. Never writes to the vault or the rules directory. Stdlib only.
"""

import argparse
import re
import sys
from datetime import date
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from lib.config import load as load_config  # noqa: E402
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
    for path in sorted(practices.rglob("*.md")):
        if path.name == "INDEX.md":
            continue
        rel = path.relative_to(practices)
        text = path.read_text(encoding="utf-8")
        fm, warnings = parse_frontmatter(text)
        if fm is None:
            problems.append((str(rel), warnings[0]))
            fm = {}
        else:
            problems.extend((str(rel), w) for w in warnings)

        repos = fm.get("repos") or []
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
                "preference_enforced": "enforced by preference" in text.lower(),
            }
        )
    return notes, problems


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
        rules.append({"file": path.name, "source": fm.get("source") or ""})
    return rules, problems


def enforced_threshold(vault):
    """Read the trialing->enforced repo-count bar from the vault's own
    00-maps/promotion-candidates.md rather than hardcoding a second copy of
    it — the number this script checks against must be the number the
    update-second-brain skill actually promotes on, or "thin evidence" would
    just be a second, driftable opinion about what the bar is.
    """
    path = vault / "00-maps" / "promotion-candidates.md"
    if not path.is_file():
        return None, f"{path} not found — cannot determine the enforced threshold"
    text = path.read_text(encoding="utf-8")
    m = re.search(r'maturity\s*=\s*"trialing"\s+AND\s+length\(repos\)\s*>=\s*(\d+)', text)
    if not m:
        return None, f"{path}: could not find the trialing->enforced threshold pattern"
    return int(m.group(1)), None


def parse_date(value):
    try:
        return date.fromisoformat(value)
    except (TypeError, ValueError):
        return None


def audit(vault, rules_dir, stale_months, as_of):
    notes, note_problems = load_notes(vault)
    rules, rule_problems = load_rules(rules_dir)

    notes_by_slug = {n["slug"]: n for n in notes}
    sourced_slugs = {r["source"] for r in rules if r["source"]}

    unpromoted = [
        n for n in notes if n["maturity"] == "enforced" and n["slug"] not in sourced_slugs
    ]

    orphaned, no_source = [], []
    for r in rules:
        if not r["source"]:
            no_source.append(r)
            continue
        note = notes_by_slug.get(r["source"])
        if note is None:
            orphaned.append((r, f"source '{r['source']}' not found in practices/"))
        elif note["maturity"] != "enforced":
            orphaned.append((r, f"source '{r['source']}' is {note['maturity']}, not enforced"))

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

    threshold, threshold_error = enforced_threshold(vault)
    thin = []
    if threshold is not None:
        thin = [
            n for n in notes
            if n["maturity"] == "enforced"
            and len(n["repos"]) < threshold
            and not n["preference_enforced"]
        ]

    return {
        "unpromoted": unpromoted,
        "orphaned": orphaned,
        "no_source": no_source,
        "stale": stale,
        "thin": thin,
        "threshold": threshold,
        "threshold_error": threshold_error,
        "note_problems": note_problems,
        "rule_problems": rule_problems,
    }


def report(result, vault, rules_dir, stale_months):
    lines = [f"second-brain-workflow lineage audit — vault: {vault}  rules: {rules_dir}", ""]

    lines.append(f"Unpromoted notes (enforced, no covering rule): {len(result['unpromoted'])}")
    for n in result["unpromoted"]:
        lines.append(f"  - {n['slug']}")
    lines.append("")

    lines.append(f"Orphaned rules (source note gone or demoted): {len(result['orphaned'])}")
    for r, why in result["orphaned"]:
        lines.append(f"  - {r['file']}: {why}")
    lines.append("")

    lines.append(f"Rules with no recorded source: {len(result['no_source'])}")
    for r in result["no_source"]:
        lines.append(f"  - {r['file']}")
    lines.append("")

    if result["threshold_error"]:
        lines.append(f"Thin evidence: skipped — {result['threshold_error']}")
    else:
        lines.append(
            f"Thin evidence (enforced, fewer than {result['threshold']} repos): "
            f"{len(result['thin'])}"
        )
        for n in result["thin"]:
            lines.append(f"  - {n['slug']} ({len(n['repos'])} repo(s))")
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

    if not vault.is_dir():
        sys.exit(f"Vault not found: {vault}")

    result = audit(vault, rules_dir, args.stale_months, as_of)

    for rel, problem in result["note_problems"]:
        print(f"warning: {rel}: {problem}", file=sys.stderr)
    for name, problem in result["rule_problems"]:
        print(f"warning: {name}: {problem}", file=sys.stderr)

    print(report(result, vault, rules_dir, args.stale_months))

    return 1 if result["orphaned"] else 0


if __name__ == "__main__":
    sys.exit(main())
