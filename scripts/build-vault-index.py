#!/usr/bin/env python3
"""Generate practices/INDEX.md (and projects/INDEX.md) for a second-brain vault.

The index is the hot path into a cold-path vault: an agent reads one file to
learn what notes exist and roughly what each says, then opens only the notes
that matter. Output is deterministic — re-running without vault changes
produces a byte-identical file, so a no-op run is a zero-line diff.

`projects/` gets an index of its own on exactly the same terms, and only once
it holds a note: a vault that has never written a project doc must regenerate
to the bytes it had before this engine knew about them, or every adopter's next
`--check` goes red for a change they did not make. That rule holds one layer
further in — a vault whose projects are all flat `projects/<name>.md` files
regenerates to the bytes it had before this engine knew about feature files.

Usage:
  build-vault-index.py [--vault PATH] [--check]

  --check   exit 1 if an index on disk differs from what would be generated
            (for CI or a pre-commit hook); writes nothing

Vault resolution: --vault, else $SBW_VAULT, else ~/vaults/second-brain
Stdlib only, by design: this must run on a machine with nothing installed.
"""

import argparse
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from lib.config import load as load_config  # noqa: E402
from lib.config import origin_describe  # noqa: E402
from lib.vault_state import classify  # noqa: E402
from lib.frontmatter import parse_frontmatter  # noqa: E402
from lib.markdown import wrapped_code_spans  # noqa: E402
from lib.promotion import application_bars, is_process_note  # noqa: E402
from lib.projects import FEATURES_DIR, PROJECT_FILE, discover  # noqa: E402

GENERATED_BY = "scripts/build-vault-index.py"

# How much of each note's **Rule:** line a row carries.
#
# The row exists to answer one question — is this note worth opening — and the
# reader already has the slug, the tags and the maturity to go on. What the
# excerpt adds is the imperative verb and its object, which is roughly the first
# 80 characters; past that it is paying by the byte for a sentence the reader
# will get in full the moment they open the note.
#
# 140 made the excerpt column 55% of a 57KB file, read on every skill
# invocation. Measured across this vault at 228 notes: 140 -> 59KB, 100 -> 50KB,
# 80 -> 46KB, 70 -> 43KB. 70 was rejected on the rows rather than the number —
# it cuts "never identify them by the artifact a healthy subject produces" to
# "never identify them by the", which is no longer a claim you can judge.
RULE_MAX = 80
MATURITY_ORDER = {"enforced": 0, "trialing": 1, "idea": 2}


def resolve_vault(explicit):
    if explicit:
        return Path(explicit).expanduser()
    cfg = load_config(warn=lambda m: print(f"warning: {m}", file=sys.stderr))
    return Path(cfg["SBW_VAULT"]).expanduser()


def first_sentence(text, limit=RULE_MAX):
    text = " ".join(text.split())
    if len(text) <= limit:
        return text
    cut = text.rfind(" ", 0, limit)
    return text[: cut if cut > 0 else limit].rstrip(" ,;:") + "…"


def extract_body(text):
    """Title from the first H1, summary from the **Rule:** block.

    The rule may sit on the same line as the marker or run over several lines
    as a list, so collect until the next bold marker, heading, or a blank line
    once something has been gathered.
    """
    title = ""
    rule_parts = []
    lines = text.splitlines()
    for i, line in enumerate(lines):
        if not title and line.startswith("# "):
            title = line[2:].strip()
        if line.startswith("**Rule:**"):
            head = line[len("**Rule:**"):].strip()
            if head:
                rule_parts.append(head)
            for follow in lines[i + 1:]:
                stripped = follow.strip()
                if stripped.startswith("**") or stripped.startswith("#"):
                    break
                if not stripped:
                    if rule_parts:
                        break
                    continue
                rule_parts.append(re.sub(r"^(?:[-*]|\d+\.)\s+", "", stripped))
            break
    return title, " ".join(rule_parts).strip()


def cell(value):
    """Escape a value for a markdown table cell."""
    return str(value).replace("|", "\\|").replace("\n", " ")


