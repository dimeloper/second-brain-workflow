#!/usr/bin/env python3
"""Listing a repo's files, and matching them against path globs.

Shared because two commands ask the same question of a repo — which skills are
scoped here (`skill_manifest.py relevant`) and which practice notes apply here
(`practices-for.py`) — and two implementations of "does this glob match" would
drift into disagreeing about the same repo, which is the one answer that has to
be stable across both.
"""

from pathlib import Path


def repo_files(repo, limit=20000):
    """Repo-relative paths, preferring git's index.

    `git ls-files` is fast, already excludes ignored files, and so never walks
    node_modules or a build directory — which a naive glob would, on the largest
    repos, for the longest time. The bounded fallback exists because a repo being
    onboarded is not always a git repo yet.
    """
    repo = Path(repo)
    try:
        import subprocess
        out = subprocess.run(
            ["git", "-C", str(repo), "ls-files"],
            capture_output=True, text=True, timeout=30, check=False)
        if out.returncode == 0:
            return [line for line in out.stdout.splitlines() if line][:limit]
    except (OSError, ImportError):
        pass

    skip = {".git", "node_modules", ".next", "dist", "build", "__pycache__",
            ".venv", "venv", "Pods", ".expo", ".dart_tool"}
    found = []
    for path in repo.rglob("*"):
        if len(found) >= limit:
            break
        if any(part in skip for part in path.parts):
            continue
        if path.is_file():
            found.append(str(path.relative_to(repo)))
    return found


def path_matches(rel, pattern):
    """Does one repo-relative path match one glob?

    `**/` is treated as "zero or more directories", matching gitignore and Cursor
    rather than fnmatch, whose `**/x` demands a literal slash and so would miss
    the file at the repo root — the single most likely place to look.
    """
    from fnmatch import fnmatch
    if fnmatch(rel, pattern):
        return True
    if pattern.startswith("**/") and fnmatch(rel, pattern[3:]):
        return True
    return False


