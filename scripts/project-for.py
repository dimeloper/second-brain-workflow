#!/usr/bin/env python3
"""What the vault already knows about this repo's initiative.

The gap this fills. `projects/` had a write path and no read path. Wrap-ups
revise the docs, `build-vault-index.py` generates `projects/INDEX.md`, and the
commit guard carries them — and nothing loaded one *into* a session. For a
document whose whole purpose is "what you would hand a fresh session so it does
not re-derive six weeks of daily notes", that is the hole: open a repo, start a
session, and the context is invisible unless somebody remembers it exists and
pastes it by hand.

So this is `practices-for.py`'s sibling, and deliberately the same shape, so
there is one way to ask "what does the vault know about this repo" rather than
one per kind of note.

What it prints, and why in that order. The **overview first**, whole: `_project.md`
is short, it is the stable half, and a session that reads only the first screen
should have read the part that changes least. Then each **feature**: its
frontmatter line and its `## State` section, which is where that slice of work
actually stands. The rest of a feature — its decision log, its contested points —
stays in the file, named by path. A feature's decision log is the expensive half
and the half a session usually does not need; printing all of them would bury
the overview under the thing the two-file split exists to stop burying it.

Between the two sits `context/` — audience, voice, brand: what does not change
per session — and it is printed as **paths only**. The overview is printed whole
because it is short and stable; context is neither, and printing it would bury
the overview under exactly the thing the two-file split exists to stop burying
it. The reader also knows better than this tool which of the three files they
need. Whatever `.md` files are there are listed, so a `context/pricing.md`
appears without a code change.

Matching is on the `repos:` frontmatter that `_project.md` and each feature file
already carry, spelled the way `practices-for.py` spells a repo — the directory
basename. Nothing is inferred from the stack: a project doc is about one named
initiative, and guessing which repo it covers would hand a session six weeks of
somebody else's context as though it were their own.

Deliberately **reports only**. Never edits the repo, never touches the vault —
the same contract `practices-for.py` holds, for a plainer reason: this is the
read side, and the vault has exactly one write path (`update-second-brain`).

A repo with no project doc is a clean "nothing here" at exit 0, not an error.
Most repos have no project doc and never will — a project doc is for a
multi-week initiative, not for every checkout — so a non-zero exit would make
the common case look like a failure and teach every caller to ignore it.

Stdlib only, like everything else in scripts/.

Exit status: 0, unless the vault or the repo cannot be read.
"""

import argparse
import datetime
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from lib.config import load as load_config  # noqa: E402
from lib.config import origin_describe  # noqa: E402
from lib.frontmatter import parse_frontmatter  # noqa: E402
from lib.projects import PROJECT_FILE, discover  # noqa: E402
from lib.vault_state import classify  # noqa: E402

STATUS_ORDER = {"active": 0, "paused": 1, "closed": 2}

# The section of a feature file that says where that slice of work stands. Same
# heading `build-vault-index.py` takes its features-table excerpt from, so the
# index row and the full section can never describe different sections.
STATE_HEADING = "## state"


def repo_slug(repo):
    """How `repos:` spells this repo — the directory basename, as the vault does."""
    return Path(repo).resolve().name


def read_note(path):
    """(frontmatter, body) for one project or feature file.

    A file whose frontmatter will not parse still yields its body: the body is
    the context the caller came for, and refusing to print it because a
    `tags:` line is malformed would withhold the whole document over a field
    this tool does not read.
    """
    text = path.read_text(encoding="utf-8")
    fm, _ = parse_frontmatter(text)
    fm = fm or {}
    body = text
    if text.startswith("---\n"):
        end = text.find("\n---", 4)
        if end != -1:
            body = text[end + 4:].lstrip("\n")
    repos = fm.get("repos") or []
    if not isinstance(repos, list):
        repos = [repos]
    return {
        "path": path,
        "status": (fm.get("status") or "?").strip(),
        "reviewed": str(fm.get("last-reviewed") or "").strip(),
        "outcome": str(fm.get("outcome") or "").strip(),
        "repos": [str(r).strip() for r in repos if str(r).strip()],
        "body": body.rstrip() + "\n",
    }


def section(body, heading):
    """One `## ...` section of a body, heading line included, or ""."""
    lines = body.splitlines()
    for i, line in enumerate(lines):
        if line.strip().lower() != heading:
            continue
        out = [line]
        for follow in lines[i + 1:]:
            if follow.startswith("## "):
                break
            out.append(follow)
        return "\n".join(out).rstrip() + "\n"
    return ""


def age(reviewed, today):
    """" (N days ago)" for a parseable last-reviewed date, else "".

    The age is stated and no bar is applied. `last-reviewed` is the only field
    that says whether a document still describes the present, and how stale is
    too stale depends on how fast the initiative moves — a threshold invented
    here would be this tool having an opinion it has no evidence for.
    """
    try:
        then = datetime.date.fromisoformat(reviewed)
    except ValueError:
        return ""
    days = (today - then).days
    if days < 0:
        return " (dated in the future)"
    if days == 0:
        return " (today)"
    return f" ({days} day{'s' if days != 1 else ''} ago)"


