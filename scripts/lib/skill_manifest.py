#!/usr/bin/env python3
"""Parse and validate a skill-source manifest, and resolve it to skill dirs.

The manifest declares *third-party* skill sources — someone else's repo of
skills you want installed alongside this engine's own. It lives outside this
repo, next to `rules/` in whatever private content repo a machine points at, for
the same reason `rules/` here ships empty: a public engine that shipped a
curated roster of another person's skills would be shipping an opinion.

    {
      "sources": [
        {
          "name": "emil",
          "repo": "https://github.com/emilkowalski/skills",
          "ref": "<40-char sha>",
          "skills_subdir": "skills",
          "allow": ["animate", "review-animations"]
        }
      ]
    }

`allow` is required and per-source. Installing a source wholesale is not
offered: every skill in it is charged against the same session budget as your
own, and the one time that was decided by default (the vendored obsidian set)
the right answer turned out to be three of six.

Why validation is strict about unknown keys: a manifest is a plain mapping, so a
misspelled key is not an error anywhere — it is just a key nobody reads.
`"alow": [...]` would parse, install nothing, and look right in a diff. That is
the same failure `check-rules.py` exists to catch for rule frontmatter, and the
same reasoning applies, so the same answer does too.

Division of labour with sync-skills.sh: everything here is parse, validate and
resolve. *Policy* — which findings are fatal, what the operator is told to run —
is the shell caller's, exactly as lib/vault_state.py leaves severity to
vault-state.sh. `resolve` therefore exits 0 while reporting a source that has
not been fetched; only a manifest that cannot be trusted exits non-zero.

Exit status (CLI):
  0  manifest read and resolved, or no manifest configured at all
  2  the manifest exists but cannot be trusted — unreadable, not JSON, or
     failing any check below. Nothing is resolved, because a manifest with one
     bad source tells you nothing reliable about the others.
"""

import argparse
import json
import os
import re
import sys
from pathlib import Path

SOURCE_KEYS_REQUIRED = ("name", "repo", "allow")
# "//" is the conventional JSON comment key, and it is accepted rather than
# rejected so the shipped skills.json.example can carry its own instructions and
# still be a valid manifest. An example that has to be edited before it parses is
# an example whose first run fails for a reason that has nothing to do with the
# reader's own mistake.
SOURCE_KEYS_OPTIONAL = ("ref", "skills_subdir", "//", "applies_to", "license")


# Any key starting with "//" is a comment and is ignored, at every level. JSON has
# no comment syntax, and a roster of other people's skills is exactly the kind of
# file that needs prose — the reason each one is in or out is the part that decays
# fastest. A single "//" key would allow one note per object; a prefix allows one
# per section, which is how the shipped example is written. A typo still fails,
# because a typo does not begin with two slashes.
def _is_comment(key):
    return isinstance(key, str) and key.startswith("//")
SOURCE_KEYS = SOURCE_KEYS_REQUIRED + SOURCE_KEYS_OPTIONAL
TOP_KEYS = ("sources", "candidates", "//")

# A candidate is a skill you have *not* adopted, recorded so onboarding can
# mention it. `when` is required and `repo` is required; `install` is optional
# because some candidates are adopted by editing this file rather than by running
# anything, and the reporter says so when it is absent.
CANDIDATE_KEYS_REQUIRED = ("name", "repo", "when")
CANDIDATE_KEYS_OPTIONAL = ("install", "applies_to", "//", "license")
CANDIDATE_KEYS = CANDIDATE_KEYS_REQUIRED + CANDIDATE_KEYS_OPTIONAL

# The ref the example ships. Refused outright rather than warned about: it is a
# well-formed sha, so nothing downstream would question it, and the failure it
# produces is a git error about an unknown object several steps later — which
# reads as a broken source rather than as "you did not fill this in".
PLACEHOLDER_REFS = ("0" * 40,)

DEFAULT_SKILLS_SUBDIR = "skills"

# A full sha, not a prefix: an abbreviated one is ambiguous in a repo you do not
# control and grows ambiguous over time in one you do.
FULL_SHA = re.compile(r"^[0-9a-f]{40}$")

