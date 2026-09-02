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

Reports only, and never *interprets* a file: this says where to read, and the
reading is the `extract-product-context` skill's job. Keeping the judgement out
of a script is deliberate — a tool that summarised these files would be one more
thing between a reader and the source, and the source is the whole point.

**It used to say "never opens a file", and that changed in v0.49.2.** The brand
tier now greps stylesheets for `@theme`, because Tailwind v4 moved the theme into
CSS under whatever filename the project already had — `globals.css`, `app.css`,
`tailwind.css` — and two rounds of adding filenames still missed a third repo the
same afternoon. A marker cannot be missed by being somewhere new. The line that
matters is unchanged: it decides whether a file belongs in a tier, and never what
the file means.

Stdlib only. Read-only. Exit 0 unless the repo cannot be read.
"""

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from lib.context_sources import TIERS, find, walk  # noqa: E402

# Filenames are matched case-insensitively against the repo root; globs are
# matched anywhere. Ordered within each tier by how much they usually carry.
def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--repo", required=True, help="product repo to survey")
    args = ap.parse_args()

    repo = Path(args.repo).expanduser().resolve()
    if not repo.is_dir():
        sys.exit("No such repo: %s" % repo)

    print("context sources in %s" % repo)
    print()

    # One walk for every pattern in every tier. Per-pattern globbing walked
    # node_modules once per pattern, which on a Next.js checkout was 50 seconds
    # each against thirty-odd patterns.
    tree = walk(repo)
    empty = []
    for name, why, patterns in TIERS:
        hits = []
        for kind, pattern in patterns:
            for path in find(repo, kind, pattern, tree=tree):
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