def collect(vault):
    practices = vault / "practices"
    if not practices.is_dir():
        sys.exit(f"No practices/ directory in {vault}")

    notes, problems = [], []
    for path in sorted(practices.rglob("*.md")):
        if path.name == "INDEX.md":
            continue
        rel = path.relative_to(practices)
        text = path.read_text(encoding="utf-8")
        fm, warnings = parse_frontmatter(text)
        if fm is None:
            problems.append((str(rel), warnings[0]))
            fm = {}
        else:
            for w in warnings:
                problems.append((str(rel), w))

        maturity = fm.get("maturity") or "?"
        if maturity not in MATURITY_ORDER and maturity != "?":
            problems.append((str(rel), f"unknown maturity: {maturity}"))
        for required in ("domain", "maturity", "last-reviewed"):
            if not fm.get(required):
                problems.append((str(rel), f"missing {required}"))

        title, rule = extract_body(text)
        if not title:
            problems.append((str(rel), "no H1 title"))
        if not rule:
            problems.append((str(rel), "no **Rule:** line"))
        for lineno, _ in wrapped_code_spans(text):
            problems.append((str(rel), f"line {lineno}: code span wraps"))

        repos = fm.get("repos") or []
        applications = fm.get("applications") or []
        notes.append(
            {
                "group": rel.parts[0] if len(rel.parts) > 1 else ".",
                "slug": path.stem,
                "title": title or path.stem,
                "maturity": maturity,
                "repos": repos if isinstance(repos, list) else [repos],
                "applications": (
                    applications if isinstance(applications, list) else [applications]
                ),
                # Shared with check-lineage.py via lib/promotion, so the index
                # and the audit cannot disagree about which bar a note is on.
                "process": is_process_note(fm),
                "tags": fm.get("tags") or [],
                "rule": first_sentence(rule) if rule else "",
            }
        )
    return notes, problems


def evidence_cell(note, two_bars=True):
    """The count that gates this note, labelled with which kind it is.

    A bare number was ambiguous once two bars existed: `1` next to a process
    rule read as "observed in one repo, needs two more", when the repo count is
    not what that note is promoted on and never will be. The unit is the part
    that carries the meaning, so it travels with the number.

    A process note with no `applications:` list yet falls back to `N seen` — the
    repos it was observed in, which is real information, marked as not the thing
    it is promoted on. Rendering those as `0` would read as evidence against
    160-odd notes at once, and rendering them as `—` would throw away a count
    the note actually carries. Only a note with nothing recorded at all is `—`:
    nothing counted is a different claim from counted and found nothing.
    """
    # A vault that has not declared the applications bar keeps the column it
    # was built with, bytes and all: `--check` is a drift gate, and an engine
    # upgrade that reformats a generated file turns every adopter's next run
    # red for a change they did not make.
    if not two_bars:
        return str(len(note["repos"]))
    if not note["process"]:
        return f"{len(note['repos'])} repos"
    if note["applications"]:
        return f"{len(note['applications'])} applied"
    if note["repos"]:
        return f"{len(note['repos'])} seen"
    return "—"


def render(notes, two_bars=True):
    total = len(notes)
    counts = {}
    for n in notes:
        counts[n["maturity"]] = counts.get(n["maturity"], 0) + 1
    summary = " · ".join(
        f"{counts[m]} {m}"
        for m in sorted(counts, key=lambda k: MATURITY_ORDER.get(k, 9))
    )

    # The legend has to describe the column that is actually rendered, so the
    # two travel together. A vault that has not opted into the second bar keeps
    # the wording it had, byte for byte.
    if two_bars:
        legend = [
            "each lives at `practices/<group>/<note>.md`. `Evidence` is the count",
            "that gates promotion: `N repos` for a scoped rule, which claims to hold",
            "outside where it was found, and `N applied` for a process rule",
            "(`applies-to: \"\"`), which only claims to have kept being right.",
            "`N seen` is a process rule whose applications are not recorded yet — the",
            "repos it turned up in, which do not gate it. `—` is uncounted, not zero.",
        ]
    else:
        legend = [
            "each lives at `practices/<group>/<note>.md`. `repos` is the count of",
            "repos a practice has been observed in — it drives promotion.",
        ]

    out = [
        "# Practices index",
        "",
        f"> Generated by `{GENERATED_BY}` — do not edit by hand.",
        f"> {total} notes · {summary}",
        "",
        "Read this file first. Open a note only when a row below looks relevant;",
        *legend,
        "",
    ]

    for group in sorted({n["group"] for n in notes}):
        rows = [n for n in notes if n["group"] == group]
        rows.sort(key=lambda n: (MATURITY_ORDER.get(n["maturity"], 9), n["slug"]))
        out.append(f"## {group} ({len(rows)})")
        out.append("")
        header = "Evidence" if two_bars else "Repos"
        out.append(f"| Note | Maturity | {header} | Tags | Rule |")
        out.append("|---|---|---|---|---|")
        for n in rows:
            out.append(
                "| [[{slug}]] | {maturity} | {evidence} | {tags} | {rule} |".format(
                    slug=cell(n["slug"]),
                    maturity=cell(n["maturity"]),
                    evidence=evidence_cell(n, two_bars),
                    tags=cell(", ".join(n["tags"])),
                    rule=cell(n["rule"]),
                )
            )
        out.append("")

    return "\n".join(out).rstrip("\n") + "\n"


