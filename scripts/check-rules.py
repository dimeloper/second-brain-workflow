#!/usr/bin/env python3
"""Validate the frontmatter of every rule in a rules directory.

The other two auditors ask whether a rule's *content* still holds up:
`check-lineage.py` cross-references it against the notes it came from,
`rule-budget.py` measures what the always-on set costs. Neither checks that
the frontmatter is the shape those tools expect, so a rule can be written in
a way that quietly does nothing and nothing says so.

The failure that motivates this is a misspelled key. Frontmatter is a plain
mapping — an unrecognised key isn't an error anywhere, it's just a key nobody
reads:

    sourse: prefer-signal-apis     # lineage silently unrecorded
    path:  "**/*.ts"               # rule silently always-on, and billed for it

Both render, both look right in a diff, and both mean the opposite of what
was written. That is strictly worse than a missing field, which at least
reports as missing.

Checks, all of them hard errors — see "Exit status":

  Unknown key       outside {paths, description, source, provisional}. Almost always a
                    typo, and the one failure mode nothing else can catch.
  No source         the rule records no lineage at all, so check-lineage.py
                    cannot tell whether it covers anything. That is the state
                    that made both lineage directions vacuous; catching it
                    here is catching it at authoring time rather than in an
                    audit run against a vault that may not be to hand.
  Malformed value   `paths`/`source` present but empty, or holding a blank
                    entry. A `source:` with nothing after it declares nothing
                    while looking like it declares something.
  Unparseable       no frontmatter block, or a line the shared parser can't
                    read. Reported rather than guessed at, same as everywhere
                    else that uses lib.frontmatter.

Deliberately *not* checked here: whether a rule has a `description`, and
whether its globs survive Cursor's comma-separated form. `render.py` already
owns both — they change what renders, so they belong to the renderer, and two
scripts holding separate opinions about the same field is how they drift
apart. This one owns the file's shape; render.py owns its output.

`rule.md.example` in the engine root is the annotated template for this
format, and is kept in step with the key set below by a parity test — the
convention living in a script but not in the template is exactly how a field
like `source:` ends up missing from every rule someone writes by hand.

Usage:
  check-rules.py [--rules-dir PATH]

Exit status: 1 if any rule has any finding, else 0. There is no advisory tier
here: every finding means a rule does not say what its author believed it
said, which is not a backlog item.

Read-only. Never writes to the rules directory. Stdlib only.
"""

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from lib.config import load as load_config  # noqa: E402
from lib.frontmatter import parse_frontmatter  # noqa: E402

ENGINE = Path(__file__).resolve().parent.parent

# The complete set of keys anything in this system reads from a rule.
# `rule.md.example` documents exactly these, and tests/test-check-rules.sh
# fails if the two fall out of step.
KNOWN_KEYS = {"paths", "description", "source", "provisional"}

# Keys that must hold a non-empty list of non-empty strings when present.
# A scalar is legal for both — render.py and check-lineage.py each coerce one
# to a single-element list — so it is the empty and blank-entry cases that
# need catching, not the scalar.
LIST_KEYS = ("paths", "source")


def resolve_rules_dir(explicit, cfg):
    """Same precedence as render.py: flag > SBW_RULES_DIR > engine-relative."""
    if explicit:
        return Path(explicit).expanduser()
    if cfg.get("SBW_RULES_DIR"):
        return Path(cfg["SBW_RULES_DIR"]).expanduser()
    return ENGINE / "rules"


def check_rule(name, text):
    """Every finding for one rule file, as a list of strings."""
    findings = []
    fm, warnings = parse_frontmatter(text)
    if fm is None:
        return [warnings[0] if warnings else "no frontmatter block"]
    findings.extend(warnings)

    for key in sorted(set(fm) - KNOWN_KEYS):
        findings.append(
            f"unknown key '{key}' — nothing reads it, so whatever it was meant "
            f"to express does not apply. Known keys: {', '.join(sorted(KNOWN_KEYS))}"
        )

    # `provisional:` must be prose, not `true`. The field exempts a rule from
    # the "source must be enforced" lineage check, and a boolean exemption
    # outlives the reason it was added for with nothing left to read; a sentence
    # can be judged stale. `true`/`yes`/`1` are therefore rejected explicitly
    # rather than silently accepted as a truthy string — that is precisely the
    # value someone reaching for a flag will write first.
    if "provisional" in fm:
        value = fm["provisional"]
        text_value = " ".join(value) if isinstance(value, list) else str(value)
        text_value = text_value.strip()
        if not text_value:
            findings.append(
                "'provisional:' is present but empty — it must state why this "
                "rule may cite a source that is not yet enforced"
            )
        elif text_value.lower() in {"true", "false", "yes", "no", "1", "0"}:
            findings.append(
                f"'provisional: {text_value}' is a boolean — write the reason "
                "instead, e.g. 'constraint read off an external tool's behaviour, "
                "so it has no evidence curve to climb'. check-lineage.py prints "
                "it on every run, and a flag with no reason cannot be judged stale"
            )

    for key in LIST_KEYS:
        if key not in fm:
            continue
        value = fm[key] if isinstance(fm[key], list) else [fm[key]]
        if not value:
            findings.append(f"'{key}:' is present but empty — it declares nothing")
        elif any(not str(v).strip() for v in value):
            findings.append(f"'{key}:' has a blank entry")

    if not fm.get("source"):
        findings.append(
            "no 'source:' — the note(s) this was distilled from are unrecorded, "
            "so check-lineage.py cannot tell what it covers. See rule.md.example"
        )

    return findings


def audit(rules_dir):
    if not rules_dir.is_dir():
        sys.exit(f"No rules directory: {rules_dir}")
    results = []
    for path in sorted(rules_dir.glob("*.md")):
        results.append((path.name, check_rule(path.name, path.read_text(encoding="utf-8"))))
    return results


def report(results, rules_dir):
    total = sum(len(f) for _, f in results)
    lines = [
        f"second-brain-workflow rule frontmatter check — rules: {rules_dir}",
        "",
        f"Rules checked: {len(results)}    Findings: {total}",
    ]
    for name, findings in results:
        if not findings:
            continue
        lines.append("")
        lines.append(f"{name}:")
        for f in findings:
            lines.append(f"  - {f}")
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--rules-dir", help="rules directory (default: $SBW_RULES_DIR, or <engine>/rules)")
    args = ap.parse_args()

    cfg = load_config(warn=lambda m: print(f"warning: {m}", file=sys.stderr))
    rules_dir = resolve_rules_dir(args.rules_dir, cfg)

    results = audit(rules_dir)
    print(report(results, rules_dir))
    return 1 if any(findings for _, findings in results) else 0


if __name__ == "__main__":
    sys.exit(main())
