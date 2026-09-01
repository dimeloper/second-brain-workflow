"""Where a repo states what its product is — the tier definitions, shared.

Two callers need the same answer about which files in a repo carry the product's
own statement of itself: `context-sources.py`, which prints them for a reader,
and `check-context-freshness.py`, which asks git when they last changed. Same
argument as `lib/followups.py` and `lib/projects.discover()` — a second copy of
these globs would drift, and the drift would be invisible: one side reporting a
source the other never looks at.

The tier order is authority order and is documented on `context-sources.py`.

Stdlib only.
"""

from pathlib import Path

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
        # Localisation, across the ecosystems this engine actually meets. Dart
        # and the Apple toolchain do not use the JS shapes, and a survey that
        # only knows JS reports a Flutter app as having no shipped surface.
        ("glob", "**/locales/*.json"),
        ("glob", "**/i18n/**/*.json"),
        ("glob", "**/messages/*.json"),
        ("glob", "**/l10n/*.arb"),
        ("glob", "**/*.lproj/*.strings"),
        ("glob", "**/values*/strings.xml"),
        ("glob", "**/locale/**/*.po"),
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
        # `theme.*` alone missed app_theme.dart and app_colors.dart, so a
        # Flutter app with a complete light/dark palette reported an empty
        # brand tier — and an empty tier tells the reader to record the answer
        # as unestablished. A false empty is worse than no survey at all.
        ("glob", "**/*theme*.*"),
        ("glob", "**/*colors*.*"),
        ("glob", "**/*palette*.*"),
        ("glob", "**/tailwind.config.*"),
        # Tailwind v4 has no config file: the theme moved into CSS, as an
        # `@theme` block in the app's main stylesheet. Globbing for the config
        # reported an empty brand tier on a Next.js repo whose palette, font
        # and mark were all present — the same false empty v0.46.1 fixed for
        # Flutter, one stack later. A glob cannot see `@theme`, so this matches
        # the file the convention puts it in.
        ("glob", "**/globals.css"),
        ("glob", "**/app.css"),
        ("glob", "assets/*.png"),
        ("glob", "assets/*.svg"),
        # `assets/` is the Flutter and Expo convention; the web ones put marks
        # in `public/`. Narrow to the mark itself rather than every image, or
        # the tier fills with hero shots and screenshots and stops pointing at
        # anything.
        ("glob", "public/**/logo.*"),
        ("glob", "public/favicon.*"),
    )),
)

# Directories whose contents are never a product's own statement of itself.
#
# The tool-cache entries are not hypothetical tidiness. v0.46.1 broadened the
# brand tier to `**/*theme*.*`, `**/*colors*.*` and `**/*palette*.*` so a
# Flutter palette would be found — and broadening the net without widening the
# exclusions let a *library's* type-check cache into the tier that is supposed
# to say where the product's palette lives. A Python repo reported
# `.mypy_cache/3.11/rich/palette.data.json` as brand, with `colorsys` matching
# `*colors*`. A wrong pointer is worse than an empty tier, because the empty
# one at least says it found nothing.
SKIP = {"node_modules", ".git", "dist", "build", ".next", ".expo", "vendor",
        "Pods", ".venv", "venv", "__pycache__", "coverage", ".turbo",
        ".dart_tool", "Carthage", "DerivedData", "target", "out",
        ".mypy_cache", ".pytest_cache", ".ruff_cache", ".tox", "htmlcov",
        # Agent-skill directories vendor whole toolchains. One of them ships a
        # 55 KB `palette.mjs`, which `**/*palette*.*` reported as a personal
        # site's brand — three times over, once per assistant. Same class as the
        # type-check cache above: a tool's file is never the product's statement
        # of itself.
        ".claude", ".cursor", ".gemini", ".windsurf", ".aider"}

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