# --- projects -----------------------------------------------------------
# A fifth kind of vault content: the current state of one multi-week initiative,
# revised in place. Indexed separately from practices/ rather than folded into
# it, because the two answer different questions and are judged on different
# things — a practice note carries a maturity and a promotion bar, and a project
# doc has neither and never will. Mixing them into one table would be the first
# step towards a project doc being read as a rule.
#
# A project is a DIRECTORY, and this reads two levels:
#
#   projects/<project>/_project.md            the stable overview
#   projects/<project>/features/<feature>.md  one file per slice of work
#   projects/<project>.md                     the flat shape, still read
#
# One file per project put the overview and the latest work in the same
# document, and every wrap-up appended the latest slice over the overview a
# fresh session actually reads. The flat form stays supported: it is somebody's
# committed vault content, and an engine upgrade that stopped indexing it would
# be this tool deciding to lose a document.
# The layout itself — which file is the overview, where the features sit, and
# that a flat projects/<name>.md is still a project — lives in lib/projects, so
# the index and project-for.py cannot disagree about what a project is.
# `standing` is for work that recurs and never reaches an end: routine
# dependency upkeep, a quarterly audit, an on-call rotation. It sorts beside
# `active` because it is live, and it is exempt from the closed-with-no-outcome
# check because it will never close. Without it such a duty reads `active`
# forever and `last-reviewed` becomes the only field carrying information —
# while being exactly the "state spans several notes, no single note answers
# where this is now" case a project doc is for.
PROJECT_STATUS_ORDER = {"active": 0, "standing": 1, "paused": 2, "closed": 3}


def extract_tldr(text, limit=RULE_MAX, headings=("## tl;dr",)):
    """The first bullet or line under one of `headings`, for the index row.

    Same job as a practice note's **Rule:** excerpt — enough to decide whether
    to open the document, not a summary of it. Comment blocks are skipped: the
    templates ship explanatory HTML comments and they are not content.
    """
    lines = text.splitlines()
    for i, line in enumerate(lines):
        if line.strip().lower() not in headings:
            continue
        in_comment = False
        for follow in lines[i + 1:]:
            stripped = follow.strip()
            if stripped.startswith("#"):
                break
            if in_comment:
                if "-->" in stripped:
                    in_comment = False
                continue
            if stripped.startswith("<!--"):
                in_comment = "-->" not in stripped
                continue
            if not stripped:
                continue
            return re.sub(r"^(?:[-*]|\d+\.)\s+", "", stripped)
        break
    return ""


def first_h1(text):
    for line in text.splitlines():
        if line.startswith("# "):
            return line[2:].strip()
    return ""


def read_doc(path, rel, problems, summary_headings, required=("status", "last-reviewed")):
    """The fields both a project file and a feature file carry.

    One reader for both, because the two are validated on the same things and a
    second copy is how one of them quietly stops checking `last-reviewed` — the
    only field that says whether a row still describes the present.
    """
    text = path.read_text(encoding="utf-8")
    fm, warnings = parse_frontmatter(text)
    if fm is None:
        problems.append((rel, warnings[0]))
        fm = {}
    else:
        for w in warnings:
            problems.append((rel, w))

    status = fm.get("status") or "?"
    if status not in PROJECT_STATUS_ORDER and status != "?":
        problems.append((rel, f"unknown status: {status}"))
    for field in required:
        if not fm.get(field):
            problems.append((rel, f"missing {field}"))

    title = first_h1(text)
    if not title:
        problems.append((rel, "no H1 title"))
    summary = extract_tldr(text, headings=summary_headings)
    if not summary:
        problems.append((rel, f"no {summary_headings[0].replace('## ', '')} line"))
    # Reported here rather than in a pass of its own, because this function is
    # already the one place both a project overview and a feature file are read.
    for lineno, _ in wrapped_code_spans(text):
        problems.append((rel, f"line {lineno}: code span wraps"))

    repos = fm.get("repos") or []
    return {
        "title": title or path.stem,
        "status": status,
        "reviewed": fm.get("last-reviewed") or "—",
        "outcome": fm.get("outcome") or "",
        "repos": repos if isinstance(repos, list) else [repos],
        "summary": first_sentence(summary) if summary else "",
    }