def matching(vault, slug):
    """Every project this repo appears in, with the features that name it.

    A project matches when its overview names the repo, or when any of its
    features does. Those two are not the same case and are not treated as one:

    - the overview names it -> the initiative is about this repo, so every
      feature under it is in scope
    - only a feature names it -> one slice of somebody else's initiative touches
      this repo, and the other slices do not. Printing them all would hand a
      session context for work in repos it is not in.
    """
    out = []
    for project in discover(vault):
        overview = read_note(project["overview"]) if project["overview"] else None
        features = [read_note(p) for p in project["features"]]
        by_overview = bool(overview and slug in overview["repos"])
        named = [f for f in features if slug in f["repos"]]
        if not by_overview and not named:
            continue
        out.append({
            "slug": project["slug"],
            "flat": project["flat"],
            "context": project["context"],
            "overview": overview,
            "features": features if by_overview else named,
            "whole": by_overview,
        })
    out.sort(key=lambda p: (
        STATUS_ORDER.get(p["overview"]["status"] if p["overview"] else "?", 9),
        p["slug"]))
    return out


def rel(path, vault):
    try:
        return str(path.relative_to(vault))
    except ValueError:
        return str(path)


def print_project(project, vault, today):
    print("=" * 72)
    print(f"PROJECT  {project['slug']}")
    print("=" * 72)
    print()

    overview = project["overview"]
    if overview is None:
        # lib/projects surfaces this rather than skipping it, and so does the
        # index. A directory of features with no overview is half-written, and
        # hiding it would hide the features that brought it here.
        print(f"No {PROJECT_FILE} — this project directory holds features and no")
        print("overview. The features below are all there is to read.")
    else:
        print(f"  file:     {rel(overview['path'], vault)}")
        print(f"  status:   {overview['status']}")
        print(f"  reviewed: {overview['reviewed'] or '—'}"
              f"{age(overview['reviewed'], today)}")
        if overview["repos"]:
            print(f"  repos:    {', '.join(overview['repos'])}")
        print()
        print(overview["body"])

    # Between the stable half and the work in flight, and printed as paths: see
    # the module docstring. Silent when there is none — most projects have no
    # context/, and a "none found" line on every run is noise that teaches a
    # reader to skim past the block on the projects that do.
    if project["context"]:
        print("CONTEXT")
        width = max(len(c.stem) for c in project["context"])
        for path in project["context"]:
            print(f"  {path.stem:<{width}}  {rel(path, vault)}")
        print()
        print("  Read these before writing anything public about the product.")
        print("  Paths only — open the one you need rather than all three.")
        print()

    if not project["whole"] and overview is not None:
        print(f"Only the feature(s) below name this repo — {PROJECT_FILE} names")
        print("others, so the rest of this initiative's work is not shown.")
        print()

    for feature in project["features"]:
        print("-" * 72)
        print(f"FEATURE  {feature['path'].stem}")
        print("-" * 72)
        print(f"  file:     {rel(feature['path'], vault)}")
        line = f"  status:   {feature['status']}"
        if feature["outcome"]:
            line += f" ({feature['outcome']})"
        print(line)
        print(f"  reviewed: {feature['reviewed'] or '—'}"
              f"{age(feature['reviewed'], today)}")
        print()
        state = section(feature["body"], STATE_HEADING)
        if state:
            print(state)
        else:
            print("  (no ## State section — open the file)")
            print()
        print("  Decisions, contested points and open questions are in the"
              " file above.")
        print()


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--repo", required=True, help="repo to report context for")
    ap.add_argument("--vault", help="vault path (default: $SBW_VAULT)")
    args = ap.parse_args()

    cfg = load_config(warn=lambda m: print("warning: %s" % m, file=sys.stderr))
    vault = Path(args.vault).expanduser() if args.vault \
        else Path(cfg["SBW_VAULT"]).expanduser()
    state, message = classify(
        vault, "the --vault flag" if args.vault else origin_describe("SBW_VAULT"))
    if state == "missing":
        sys.exit(message)

    repo = Path(args.repo).expanduser()
    if not repo.is_dir():
        sys.exit("No such repo: %s" % repo)

    slug = repo_slug(repo)
    projects = matching(vault, slug)
    today = datetime.date.today()

    print(f"project context for {slug}  ({repo})")
    print(f"vault: {vault}")
    print()

    if not projects:
        # The common case, and it is not a failure. Said in full rather than
        # left as silence, because "no output" and "the tool did not run" look
        # identical to whoever is reading the transcript.
        if not (vault / "projects").is_dir():
            print("No projects/ directory in this vault — nothing to read.")
        else:
            print("No project doc names this repo.")
        print()
        print("A project doc is for a multi-week initiative, not for every")
        print("repo, so this is the ordinary answer. `make project-candidates`")
        print("reports which initiatives the daily notes already evidence, and")
        print("saying \"backfill project docs\" has update-second-brain draft one.")
        return 0

    total_features = sum(len(p["features"]) for p in projects)
    total_context = sum(len(p["context"]) for p in projects)
    line = f"{len(projects)} project(s), {total_features} feature(s)"
    if total_context:
        line += f", {total_context} context file(s)"
    print(line + ". The overview")
    print("is the stable half — read it first; the features are work in flight.")
    print()
    for project in projects:
        print_project(project, vault, today)

    print("=" * 72)
    print("This is context, not rules. A project doc carries no maturity and")
    print("never promotes — it says what was decided here and why, not what to")
    print("do everywhere. Practices are `practices-for.py`'s job.")
    print("Read-only: changes to any of this go through update-second-brain.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