# Source names become directory names under vendor/external/, so they are held
# to what is safe as a single path segment rather than to what JSON allows.
SAFE_NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")


class ManifestError(Exception):
    """A manifest that cannot be trusted. The message is the operator's."""


def _require_mapping(value, what):
    if not isinstance(value, dict):
        raise ManifestError("%s must be a JSON object, got %s" % (what, _kind(value)))


def _kind(value):
    if value is None:
        return "null"
    return {bool: "a boolean", int: "a number", float: "a number",
            str: "a string", list: "an array", dict: "an object"}.get(
                type(value), type(value).__name__)


def _unknown_key_message(key, known, where):
    """Name the closest legal key. A misspelling is the failure mode here, and
    'unknown key' alone leaves the reader diffing against documentation."""
    import difflib
    near = difflib.get_close_matches(key, known, n=1, cutoff=0.6)
    hint = " (did you mean '%s'?)" % near[0] if near else ""
    return "%s: unknown key '%s'%s — allowed: %s" % (
        where, key, hint, ", ".join(known))


def parse(text, origin="manifest"):
    """Validate `text` as a manifest and return its list of sources.

    Every check is a hard error. Warnings are returned separately so the caller
    decides whether to print them; nothing here writes to stderr.
    """
    try:
        data = json.loads(text)
    except ValueError as exc:
        raise ManifestError("%s: not valid JSON: %s" % (origin, exc))

    _require_mapping(data, origin)
    for key in data:
        if _is_comment(key):
            continue
        if key not in TOP_KEYS:
            raise ManifestError(_unknown_key_message(key, TOP_KEYS, origin))

    if "sources" not in data:
        raise ManifestError("%s: no 'sources' key — an empty roster is "
                            '\'{"sources": []}\', not an empty file' % origin)
    if not isinstance(data["sources"], list):
        raise ManifestError("%s: 'sources' must be an array, got %s"
                           % (origin, _kind(data["sources"])))

    sources = []
    warnings = []
    seen_names = {}
    seen_skills = {}

    for index, raw in enumerate(data["sources"]):
        where = "%s: sources[%d]" % (origin, index)
        _require_mapping(raw, where)

        for key in raw:
            if _is_comment(key):
                continue
            if key not in SOURCE_KEYS:
                raise ManifestError(_unknown_key_message(key, SOURCE_KEYS, where))
        for key in SOURCE_KEYS_REQUIRED:
            if key not in raw:
                raise ManifestError("%s: missing required key '%s'" % (where, key))

        name = raw["name"]
        if not isinstance(name, str) or not SAFE_NAME.match(name):
            raise ManifestError(
                "%s: 'name' must be a single safe path segment "
                "(letters, digits, dot, dash, underscore), got %r"
                % (where, name))
        if name in seen_names:
            raise ManifestError(
                "%s: duplicate source name '%s', already used by sources[%d] — "
                "names become directories under vendor/external/, so two "
                "sources sharing one would fetch over each other"
                % (where, name, seen_names[name]))
        seen_names[name] = index

        repo = raw["repo"]
        if not isinstance(repo, str) or not repo.strip():
            raise ManifestError("%s: 'repo' must be a non-empty string" % where)

        ref = raw.get("ref", "")
        if not isinstance(ref, str) or not ref.strip():
            raise ManifestError(
                "%s: 'ref' is required — an unpinned source installs whatever "
                "its default branch happens to hold today, so two machines "
                "reading the same manifest would not get the same skills"
                % where)
        if ref.strip() in PLACEHOLDER_REFS:
            raise ManifestError(
                "%s: 'ref' is still the placeholder from skills.json.example — "
                "replace it with the sha you actually want pinned "
                "(git ls-remote %s HEAD)" % (where, repo.strip()))
        if not FULL_SHA.match(ref.strip()):
            warnings.append(
                "%s: ref '%s' is not a full 40-character sha, so what it points "
                "at can move under you" % (where, ref.strip()))

        allow = raw["allow"]
        if not isinstance(allow, list):
            raise ManifestError("%s: 'allow' must be an array, got %s"
                               % (where, _kind(allow)))
        for entry in allow:
            if not isinstance(entry, str) or not entry.strip():
                raise ManifestError(
                    "%s: 'allow' holds a blank or non-string entry (%r)"
                    % (where, entry))
            skill = entry.strip()
            if skill in seen_skills:
                raise ManifestError(
                    "%s: skill '%s' is also allowed by source '%s' — skills "
                    "install by name into one flat directory, so two sources "
                    "offering the same name have no resolution order"
                    % (where, skill, seen_skills[skill]))
            seen_skills[skill] = name

        # Absent is a warning, not an error. You are installing someone else's
        # content into every session on this machine, and "what am I allowed to
        # do with this" is a question that gets asked once and then never again —
        # which is precisely the kind that wants a mechanical prompt. Not fatal,
        # because the answer is a judgement the operator makes, not one this
        # script can make for them.
        license_ = _license(raw.get("license"), where)
        if not license_:
            warnings.append(
                "%s: no 'license' recorded for '%s' (%s). Check it before "
                "adopting — an unlicensed repo is all-rights-reserved by default"
                % (where, name, repo.strip()))

        subdir = raw.get("skills_subdir", DEFAULT_SKILLS_SUBDIR)
        if not isinstance(subdir, str) or not subdir.strip():
            raise ManifestError(
                "%s: 'skills_subdir' must be a non-empty string; omit the key "
                "to use the default '%s'" % (where, DEFAULT_SKILLS_SUBDIR))

        sources.append({
            "name": name,
            "repo": repo.strip(),
            "ref": ref.strip(),
            "skills_subdir": subdir.strip().strip("/"),
            "allow": [entry.strip() for entry in allow],
            "applies_to": _globs(raw.get("applies_to"), where),
            "license": license_,
        })

    candidates = _parse_candidates(data.get("candidates"), origin, seen_skills)
    return sources, candidates, warnings


