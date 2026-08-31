#!/usr/bin/env python3
"""Vault notes that will not render as written.

The gap this fills. Frontmatter is validated, required sections are validated,
wikilinks are answered by Obsidian in the editor — and **nothing looks at the
text**. On 2026-08-31 six code spans in `projects/**` were wrapped across a line
break, five of them written that day, and every check the engine runs was green
throughout: the index regenerated clean, the commit guard passed, `make audit`
had nothing to say. They were found by eye.

What a wrapped span does, precisely. CommonMark converts the line ending inside
a code span to a space and then strips **at most one** leading space, so a
two-space continuation indent survives:

    `eks-deploy-staging.yml` has had one throughout (`group:
    staging-<release>-<ns>`, `cancel-in-progress: false`)

renders as `group:   staging-<release>-<ns>`. A config key that renders wrong is
a config key somebody copies wrong, in a document whose whole job is to be
trusted as a record.

Why this is the gate and the index is the finding. `build-vault-index.py`
reports the same problem — it already opens every note, so it is the cheapest
place to notice — but its `problems` print to stderr and do not affect its exit
code. A warning inside a run that exits 0 is a warning nobody reads on the day
it appears. This script is what `make audit` fails on.

Not put in the commit guard, and that is deliberate. The guard reads the
*staged diff*, and a wrapped span is a property of two adjacent lines: edit one
of the pair and the diff shows a line with an odd backtick count and no way to
tell whether its partner closes it. A diff-scoped check either false-positives
on a legitimate edit or misses the defect when the other half is what moved. The
guard's contract is *this write is aimed somewhere it should not go*, and prose
quality is not that.

Scope, and what is left out of it:

  practices/**    checked
  projects/**     checked
  daily notes     NOT checked. Every note written before this existed is full of
                  prose nobody is going to re-wrap, and the vault's own rule for
                  the `#outcome/` tags applies unchanged — check what is being
                  written, do not retrofit.

Read-only. Never writes to the vault. Stdlib only.

Exit status: 0 clean, 1 findings, and non-zero with a message if the vault
cannot be read.
"""

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from lib.config import load as load_config  # noqa: E402
from lib.config import origin_describe  # noqa: E402
from lib.markdown import wrapped_code_spans  # noqa: E402
from lib.vault_state import classify  # noqa: E402

# Where notes are prose worth checking. Daily notes are excluded on purpose —
# see the module docstring; this is a tuple rather than a walk of the vault root
# so adding a directory is a decision somebody makes here.
SCANNED = ("practices", "projects")


def findings(vault):
    """[(relative path, lineno, line)] across every scanned note, path-sorted."""
    out = []
    for top in SCANNED:
        root = vault / top
        if not root.is_dir():
            continue
        for path in sorted(root.rglob("*.md")):
            if path.name == "INDEX.md":
                continue
            try:
                text = path.read_text(encoding="utf-8")
            except OSError as exc:
                out.append((path.relative_to(vault), 0, f"unreadable: {exc}"))
                continue
            for lineno, line in wrapped_code_spans(text):
                out.append((path.relative_to(vault), lineno, line.strip()))
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--vault", help="vault path (default: $SBW_VAULT)")
    args = ap.parse_args()

    cfg = load_config(warn=lambda m: print(f"warning: {m}", file=sys.stderr))
    vault = Path(args.vault).expanduser() if args.vault \
        else Path(cfg["SBW_VAULT"]).expanduser()
    state, message = classify(
        vault, "the --vault flag" if args.vault else origin_describe("SBW_VAULT"))
    if state == "missing":
        sys.exit(message)

    hits = findings(vault)
    scanned = ", ".join(f"{t}/**" for t in SCANNED)
    print(f"second-brain-workflow markdown check — vault: {vault}")
    print(f"Scanned: {scanned}   (daily notes excluded by design)")
    print()

    if not hits:
        print("No wrapped code spans.")
        return 0

    # Grouped by file, because the fix is per-file and a flat list of line
    # numbers makes the reader do the grouping themselves.
    print(f"Code spans that wrap a line break: {len(hits)}")
    print("  A span's line ending becomes a space and only one leading space is")
    print("  stripped, so the continuation indent renders inside the span. Keep")
    print("  each span on one line — rewrap the sentence around it.")
    current = None
    for rel, lineno, line in hits:
        if rel != current:
            print()
            print(f"  {rel}")
            current = rel
        print(f"    line {lineno}: {line}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
