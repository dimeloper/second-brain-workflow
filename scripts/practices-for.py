#!/usr/bin/env python3
"""Which vault practice notes apply to a repo and have not been applied there.

The gap this fills. Only `enforced` notes get distilled into rules, and only
rules reach a repo's agent context — so on a vault of ~180 notes, the ~160 at
`idea` or `trialing` are invisible to a repo that was just onboarded. The
knowledge exists and never arrives.

What makes this worth a command rather than a paragraph is the **promotion
delta**. Promotion is driven by `length(repos)`, so applying one note in one new
repo is often the single act that clears a rung — and today that depends on
someone remembering which note was one repo short. This computes it.

Deliberately **reports only**. It never edits the repo and never touches the
vault, for a reason that is not squeamishness: the vault's own rule is that
`trialing` must be *earned by deliberate re-application, not just counted*. A
command that applied a dozen notes in one pass would add a dozen `repos:` entries
and manufacture exactly the evidence the bar exists to measure. Applying one, on
purpose, and recording it through `update-second-brain` is the honest path.

Matching, and its limits — stated because a candidate list that reads as an
authority is worse than none:

  applies-to glob   High confidence. The note names the files it governs, so a
                    match is a real match. Only promoted notes usually have one.
  domain + stack    Everything else. The repo's stack maps to a domain
                    (frontend / backend / app) and every note in that domain is
                    a candidate. Genuinely fuzzy: it says "worth reading", not
                    "applies".
  cross-cutting     EXCLUDED from the domain fallback, and the count of what was
                    excluded is printed. Those notes are process rules that
                    apply everywhere, so including them would bury the
                    repo-specific ones under a hundred lines. One with an
                    `applies-to` glob still matches through the first route.

Read-only. Never writes to the repo or the vault. Stdlib only.

Exit status: 0 always, unless the vault or repo cannot be read, or the promotion
bars cannot be determined — see lib/promotion.py for why that is fatal.
"""

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from lib.config import load as load_config  # noqa: E402
from lib.config import origin_describe  # noqa: E402
from lib.frontmatter import parse_frontmatter  # noqa: E402
from lib.promotion import bars  # noqa: E402
from lib.repo_match import path_matches, repo_files  # noqa: E402
from lib.vault_state import classify  # noqa: E402

# A repo's stack decides which domains are candidates. Keyed on evidence that is
# cheap and unambiguous — a dependency name or a manifest that only one ecosystem
# uses — rather than on file extensions alone, since .ts says nothing about tier.
STACK_MARKERS = (
    # (domain, kind, needles)
    ("app", "dep", ("expo", "react-native")),
    ("app", "file", ("pubspec.yaml",)),
    ("frontend", "dep", ("astro", "next", "@angular/core", "vue", "svelte",
                         "react-dom", "nuxt", "remix")),
    ("frontend", "file", ("astro.config.mjs", "astro.config.ts", "angular.json",
                          "next.config.js", "next.config.mjs", "svelte.config.js")),
    ("backend", "dep", ("fastify", "express", "@nestjs/core", "fastapi",
                        "uvicorn", "django", "flask")),
    ("backend", "file", ("pyproject.toml", "uv.lock", "alembic.ini",
                         "requirements.txt")),
)

MATURITY_ORDER = {"enforced": 0, "trialing": 1, "idea": 2}


def infer_domains(repo, files):
    """Domains worth reading for this repo, with the evidence that chose them."""
    text = ""
    for manifest in ("package.json", "pyproject.toml", "pubspec.yaml"):
        path = repo / manifest
        if path.is_file():
            try:
                text += path.read_text(encoding="utf-8")
            except OSError:
                pass

    names = set(files)
    found = {}
    for domain, kind, needles in STACK_MARKERS:
        for needle in needles:
            hit = needle in text if kind == "dep" else needle in names
            if hit:
                found.setdefault(domain, needle)
                break
    return found


def repo_slug(repo):
    """How `repos:` spells this repo — the directory basename, as the vault does."""
    return Path(repo).resolve().name


def load_notes(vault):
    practices = vault / "practices"
    if not practices.is_dir():
        sys.exit("No practices/ directory in %s" % vault)

    notes = []
    for path in sorted(practices.rglob("*.md")):
        if path.name == "INDEX.md":
            continue
        fm, _ = parse_frontmatter(path.read_text(encoding="utf-8"))
        fm = fm or {}
        repos = fm.get("repos") or []
        if not isinstance(repos, list):
            repos = [repos]
        applies = fm.get("applies-to") or ""
        if isinstance(applies, list):
            applies = ", ".join(applies)
        notes.append({
            "slug": path.stem,
            "domain": (fm.get("domain") or "").strip(),
            "maturity": (fm.get("maturity") or "?").strip(),
            "repos": [str(r).strip() for r in repos if str(r).strip()],
            "globs": [g.strip() for g in str(applies).split(",") if g.strip()],
        })
    return notes


