#!/usr/bin/env python3
"""Estimate the per-turn token cost of the always-on rule set.

A rule with no `paths:` loads on every turn, for every agent, whether or not
it's relevant to what's being worked on — that's the point of "always-on,"
and also its cost. Nothing currently measures that cost, or notices when it
grows past whatever ceiling was fine when the rule set was smaller.

Measures the rendered output for each configured target, not the source
`rules/*.md` files — a rule's rendered form carries a frontmatter block and a
provenance comment the source doesn't, so the source's char count would
understate it. Deliberately conservative: the provenance comment is counted
even though some consumers may strip it before loading (Claude Code is known
to, for CLAUDE.md specifically) — better to overestimate a budget check than
under it on an unverified assumption.

Estimate is chars / 4 — a rough, standard approximation, not a real
tokenizer count. Good enough to notice growth and a ceiling crossing; not
good enough to trust to the token.

Always-on set, per configured target:
  - AGENTS.md, if present (loaded by every agent that reads it)
  - CLAUDE.md, for the claude-code target (small, fixed content)
  - any individual rule with no `paths:` — always-on in every target's own
    native form, not just one of them

Ceiling: read from `.rule-budget` — a plain integer, sibling of wherever
`rules/` resolves to (SBW_RULES_DIR's directory, or the engine checkout for a
self-contained one), the same way AGENTS_SRC is derived from RULES_SRC.
Default 2000 if the file doesn't exist. See .rule-budget.example.

Usage:
  rule-budget.py [--rules-dir PATH] [--targets t1,t2] [--ceiling N]

Exit status: 1 if any target's always-on total exceeds the ceiling.
Read-only. Stdlib only.
"""

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import render  # noqa: E402
from lib.config import load as load_config  # noqa: E402

DEFAULT_CEILING = 2000


def resolve_rules_dir(explicit, cfg):
    """Same precedence as render.py itself: flag > SBW_RULES_DIR > default."""
    if explicit:
        return Path(explicit).expanduser().resolve()
    if cfg.get("SBW_RULES_DIR"):
        return Path(cfg["SBW_RULES_DIR"]).expanduser().resolve()
    return render.ENGINE / "rules"


def resolve_ceiling(explicit, rules_dir):
    if explicit is not None:
        return explicit
    path = rules_dir.parent / ".rule-budget"
    if path.is_file():
        text = path.read_text(encoding="utf-8").strip()
        try:
            return int(text)
        except ValueError:
            sys.exit(f"{path}: not an integer: {text!r}")
    return DEFAULT_CEILING


def measure(targets, rules_dir, agents_src, sha):
    """-> {target: [(name, chars), ...]} for the always-on set only."""
    render.RULES_SRC = rules_dir
    render.AGENTS_SRC = agents_src
    rules = render.load_rules()
    always_on = [r for r in rules if r["always"]]

    by_target = {}
    have_agents = agents_src.is_file()
    for target in targets:
        rows, undeliverable = [], []
        if target == "cursor":
            for r in always_on:
                _, content = render.render_cursor(r, sha)
                rows.append((r["name"], len(content)))
        elif target == "claude-code":
            # Mirrors plan(): folded into AGENTS.md when there is one, and only
            # then. Measuring them separately as well would double-count text
            # that is rendered once.
            for r in always_on:
                if have_agents:
                    continue
                _, content = render.render_claude_rule(r, sha)
                rows.append((r["name"], len(content)))
            if have_agents:
                _, content = render.render_claude_md(sha)
                rows.append(("CLAUDE.md", len(content)))
        if target in ("agents", "claude-code"):
            if have_agents:
                _, content = render.render_agents(sha, always_on)
                rows.append(("AGENTS.md", len(content)))
            elif always_on and target == "agents":
                # Only `agents`. Claude Code falls back to per-rule files in
                # .claude/rules and still receives them, which is why the rows
                # above are conditional on have_agents rather than skipped
                # outright. `agents` emits AGENTS.md and nothing else, so with no
                # AGENTS.md it has no carrier at all.
                # Not zero — *undeliverable*. This target's only always-on
                # carrier is AGENTS.md, and there isn't one, so rules that are
                # always-on everywhere else silently do not reach it. A target
                # that cannot deliver the set is not a target the set is free on,
                # and reporting it at zero is the shape this whole check exists
                # to avoid.
                undeliverable = [r["name"] for r in always_on]
        by_target[target] = {"rows": rows, "undeliverable": undeliverable}
    return by_target


def report(by_target, ceiling):
    lines = [f"second-brain-workflow rule budget — ceiling: {ceiling} tokens (chars / 4)", ""]
    over_budget = []

    for target in sorted(by_target):
        rows = by_target[target]["rows"]
        undeliverable = by_target[target]["undeliverable"]
        lines.append(f"[{target}]")
        if undeliverable:
            # Named, and never folded into a zero. The cost is zero here only
            # because the rules do not arrive at all.
            lines.append(
                "  CANNOT CARRY the always-on set — no AGENTS.md, which is this "
                "target's only carrier."
            )
            for name in sorted(undeliverable):
                lines.append(f"    {name} does not reach this target")
            lines.append("")
            continue
        if not rows:
            lines.append("  (nothing always-on)")
            lines.append("")
            continue
        total_chars = 0
        for name, chars in sorted(rows, key=lambda r: -r[1]):
            tokens = chars // 4
            total_chars += chars
            lines.append(f"  {tokens:>6} tokens  {name}")
        total_tokens = total_chars // 4
        lines.append(f"  {'-' * 6}")
        lines.append(f"  {total_tokens:>6} tokens  total")
        if total_tokens > ceiling:
            over_budget.append((target, total_tokens))
            lines.append(f"  OVER BUDGET by {total_tokens - ceiling} tokens")
        lines.append("")

    return "\n".join(lines).rstrip("\n") + "\n", over_budget


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--rules-dir", help="override SBW_RULES_DIR for this run")
    ap.add_argument("--targets", help="override RENDER_TARGETS for this run")
    ap.add_argument("--ceiling", type=int, help="override .rule-budget for this run")
    args = ap.parse_args()

    cfg = load_config(warn=lambda m: print(f"warning: {m}", file=sys.stderr))
    targets_raw = args.targets or cfg["RENDER_TARGETS"]
    targets = [t.strip() for t in targets_raw.split(",") if t.strip()]
    unknown = [t for t in targets if t not in render.ALL_TARGETS]
    if unknown:
        sys.exit(f"Unknown target(s): {', '.join(unknown)}. Known: {', '.join(render.ALL_TARGETS)}")

    rules_dir = resolve_rules_dir(args.rules_dir, cfg)
    agents_src = rules_dir.parent / "AGENTS.md"
    ceiling = resolve_ceiling(args.ceiling, rules_dir)
    sha = render.engine_sha()

    if not rules_dir.is_dir():
        sys.exit(f"Rules directory not found: {rules_dir}")

    by_target = measure(targets, rules_dir, agents_src, sha)
    text, over_budget = report(by_target, ceiling)
    print(text, end="")

    return 1 if over_budget else 0


if __name__ == "__main__":
    sys.exit(main())