def _license(value, where):
    """Optional free text — an SPDX id, or a sentence about why there isn't one."""
    if value is None:
        return ""
    if not isinstance(value, str) or not value.strip():
        raise ManifestError(
            "%s: 'license' must be a non-empty string; omit the key if you have "
            "not checked yet, which warns rather than passing silently" % where)
    return value.strip()


def _globs(value, where):
    """An optional list of path globs. Absent means 'relevant everywhere'."""
    if value is None:
        return []
    if not isinstance(value, list):
        raise ManifestError("%s: 'applies_to' must be an array of globs, got %s"
                           % (where, _kind(value)))
    out = []
    for entry in value:
        if not isinstance(entry, str) or not entry.strip():
            raise ManifestError("%s: 'applies_to' holds a blank or non-string glob (%r)"
                               % (where, entry))
        out.append(entry.strip())
    return out


def _parse_candidates(value, origin, adopted_skills):
    """Skills deliberately *not* adopted, recorded so onboarding can mention them.

    The gap this fills is one the host cannot: an agent routes to the skills that
    are installed, and can say nothing about one that exists and is not. That is
    knowledge only the person keeping the roster has, so it lives here beside the
    roster rather than being inferred.
    """
    if value is None:
        return []
    if not isinstance(value, list):
        raise ManifestError("%s: 'candidates' must be an array, got %s"
                           % (origin, _kind(value)))

    candidates = []
    seen = {}
    for index, raw in enumerate(value):
        where = "%s: candidates[%d]" % (origin, index)
        _require_mapping(raw, where)
        for key in raw:
            if _is_comment(key):
                continue
            if key not in CANDIDATE_KEYS:
                raise ManifestError(_unknown_key_message(key, CANDIDATE_KEYS, where))
        for key in CANDIDATE_KEYS_REQUIRED:
            if key not in raw:
                raise ManifestError("%s: missing required key '%s'" % (where, key))

        name = raw["name"]
        if not isinstance(name, str) or not name.strip():
            raise ManifestError("%s: 'name' must be a non-empty string" % where)
        name = name.strip()
        if name in seen:
            raise ManifestError("%s: duplicate candidate '%s', already at candidates[%d]"
                               % (where, name, seen[name]))
        # Adopted and merely-a-candidate are contradictory states, and the
        # contradiction is silent: onboarding would suggest installing something
        # already linked. Caught here rather than left to read oddly in a report.
        if name in adopted_skills:
            raise ManifestError(
                "%s: '%s' is listed as a candidate but source '%s' already allows "
                "it — a skill cannot be both adopted and merely suggested"
                % (where, name, adopted_skills[name]))
        seen[name] = index

        for key in ("repo", "when"):
            if not isinstance(raw[key], str) or not raw[key].strip():
                raise ManifestError("%s: '%s' must be a non-empty string" % (where, key))

        install = raw.get("install", "")
        if not isinstance(install, str):
            raise ManifestError("%s: 'install' must be a string" % where)

        candidates.append({
            "license": _license(raw.get("license"), where),
            "name": name,
            "repo": raw["repo"].strip(),
            "when": raw["when"].strip(),
            "install": install.strip(),
            "applies_to": _globs(raw.get("applies_to"), where),
        })
    return candidates


