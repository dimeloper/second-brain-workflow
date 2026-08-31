#!/usr/bin/env python3
"""Generate practices/INDEX.md (and projects/INDEX.md) for a second-brain vault.

The index is the hot path into a cold-path vault: an agent reads one file to
learn what notes exist and roughly what each says, then opens only the notes
that matter. Output is deterministic — re-running without vault changes
produces a byte-identical file, so a no-op run is a zero-line diff.

`projects/` gets an index of its own on exactly the same terms, and only once
it holds a note: a vault that has never written a project doc must regenerate
to the bytes it had before this engine knew about them, or every adopter's next
`--check` goes red for a change they did not make.

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
from lib.promotion import application_bars, is_process_note  # noqa: E402

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
PROJECT_STATUS_ORDER = {"active": 0, "paused": 1, "closed": 2}


def extract_tldr(text, limit=RULE_MAX):
    """The first bullet or line under `## TL;DR`, for the index row.

    Same job as a practice note's **Rule:** excerpt — enough to decide whether
    to open the document, not a summary of it. Comment blocks are skipped: the
    template ships explanatory HTML comments and they are not content.
    """
    lines = text.splitlines()
    for i, line in enumerate(lines):
        if line.strip().lower() != "## tl;dr":
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


def collect_projects(vault):
    """(notes, problems), or (None, []) when the vault has no projects/ at all."""
    projects = vault / "projects"
    if not projects.is_dir():
        return None, []

    notes, problems = [], []
    for path in sorted(projects.rglob("*.md")):
        if path.name == "INDEX.md":
            continue
        rel = path.relative_to(projects)
        text = path.read_text(encoding="utf-8")
        fm, warnings = parse_frontmatter(text)
        if fm is None:
            problems.append((str(rel), warnings[0]))
            fm = {}
        else:
            for w in warnings:
                problems.append((str(rel), w))

        status = fm.get("status") or "?"
        if status not in PROJECT_STATUS_ORDER and status != "?":
            problems.append((str(rel), f"unknown status: {status}"))
        for required in ("status", "last-reviewed"):
            if not fm.get(required):
                problems.append((str(rel), f"missing {required}"))

        title = ""
        for line in text.splitlines():
            if line.startswith("# "):
                title = line[2:].strip()
                break
        if not title:
            problems.append((str(rel), "no H1 title"))
        tldr = extract_tldr(text)
        if not tldr:
            problems.append((str(rel), "no ## TL;DR line"))

        repos = fm.get("repos") or []
        notes.append(
            {
                "slug": path.stem,
                "title": title or path.stem,
                "status": status,
                "reviewed": fm.get("last-reviewed") or "—",
                "repos": repos if isinstance(repos, list) else [repos],
                "tldr": first_sentence(tldr) if tldr else "",
            }
        )
    return notes, problems


def render_projects(notes):
    counts = {}
    for n in notes:
        counts[n["status"]] = counts.get(n["status"], 0) + 1
    summary = " · ".join(
        f"{counts[st]} {st}"
        for st in sorted(counts, key=lambda k: PROJECT_STATUS_ORDER.get(k, 9))
    )
    out = [
        "# Projects index",
        "",
        f"> Generated by `{GENERATED_BY}` — do not edit by hand.",
        f"> {len(notes)} initiatives · {summary}",
        "",
        "One row per long-running initiative. These are context documents, not",
        "practices: they are revised in place, they carry no maturity, and none of",
        "them promotes. `Reviewed` is the note's own `last-reviewed` field — the",
        "date somebody last checked it against reality, which is the only thing",
        "that says whether a row still describes the present.",
        "",
        "| Project | Status | Reviewed | Repos | TL;DR |",
        "|---|---|---|---|---|",
    ]
    for n in sorted(notes, key=lambda n: (PROJECT_STATUS_ORDER.get(n["status"], 9),
                                          n["slug"])):
        out.append(
            "| [[{slug}]] | {status} | {reviewed} | {repos} | {tldr} |".format(
                slug=cell(n["slug"]),
                status=cell(n["status"]),
                reviewed=cell(n["reviewed"]),
                repos=cell(", ".join(n["repos"])),
                tldr=cell(n["tldr"]),
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