def next_rung(note, trialing_bar, enforced_bar):
    """What one more repo would buy this note, or None.

    Only ever reports the *next* rung. The vault promotes one rung per pass, on
    purpose — `trialing` requires deliberate re-application rather than a count —
    so a note jumping two rungs is not a thing to advertise.
    """
    count = len(note["repos"]) + 1
    if note["maturity"] == "idea" and count >= trialing_bar:
        return "trialing"
    if note["maturity"] == "trialing" and count >= enforced_bar:
        return "enforced"
    return None


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--repo", required=True, help="repo to report against")
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

    trialing_bar, enforced_bar = bars(vault)
    files = repo_files(repo)
    slug = repo_slug(repo)
    domains = infer_domains(repo, files)
    notes = load_notes(vault)

    matched, already, excluded_cross = [], 0, 0
    for note in notes:
        applies_here = False
        why = ""
        if note["globs"]:
            # Name the glob that *actually* matched, not the first one written.
            # The earlier version printed globs[0] regardless, and on the first
            # real run it credited a match to `**/dictionaries/**/*.json` in a
            # repo with no dictionaries at all — the match was genuine (a later
            # glob did it) and the stated reason was false. A report whose
            # reasons cannot be trusted is not a cheaper report, it is a worse
            # one, because the reason is what a reader checks.
            for glob in note["globs"]:
                hits = [f for f in files if path_matches(f, glob)]
                if hits:
                    applies_here = True
                    why = "glob %s (e.g. %s)" % (glob, hits[0])
                    break
        if not applies_here and note["domain"] in domains:
            applies_here = True
            why = "domain %s (%s)" % (note["domain"], domains[note["domain"]])
        elif not applies_here and note["domain"] == "cross-cutting":
            excluded_cross += 1

        if not applies_here:
            continue
        # Already applied here is the whole point of the filter: the report is
        # about what this repo has *not* had, not what the vault contains.
        if slug in note["repos"]:
            already += 1
            continue
        by_glob = why.startswith("glob ")
        matched.append(dict(
            note, why=why, by_glob=by_glob,
            # A promotion claim is only made for a glob match. The domain
            # fallback is a reading suggestion, and "applying this clears
            # ENFORCED" attached to a guess would invite adding a repos: entry
            # on a note that does not govern this repo — corrupting the one
            # measure the whole promotion model rests on. The first real run made
            # the case: an Angular signals note and a Next server-actions note
            # both surfaced for an Astro site purely on domain.
            unlocks=next_rung(note, trialing_bar, enforced_bar) if by_glob else None))

    matched.sort(key=lambda n: (MATURITY_ORDER.get(n["maturity"], 9),
                                -len(n["repos"]), n["slug"]))

    print("practice notes for %s  (%d file(s), stack: %s)"
          % (repo, len(files),
             ", ".join(sorted(domains)) if domains else "not recognised"))
    print("vault: %s   bars: idea->trialing at %d repos, trialing->enforced at %d"
          % (vault, trialing_bar, enforced_bar))
    print()

    by_glob = [n for n in matched if n["by_glob"]]
    by_domain = [n for n in matched if not n["by_glob"]]
    ready = [n for n in by_glob if n["unlocks"]]

    print("Governs files here, not yet applied: %d" % len(by_glob))
    print("  (the note's own applies-to glob matches real files in this repo)")
    for note in by_glob:
        line = "  [%-8s] %-52s %d repo(s)" % (
            note["maturity"], note["slug"], len(note["repos"]))
        if note["unlocks"]:
            line += "  -> applying here clears %s" % note["unlocks"].upper()
        print(line)
        print("      %s" % note["why"])
    print()
    print("Same domain, judgement required: %d" % len(by_domain))
    print("  (matched on domain alone, so no promotion claim is made for these)")
    for note in by_domain:
        print("  [%-8s] %-52s %d repo(s)" % (
            note["maturity"], note["slug"], len(note["repos"])))
    print()
    if ready:
        print("%d of the glob matches would clear a rung if applied here."
              % len(ready))
        print("Check the glob is not merely broad before acting on that: a note")
        print("claiming **/package.json matches every Node repo ever, and the")
        print("rung it would clear is not evidence of anything.")
        print("Applying one is a decision, not a batch: the vault's bar counts")
        print("deliberate re-application, so applying a dozen at once would")
        print("manufacture the evidence it exists to measure. Apply one, then")
        print("record it with the update-second-brain skill.")
    else:
        print("None of them would clear a rung yet.")
    print()
    print("Already applied here (this repo is in their repos:): %d" % already)
    # Named, never silently dropped — the count is the whole disclosure.
    print("Excluded: %d cross-cutting note(s) with no matching glob. They are"
          % excluded_cross)
    print("process rules that apply everywhere, so listing them would bury the")
    print("repo-specific ones. Read them with the obsidian-knowledge-base skill.")
    if not domains:
        print()
        print("NOTE: no stack recognised, so only glob matches are reported.")
        print("Add an applies-to glob to a note, or extend STACK_MARKERS here.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