def manifest_path(flag=None, cfg=None):
    """Resolve which manifest to read, mirroring render.py's rules precedence:
    flag, then environment, then config file, then none.

    Returns None when nothing is configured — the state a fresh clone is in and
    stays in, not an error.
    """
    if flag:
        return Path(os.path.expanduser(flag))
    env = os.environ.get("SBW_SKILLS_MANIFEST")
    if env is not None:
        # Set-but-empty is a deliberate "none", not a request for the default —
        # the same reading lib/config.sh gives every other key.
        return Path(os.path.expanduser(env)) if env.strip() else None
    if cfg:
        value = cfg.get("SBW_SKILLS_MANIFEST", "")
        if value.strip():
            return Path(os.path.expanduser(value))
    return None


def load(flag=None, cfg=None):
    """(path, sources, candidates, warnings). path is None when unconfigured."""
    path = manifest_path(flag, cfg)
    if path is None:
        return None, [], [], []
    if not path.is_file():
        raise ManifestError(
            "%s: no such file. This is where the skill roster is expected "
            "because SBW_SKILLS_MANIFEST points here; unset it to run with "
            "workflow skills only." % path)
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as exc:
        raise ManifestError("%s: cannot read: %s" % (path, exc))
    sources, candidates, warnings = parse(text, origin=str(path))
    return path, sources, candidates, warnings


def source_root(engine, source):
    """Where fetch-skill-sources.sh puts this source's checkout.

    Gitignored on purpose: these are pins, not content. Recording them in the
    engine's own history — as a submodule would — is what puts a personal roster
    in a public repo.
    """
    return Path(engine) / "vendor" / "external" / source["name"]


def resolve(engine, sources):
    """One row per allowed skill: (status, name, path, source_name).

    status is 'ok', 'missing-source' (nothing fetched yet) or 'missing-skill'
    (fetched, but the source does not carry that skill under its subdir — a
    rename upstream, or a typo in `allow`). Severity is the caller's call.
    """
    rows = []
    for source in sources:
        root = source_root(engine, source)
        skills_dir = root / source["skills_subdir"]
        for skill in source["allow"]:
            target = skills_dir / skill
            if not root.is_dir():
                status = "missing-source"
            elif not target.is_dir():
                status = "missing-skill"
            else:
                status = "ok"
            rows.append((status, skill, str(target), source["name"]))
    return rows


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


def relevant(entries, files):
    """Split entries into (matched, unscoped, unmatched) against a repo's files.

    Three buckets, not two. An entry with no `applies_to` is *unscoped* — it was
    never claimed to be repo-specific, so reporting it as "does not apply here"
    would be an assertion nobody made. Keeping it separate is what stops an
    unscoped entry being read as either a match or a miss.
    """
    matched, unscoped, unmatched = [], [], []
    for entry in entries:
        globs = entry.get("applies_to") or []
        if not globs:
            unscoped.append(entry)
            continue
        hits = [f for f in files if any(path_matches(f, g) for g in globs)]
        if hits:
            matched.append(dict(entry, matched_by=hits[:3]))
        else:
            unmatched.append(entry)
    return matched, unscoped, unmatched


