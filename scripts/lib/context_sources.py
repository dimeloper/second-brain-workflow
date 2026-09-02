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

import os
import re
from pathlib import Path

# A theme block, or a custom property assigned a literal colour.
THEME_MARKER = r"(?m)@theme\b|^\s*--[a-z][a-z0-9-]*:\s*(?:#[0-9a-fA-F]{3,8}|oklch\(|rgba?\(|hsla?\()"

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
        # The filename fallbacks stay: a stylesheet can hold brand tokens as
        # plain custom properties with no `@theme` to find.
        ("glob", "**/globals.css"),
        ("glob", "**/app.css"),
        # Two markers, because two things are being looked for. `@theme` is
        # Tailwind v4's, and a custom property assigned an actual colour is what
        # a hand-written token file looks like in any stack — it caught an Astro
        # site's `polish.scss`, which has no `@theme` at all. Assigned, not
        # merely referenced: a stylesheet that *uses* `var(--navy)` is not where
        # `--navy` is decided, and matching those would bury the pointer.
        ("content", ("**/*.css", THEME_MARKER)),
        ("content", ("**/*.scss", THEME_MARKER)),
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


def _glob_re(pattern):
    """A glob translated to a regex over a `/`-joined relative path.

    `Path.glob` cannot be used here — it walks the whole tree before anything
    gets a chance to prune it, and on one Next.js checkout a single
    `**/*.css` took 50 seconds against `node_modules`. The tiers hold about
    thirty patterns, so the survey was paying minutes per repo before any file
    was read. Matching against one pruned walk needs the patterns as regexes.

    `**/` means "at any depth, including none", which is what makes `**/*.css`
    match a stylesheet at the root as well as three levels down. `*` and `?`
    stop at a separator, as they do in a shell.
    """
    out, i = [], 0
    while i < len(pattern):
        if pattern.startswith("**/", i):
            out.append("(?:[^/]+/)*")
            i += 3
        elif pattern[i] == "*":
            out.append("[^/]*")
            i += 1
        elif pattern[i] == "?":
            out.append("[^/]")
            i += 1
        else:
            out.append(re.escape(pattern[i]))
            i += 1
    return re.compile("".join(out) + r"\Z")


def walk(repo):
    """Every file under `repo` as a relative posix path, SKIP pruned in descent.

    Pruning while descending rather than filtering afterwards is the whole
    point: `skipped()` can reject a `node_modules` path only once the walk has
    already produced it.
    """
    out = []
    for dirpath, dirnames, filenames in os.walk(repo, topdown=True, followlinks=False):
        dirnames[:] = sorted(d for d in dirnames if d not in SKIP)
        base = Path(dirpath)
        rel_base = base.relative_to(repo)
        for name in sorted(filenames):
            out.append((str(rel_base / name) if str(rel_base) != "." else name, base / name))
    return out


def find(repo, kind, pattern, tree=None):
    """Paths in `repo` matching one pattern, sorted, capped, skip-dirs pruned."""
    out = []
    tree = walk(repo) if tree is None else tree
    if kind == "file":
        # Case-insensitive, root only: ROADMAP.md and Roadmap.md are one thing,
        # and a ROADMAP.md three levels down is somebody's dependency.
        for child in repo.iterdir():
            if child.is_file() and child.name.lower() == pattern.lower():
                out.append(child)
    elif kind == "content":
        # Matched on what the file *says*, not what it is called. Tailwind v4
        # moved the theme into CSS and named the file whatever the project
        # already used — `globals.css`, `app.css`, `tailwind.css`, `index.css` —
        # so filename globs are whack-a-mole: two filenames were added in
        # v0.48.2 and a third repo was still missed the same afternoon. `@theme`
        # is the marker itself, and it cannot be missed by being somewhere new.
        glob, needle = pattern
        rx, grx = re.compile(needle), _glob_re(glob)
        for rel, path in tree:
            if not grx.match(rel):
                continue
            try:
                # A stylesheet a person wrote is kilobytes. Past a megabyte it is
                # a build artifact that escaped SKIP, and reading it would cost
                # more than the answer is worth.
                if path.stat().st_size > 1_000_000:
                    continue
                if rx.search(path.read_text(encoding="utf-8", errors="replace")):
                    out.append(path)
            except OSError:
                continue
    else:
        grx = _glob_re(pattern)
        for rel, path in tree:
            if grx.match(rel):
                out.append(path)
    return sorted(out)[:MAX_PER_PATTERN]
