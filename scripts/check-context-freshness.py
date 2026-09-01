#!/usr/bin/env python3
"""Report `context/` files whose repo has moved on since they were written.

The gap this closes. `update-second-brain` revises the feature a session moved
and `_project.md` when the project itself changed — and it has no step for
`context/` at all. So a repo whose `PRODUCT.md`, README, locales or theme change
leaves its audience, voice and brand files untouched, and nothing says so.

That is not hypothetical. On 2026-09-01 a `context/` written that morning
carried four claims that were wrong rather than merely stale, and they were
found only because another session happened to re-source them while retiring a
repo. The same day, a `PRODUCT.md` was discovered asserting a CMS the repo had
migrated off. Both were caught by a person reading; neither by a check.

**Git dates, not mtimes.** Every repo here is a checkout, and a file's mtime is
rewritten by a clone, a branch switch or a stash pop — none of which is a change
to the product. The honest question is "when was this source last *committed*",
which git answers exactly and which survives moving the checkout.

Repos are located the way `check-followups.py` locates them — `lib.landed`'s
resolver, which tries its cache, then the render registry, then one bounded walk
of `SBW_SCAN_ROOTS`. A repo that was never onboarded is still on this machine,
and calling it unreachable for want of a registry line would report a fact about
the registry as a fact about the context file.

**A repo it cannot reach is `undetermined`, never fresh.** Not on this machine,
not a git checkout, no commits touching any tier source: each is reported as its
own state and none of them counts as up to date. A check that quietly passed on
a repo it could not read would be worse than no check, because the silence would
be indistinguishable from a clean answer — the same argument that makes an empty
tier a finding in `context-sources.py`.

Reports only, never edits. What a stale file needs is a judgement about which
claim moved, and re-running `extract-product-context` against the repo is how
that gets made.

Usage:
  check-context-freshness.py [--vault PATH] [--project NAME] [--quiet]

Exit codes: 0 nothing stale, 1 at least one stale or undetermined file,
2 usage or a missing vault.

Vault resolution: --vault, else $SBW_VAULT, else ~/vaults/second-brain
Stdlib only, by design.
"""

import argparse
import subprocess
import sys
from datetime import date, datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from lib.config import load as load_config  # noqa: E402
from lib.config import origin_describe  # noqa: E402
from lib.context_sources import TIERS, find  # noqa: E402
from lib.frontmatter import parse_frontmatter  # noqa: E402
from lib.projects import discover  # noqa: E402
from lib.landed import Resolver  # noqa: E402
from lib.vault_state import classify  # noqa: E402

DATE_FMT = "%Y-%m-%d"


def resolve_vault(explicit):
    if explicit:
        return Path(explicit).expanduser()
    cfg = load_config(warn=lambda m: print(f"warning: {m}", file=sys.stderr))
    return Path(cfg["SBW_VAULT"]).expanduser()