def _main(argv):
    parser = argparse.ArgumentParser(
        description="Parse, validate and resolve a skill-source manifest.")
    parser.add_argument("mode", choices=("resolve", "validate", "sources", "relevant"))
    parser.add_argument("--repo", default=None,
                        help="repo to judge relevance against (relevant mode)")
    parser.add_argument("--engine", default=str(Path(__file__).resolve().parent.parent.parent),
                        help="engine checkout, where vendor/external/ lives")
    parser.add_argument("--manifest", default=None,
                        help="manifest path, overriding env and config")
    args = parser.parse_args(argv)

    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
    from lib.config import load as load_config  # noqa: E402

    try:
        path, sources, candidates, warnings = load(args.manifest, load_config())
    except ManifestError as exc:
        sys.stderr.write("error: %s\n" % exc)
        return 2

    for warning in warnings:
        sys.stderr.write("warning: %s\n" % warning)

    if path is None:
        return 0

    if args.mode == "validate":
        print("%s: %d source(s), %d skill(s) allowed, %d candidate(s)"
              % (path, len(sources), sum(len(s["allow"]) for s in sources),
                 len(candidates)))
        return 0

    if args.mode == "relevant":
        if not args.repo:
            sys.stderr.write("error: relevant mode needs --repo\n")
            return 2
        return _report_relevant(args.repo, sources, candidates)

    if args.mode == "sources":
        # Tab-separated for the fetch script: name, repo, ref, checkout dir.
        for source in sources:
            print("\t".join([source["name"], source["repo"], source["ref"],
                             str(source_root(args.engine, source))]))
        return 0

    for row in resolve(args.engine, sources):
        print("\t".join(row))
    return 0


def _report_relevant(repo, sources, candidates):
    """Human-readable, for onboard-repo to read out. Not machine-parsed.

    Adopted skills are flattened out of their sources because relevance is a
    property of the skill, not of the repo it happened to come from — an
    onboarding reader wants "use `animate` here", not "source emil is relevant".
    """
    repo = Path(repo).expanduser()
    if not repo.is_dir():
        sys.stderr.write("error: no such repo: %s\n" % repo)
        return 2
    files = repo_files(repo)

    adopted = []
    for source in sources:
        for skill in source["allow"]:
            adopted.append({"name": skill, "applies_to": source["applies_to"],
                            "source": source["name"]})

    a_match, a_unscoped, _ = relevant(adopted, files)
    c_match, c_unscoped, _ = relevant(candidates, files)

    print("skills relevant to %s  (%d file(s) considered)" % (repo, len(files)))
    print()
    print("Adopted and scoped to this repo: %d" % len(a_match))
    for entry in a_match:
        print("  - %s  (matched %s)" % (entry["name"], ", ".join(entry["matched_by"])))
    if a_unscoped:
        # Named, never dropped: an unscoped skill is available everywhere, and a
        # report that listed only the scoped matches would read as the full set.
        print("  (%d adopted skill(s) declare no applies_to, so they apply "
              "everywhere: %s)" % (len(a_unscoped),
                                   ", ".join(e["name"] for e in a_unscoped)))
    print()
    print("Not adopted, worth considering here: %d" % len(c_match))
    for entry in c_match:
        print("  - %s — %s" % (entry["name"], entry["when"]))
        print("      %s%s" % (entry["repo"],
                              "  [%s]" % entry["license"] if entry["license"] else
                              "  [license not recorded]"))
        print("      install: %s" % (entry["install"] or
                                     "add it to skills.json sources, then "
                                     "make fetch-skills YES=1 && make sync-skills"))
    for entry in c_unscoped:
        print("  - %s — %s (no applies_to; relevance is yours to judge)"
              % (entry["name"], entry["when"]))
    return 0


if __name__ == "__main__":
    sys.exit(_main(sys.argv[1:]))
