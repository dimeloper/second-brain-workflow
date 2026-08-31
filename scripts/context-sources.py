#!/usr/bin/env python3
"""Where a repo already states what its product is, who it is for, and how it talks.

The failure this closes. On 2026-08-31 the first `context/` written for a
product app got its central claim wrong — it asserted the product ended at
birth, inferred from the vocabulary of the store listing. The repo contained a
`ROADMAP.md` with a phase named *Post-Birth Retention*, plus install and
conversion numbers, plus a written boundary against a sibling app. None of it
was read, because nothing said to look and the two sources that *talk about* a
product — daily notes and store copy — are the ones that come to mind.

So this enumerates the places a product actually defines itself, in order of
authority, and — the half that matters — **names the tiers that are empty**. A
tier with nothing in it is a finding: it says the answer is not in this repo and
must be asked for, rather than inferred from a tier that happens to be full.

  1  product docs      Written to state intent. Highest authority: a roadmap
                       says what the product is *for*, which nothing else does.
  2  store metadata    The pitch. Authoritative about voice and claims, and
                       about audience only as marketing believes it.
  3  shipped surface   Routes, locales, paywall and flag config. What the
                       product *is*, as against what it says — the tier that
                       contradicts tier 2 when they disagree.
  4  brand             Tokens, theme, app config, icons. Points at a source
                       when one exists; its absence is why some `context/`
                       files must hold prose instead.

Reports only, and never opens a file: this says *where to read*, and the reading
is the `extract-product-context` skill's job. Keeping the judgement out of a
script is deliberate — a tool that summarised these files would be one more
thing between a reader and the source, and the source is the whole point.

Stdlib only. Read-only. Exit 0 unless the repo cannot be read.
"""

import argparse
import sys
from pathlib import Path

# Filenames are matched case-insensitively against the repo root; globs are
# matched anywhere. Ordered within each tier by how much they usually carry.
TIERS = (
    ("product docs", "what the product is for, in the team's own words", (
        ("file", "ROADMAP.md"),
        ("file", "KNOWLEDGE_BASE.md"),
        ("file", "PRODUCT.md"),
        ("file", "VISION.md"),
        ("file", "STRATEGY.md"),
        ("glob", "docs/features/*.md"),
        ("glob", "docs/product/*.md"),
        ("file", "CLAUDE.md"),
        ("file", "AGENTS.md"),
        ("file", "README.md"),
    )),
    ("store metadata", "the pitch, and the canonical voice artifact if there is one", (
        ("glob", "store/listings/*/*.txt"),
        ("glob", "metadata/*/*.txt"),
        ("glob", "fastlane/metadata/**/*.txt"),
        ("glob", "metadata/screenshots/*.md"),
        ("glob", "store/**/*.md"),
    )),
    ("shipped surface", "what the product is, as against what it claims", (
        ("glob", "**/locales/*.json"),
        ("glob", "**/i18n/**/*.json"),
        ("glob", "**/messages/*.json"),
        ("glob", "app/**/_layout.tsx"),
        ("glob", "src/app/**/page.tsx"),
        ("glob", "**/paywall*.*"),
        ("glob", "**/feature-flags*.*"),
        ("glob", "**/entitlements*.*"),
    )),
    ("brand", "tokens and marks — point at these rather than restating them", (
        ("file", "app.config.ts"),
        ("file", "app.config.js"),
        ("file", "app.json"),
        ("glob", "**/tokens.*"),
        ("glob", "**/theme.*"),
        ("glob", "**/tailwind.config.*"),
        ("glob", "assets/*.png"),
        ("glob", "assets/*.svg"),
    )),
)

# Directories whose contents are never a product's own statement of itself.
SKIP = {"node_modules", ".git", "dist", "build", ".next", ".expo", "vendor",
        "Pods", ".venv", "venv", "__pycache__", "coverage", ".turbo"}

MAX_PER_PATTERN = 12


def skipped(path, repo):
    return any(part in SKIP for part in path.relative_to(repo).parts)


def find(repo, kind, pattern):
    """Paths in `repo` matching one pattern, sorted, capped, skip-dirs pruned."""
    out = []
    if kind == "file":
        # Case-insensitive, root only: ROADMAP.md and Roadmap.md are one thing,
        # and a ROADMAP.md three levels down is somebody's dependency.
        for child in repo.iterdir():
            if child.is_file() and child.name.lower() == pattern.lower():
                out.append(child)
    else:
        for path in repo.glob(pattern):
            if path.is_file() and not skipped(path, repo):
                out.append(path)
    return sorted(out)[:MAX_PER_PATTERN]


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--repo", required=True, help="product repo to survey")
    args = ap.parse_args()

    repo = Path(args.repo).expanduser().resolve()
    if not repo.is_dir():
        sys.exit("No such repo: %s" % repo)

    print("context sources in %s" % repo)
    print()

    empty = []
    for name, why, patterns in TIERS:
        hits = []
        for kind, pattern in patterns:
            for path in find(repo, kind, pattern):
                rel = path.relative_to(repo)
                if rel not in [h[0] for h in hits]:
                    hits.append((rel, pattern))
        print("%s — %s" % (name.upper(), why))
        if not hits:
            print("  (nothing)")
            empty.append(name)
        for rel, pattern in hits:
            try:
                size = path_size(repo / rel)
            except OSError:
                size = "?"
            print("  %-58s %s" % (rel, size))
        print()

    print("Read tier 1 before tier 2. A roadmap states intent; a listing states")
    print("a pitch, and the two disagree often enough that reading them in the")
    print("wrong order produces a confident wrong answer.")
    if empty:
        print()
        # The disclosure that makes the report usable. Silence here would let a
        # full tier stand in for an empty one, which is the substitution that
        # produced the defect this exists for.
        print("EMPTY, and that is a finding rather than a gap to fill by")
        print("inference: %s." % ", ".join(empty))
        print("Whatever those tiers would have answered is not in this repo.")
        print("Ask for it, or record it as unestablished — do not derive it")
        print("from a tier that happens to be populated.")
    return 0


def path_size(path):
    n = path.stat().st_size
    if n < 1024:
        return "%d B" % n
    return "%.1f KB" % (n / 1024)


if __name__ == "__main__":
    sys.exit(main())