def last_source_commit(repo):
    """(date, sha, count) for the newest commit touching any tier source.

    Returns (None, reason, 0) when the question cannot be answered.
    """
    if not repo.exists():
        return None, "no checkout at the registered path", 0
    if not (repo / ".git").exists():
        return None, "not a git checkout", 0

    paths = []
    for _, _, patterns in TIERS:
        for kind, pattern in patterns:
            paths.extend(find(repo, kind, pattern))
    if not paths:
        return None, "no tier-1..4 source files in this repo", 0

    rels = sorted({str(p.relative_to(repo)) for p in paths})
    try:
        proc = subprocess.run(
            ["git", "-C", str(repo), "log", "-1", "--format=%cs %H", "--"] + rels,
            capture_output=True, text=True, timeout=30, check=False,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        return None, f"git failed: {exc}", 0
    line = proc.stdout.strip()
    if proc.returncode != 0 or not line:
        return None, "git records no commit touching those files", len(rels)
    stamp, _, sha = line.partition(" ")
    try:
        return datetime.strptime(stamp, DATE_FMT).date(), sha[:9], len(rels)
    except ValueError:
        return None, f"unparseable commit date {stamp!r}", len(rels)


def reviewed_on(path):
    fm, _ = parse_frontmatter(path.read_text(encoding="utf-8", errors="replace"))
    raw = fm.get("last-reviewed")
    if not raw:
        return None
    try:
        return datetime.strptime(str(raw).strip(), DATE_FMT).date()
    except ValueError:
        return None


def check(vault, only=None):
    """[(project, file, verdict, detail)] — one row per context file."""
    rows = []
    # lib.landed's resolver, not a second lookup: cache, then the registry,
    # then one bounded walk of SBW_SCAN_ROOTS. A repo that was never onboarded is
    # still on this machine, and reporting it unreachable for want of a registry
    # line would be a fact about the registry dressed up as a fact about the
    # context file.
    resolve = Resolver()
    for project in discover(vault):
        if only and project["slug"] != only:
            continue
        for ctx in project["context"]:
            fm, _ = parse_frontmatter(ctx.read_text(encoding="utf-8", errors="replace"))
            reviewed = reviewed_on(ctx)
            repos = fm.get("repos") or project.get("repos") or []
            if reviewed is None:
                rows.append((project["slug"], ctx, "undetermined",
                             "no `last-reviewed:` in frontmatter — nothing to compare"))
                continue
            if not repos:
                rows.append((project["slug"], ctx, "undetermined",
                             "names no repos, here or on the project"))
                continue

            newest, newest_detail, unreachable = None, "", []
            for name in repos:
                repo = resolve(name)
                if repo is None:
                    unreachable.append(f"{name}: no checkout found under SBW_SCAN_ROOTS")
                    continue
                when, info, _ = last_source_commit(repo)
                if when is None:
                    unreachable.append(f"{name}: {info}")
                    continue
                if newest is None or when > newest:
                    newest, newest_detail = when, f"{name} {info} {when.isoformat()}"

            if newest is None:
                rows.append((project["slug"], ctx, "undetermined",
                             "; ".join(unreachable) or "no reachable repo"))
                continue
            note = f"reviewed {reviewed.isoformat()}, sources last moved {newest_detail}"
            if unreachable:
                note += f" (also unreachable: {'; '.join(unreachable)})"
            rows.append((project["slug"], ctx, "stale" if newest > reviewed else "ok", note))
    return rows


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--vault", help="vault path (default: $SBW_VAULT)")
    ap.add_argument("--project", help="check one project's context/ only")
    ap.add_argument("--quiet", action="store_true",
                    help="print findings only; say nothing about files that are fine")
    args = ap.parse_args()

    vault = resolve_vault(args.vault)
    state, message = classify(
        vault, "the --vault flag" if args.vault else origin_describe("SBW_VAULT")
    )
    if state == "missing":
        sys.exit(message)

    print(f"second-brain-workflow context freshness — vault: {vault}")
    rows = check(vault, args.project)
    if not rows:
        print()
        print("No `context/` files found — nothing to check.")
        print("`context/` is optional; a vault with none is not missing anything.")
        return 0

    print(f"Compared {len(rows)} context file(s) against the last commit touching")
    print("their repos' tier-1..4 sources. Git dates, not mtimes — a clone or a")
    print("branch switch rewrites an mtime and changes nothing about the product.")
    print()

    order = {"stale": 0, "undetermined": 1, "ok": 2}
    for slug, path, verdict, detail in sorted(rows, key=lambda r: (order[r[2]], r[0])):
        if args.quiet and verdict == "ok":
            continue
        rel = path.relative_to(vault)
        label = {"stale": "STALE", "undetermined": "  ??  ", "ok": "  ok  "}[verdict]
        print(f"  {label}  {rel}")
        print(f"          {detail}")

    stale = sum(1 for r in rows if r[2] == "stale")
    unknown = sum(1 for r in rows if r[2] == "undetermined")
    ok = len(rows) - stale - unknown
    print()
    print(f"{stale} stale, {unknown} undetermined, {ok} up to date.")
    if stale or unknown:
        print()
        print("A stale file is not automatically wrong — it is unverified against a")
        print("repo that has moved. Re-run `extract-product-context` for that repo,")
        print("diff what it finds, and bump `last-reviewed:` when the claims hold.")
        print("An undetermined one is a question this check could not ask at all.")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