def collect_features(paths, project_slug, problems):
    """The feature files of one project, sorted by status then slug."""
    out = []
    for path in paths:
        rel = f"{project_slug}/{FEATURES_DIR}/{path.name}"
        doc = read_doc(path, rel, problems, ("## state",))
        # A closed feature with no outcome is the same gap a bare `- [x]` leaves
        # on a follow-up: it says the work left the list and nothing about how.
        if doc["status"] == "closed" and not doc["outcome"]:
            problems.append((rel, "closed with no outcome:"))
        doc["slug"] = path.stem
        doc["link"] = f"{project_slug}/{FEATURES_DIR}/{path.stem}"
        out.append(doc)
    out.sort(key=lambda f: (PROJECT_STATUS_ORDER.get(f["status"], 9), f["slug"]))
    return out


def strays(project_dir):
    """Names of .md files sitting directly in a project directory.

    `_project.md` is the overview; everything else at that level is read by
    nothing. Returns [] for a path that is not a directory, so the flat shape
    passes straight through.
    """
    if not project_dir.is_dir():
        return []
    return [p.name for p in sorted(project_dir.glob("*.md"))
            if p.name != PROJECT_FILE and p.name != "INDEX.md"]


def collect_projects(vault):
    """(projects, problems), or (None, []) when the vault has no projects/ at all."""
    if not (vault / "projects").is_dir():
        return None, []

    notes, problems = [], []
    for project in discover(vault):
        slug = project["slug"]
        # A .md sitting directly in projects/<x>/ is either a misplaced feature
        # or somebody reaching for projects/<repo>/<initiative>.md, which is not
        # a supported shape. Either way the file is read by nothing — not the
        # index, not project-for — and the silence is indistinguishable from an
        # empty directory. Named here for the same reason lib/projects exists.
        for stray in strays(vault / "projects" / slug):
            problems.append((f"{slug}/{stray}",
                             "not read: a project directory holds _project.md, "
                             "features/ and context/ — move it into features/"))
        if project["flat"]:
            # The flat shape. Still read, still indexed, still linked by bare
            # slug — somebody's committed vault content does not stop being
            # indexed because a newer layout exists.
            doc = read_doc(project["overview"], f"{slug}.md", problems,
                           ("## tl;dr",))
            doc["link"] = slug
        elif project["overview"] is None:
            # Named, not skipped. A directory of features with no overview is a
            # half-written project, and dropping it from the index would hide
            # the features too.
            problems.append((slug, f"no {PROJECT_FILE}"))
            doc = {"title": slug, "status": "?", "reviewed": "—",
                   "outcome": "", "repos": [], "summary": ""}
            doc["link"] = f"{slug}/{PROJECT_FILE[:-3]}"
        else:
            doc = read_doc(project["overview"], f"{slug}/{PROJECT_FILE}",
                           problems, ("## tl;dr",))
            doc["link"] = f"{slug}/{PROJECT_FILE[:-3]}"
        doc["slug"] = slug
        doc["features"] = collect_features(project["features"], slug, problems)
        notes.append(doc)
    return notes, problems


def project_cell(note):
    """A wikilink that resolves to one file.

    `[[_project]]` would be ambiguous the moment a vault has two projects, since
    Obsidian resolves a bare wikilink by filename. So a directory project is
    linked by path with the project name as the alias, and a flat doc keeps the
    bare slug it has always had.

    The alias pipe is escaped: this lands in a markdown table cell, where a bare
    `|` starts the next column and would silently break the row.
    """
    if note["link"] == note["slug"]:
        return f"[[{cell(note['slug'])}]]"
    return "[[" + cell(note["link"]) + r"\|" + cell(note["slug"]) + "]]"


def render_projects(notes):
    counts = {}
    for n in notes:
        counts[n["status"]] = counts.get(n["status"], 0) + 1
    summary = " · ".join(
        f"{counts[st]} {st}"
        for st in sorted(counts, key=lambda k: PROJECT_STATUS_ORDER.get(k, 9))
    )
    features = [(n, f) for n in notes for f in n["features"]]
    # A vault whose projects are all flat files regenerates to exactly the bytes
    # it had before this engine knew about feature files — same reasoning as the
    # two-bar column in the practices index, and the same reason an empty
    # projects/ gets no index at all.
    head = [
        "# Projects index",
        "",
        f"> Generated by `{GENERATED_BY}` — do not edit by hand.",
        f"> {len(notes)} initiatives · {summary}"
        + (f" · {len(features)} features" if features else ""),
        "",
        "One row per long-running initiative. These are context documents, not",
        "practices: they are revised in place, they carry no maturity, and none of",
        "them promotes. `Reviewed` is the note's own `last-reviewed` field — the",
        "date somebody last checked it against reality, which is the only thing",
        "that says whether a row still describes the present.",
    ]
    if features:
        head += [
            "",
            "A project is a directory: `_project.md` is the stable overview a fresh",
            "session reads first, and each feature below it is one slice of work,",
            "revised as that slice moves. The overview is what the features table",
            "does not repeat — open a feature for where its own work stands.",
        ]
    out = head + [
        "",
        "| Project | Status | Reviewed | Repos | TL;DR |",
        "|---|---|---|---|---|",
    ]
    ordered = sorted(notes, key=lambda n: (PROJECT_STATUS_ORDER.get(n["status"], 9),
                                           n["slug"]))
    for n in ordered:
        out.append(
            "| {project} | {status} | {reviewed} | {repos} | {tldr} |".format(
                project=project_cell(n),
                status=cell(n["status"]),
                reviewed=cell(n["reviewed"]),
                repos=cell(", ".join(n["repos"])),
                tldr=cell(n["summary"]),
            )
        )

    if features:
        out += [
            "",
            "## Features",
            "",
            "| Project | Feature | Status | Reviewed | State |",
            "|---|---|---|---|---|",
        ]
        # Grouped by project in the same order as the table above, so a reader
        # scanning down finds each project's features together.
        for n in ordered:
            for f in n["features"]:
                status = f["status"]
                if f["outcome"]:
                    status = f"{status} · {f['outcome']}"
                out.append(
                    "| {project} | {feature} | {status} | {reviewed} | {state} |".format(
                        project=cell(n["slug"]),
                        feature="[[" + cell(f["link"]) + r"\|" + cell(f["slug"]) + "]]",
                        status=cell(status),
                        reviewed=cell(f["reviewed"]),
                        state=cell(f["summary"]),
                    )
                )
    return "\n".join(out).rstrip("\n") + "\n"


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--vault", help="vault path (default: $SBW_VAULT)")
    ap.add_argument("--check", action="store_true", help="exit 1 if the index is stale")
    args = ap.parse_args()

    vault = resolve_vault(args.vault)
    state, message = classify(
        vault, "the --vault flag" if args.vault else origin_describe("SBW_VAULT")
    )
    if state == "missing":
        sys.exit(message)

    notes, problems = collect(vault)
    # Opt-in, read from the vault's own promotion map. A vault that has not
    # declared an applications bar has not adopted the two-bar model, and its
    # index must regenerate to the same bytes it had before the engine knew
    # about one.
    two_bars = application_bars(vault, required=False) is not None
    content = render(notes, two_bars)
    index = vault / "practices" / "INDEX.md"

    projects, project_problems = collect_projects(vault)
    problems = problems + [(f"projects/{rel}", p) for rel, p in project_problems]
    # A vault can reach "projects/ holds documents, templates absent" by doing
    # nothing unusual: create the directory by hand, write a doc into it. Both
    # readers key off `repos:` frontmatter rather than layout, so a flat doc
    # works and the gap never surfaces — until a wrap-up is asked to draft from
    # two templates that are not there, reads the vault as flat, and entrenches
    # the un-adopted layout. One command fixes it, and nothing said so.
    if projects:
        missing = [t for t in ("project.md", "feature.md")
                   if not (vault / "_templates" / t).is_file()]
        if missing:
            problems.append((
                "_templates",
                "projects/ holds documents but %s %s missing — run "
                "./scripts/init-vault.sh --path %s --id VAULT_ID --adopt"
                % (", ".join(missing), "is" if len(missing) == 1 else "are",
                   vault)))

    for rel, problem in problems:
        print(f"warning: {rel}: {problem}", file=sys.stderr)

    if args.check:
        rc = 0
        current = index.read_text(encoding="utf-8") if index.exists() else None
        if current == content:
            print(f"{index} is current ({len(notes)} notes)")
        else:
            print(f"{index} is stale — run build-vault-index.py", file=sys.stderr)
            rc = 1
        # An empty (or absent) projects/ has no index and is not stale for
        # lacking one — same reasoning as the two-bar column above.
        if projects:
            pindex = vault / "projects" / "INDEX.md"
            pcurrent = pindex.read_text(encoding="utf-8") if pindex.exists() else None
            if pcurrent == render_projects(projects):
                print(f"{pindex} is current ({len(projects)} initiatives)")
            else:
                print(f"{pindex} is stale — run build-vault-index.py", file=sys.stderr)
                rc = 1
        return rc

    index.write_text(content, encoding="utf-8")
    print(f"Wrote {index} ({len(notes)} notes, {len(problems)} warning(s))")
    if projects:
        pindex = vault / "projects" / "INDEX.md"
        pindex.write_text(render_projects(projects), encoding="utf-8")
        print(f"Wrote {pindex} ({len(projects)} initiatives)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
