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

An `allow` entry may be a bare skill name or an object carrying its own
`applies_to` and `license`:

    "allow": ["a11y-audit", {"name": "screenshot",
                             "applies_to": ["**/next.config.*"]}]

`ref`, `applies_to` and `license` attach to a *source*; what gets allowlisted,
linked and reasoned about is a *skill*. Where a source's skills do not share one
answer — a twelve-skill repo of which three are Next.js-specific — a source-level
scope can only state something untrue in one direction or the other. An entry's
value **replaces** the source's rather than merging, because the case this exists
for is narrowing, and a merge can only widen, which omitting the key already
does.

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

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from lib.repo_match import repo_files, path_matches  # noqa: E402,F401

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

# An `allow` entry. A bare string coerces to {"name": ...} — the same coercion
# `source:` and `repos:` already do on the note side, so every manifest written
# before this existed parses unchanged and means exactly what it meant.
ALLOW_ENTRY_KEYS_REQUIRED = ("name",)
ALLOW_ENTRY_KEYS_OPTIONAL = ("applies_to", "license", "//")
ALLOW_ENTRY_KEYS = ALLOW_ENTRY_KEYS_REQUIRED + ALLOW_ENTRY_KEYS_OPTIONAL

# A candidate is a skill you have *not* adopted, recorded so onboarding can
# mention it. `when` is required and `repo` is required; `install` is optional
# because some candidates are adopted by editing this file rather than by running
# anything, and the reporter says so when it is absent.
CANDIDATE_KEYS_REQUIRED = ("name", "repo", "when")
CANDIDATE_KEYS_OPTIONAL = ("install", "applies_to", "//", "license", "status")

# A candidate's standing. "suggested" is the default and the only one that gets
# pitched by the relevance report; the other two are *decisions already made*.
#
# They are kept in the same list rather than deleted, because the value of a
# rejected option is the reason it was rejected — delete the entry and the next
# session re-evaluates from scratch and may well reach a different answer for no
# new reason. And "adopted" exists because a skill installed the vendor's own way
# (its own installer, a real directory sync-skills.sh refuses to touch) is
# genuinely adopted while never appearing in any source's allow list, so without
# it the roster cannot describe the installed set.
CANDIDATE_STATUSES = ("suggested", "adopted", "declined")
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

        source_license = _license(raw.get("license"), where)
        source_globs = _globs(raw.get("applies_to"), where)

        entries = _parse_allow(raw["allow"], where, name, source_globs,
                               source_license)
        for entry in entries:
            skill = entry["name"]
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
        #
        # One warning per *source*, never one per skill. A twelve-skill source
        # that records no license is one unanswered question, not twelve, and
        # turning one line into twelve is a regression in noise for no new
        # information. An entry that overrides is licensed and does not
        # contribute; a source whose every entry overrides is fully answered and
        # says nothing.
        if not source_license and (not entries or
                                   any(not e["license"] for e in entries)):
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
            "allow": entries,
            "applies_to": source_globs,
            "license": source_license,
        })

    candidates, candidate_warnings = _parse_candidates(
        data.get("candidates"), origin, seen_skills)
    return sources, candidates, warnings + candidate_warnings


def _license(value, where):
    """Optional free text — an SPDX id, or a sentence about why there isn't one."""
    if value is None:
        return ""
    if not isinstance(value, str) or not value.strip():
        raise ManifestError(
            "%s: 'license' must be a non-empty string; omit the key if you have "
            "not checked yet, which warns rather than passing silently" % where)
    return value.strip()


def _globs(value, where, empty_ok=True):
    """An optional list of path globs. Absent means 'relevant everywhere'."""
    if value is None:
        return []
    if not isinstance(value, list):
        raise ManifestError("%s: 'applies_to' must be an array of globs, got %s"
                           % (where, _kind(value)))
    if not value and not empty_ok:
        # Same reason a blank `license` is an error at the source level: it looks
        # answered and is not. An omitted key at least has a defined meaning here
        # — inherit — and the two things it might have meant are different
        # enough that guessing either one would be wrong.
        raise ManifestError(
            "%s: 'applies_to' is an empty array, which says nothing. Omit the "
            "key to inherit the source's scope, or list the globs this skill "
            "applies to" % where)
    out = []
    for entry in value:
        if not isinstance(entry, str) or not entry.strip():
            raise ManifestError("%s: 'applies_to' holds a blank or non-string glob (%r)"
                               % (where, entry))
        out.append(entry.strip())
    return out


def _parse_allow(value, where, source_name, source_globs, source_license):
    """Resolve a source's `allow` list into one record per adopted skill.

    Each record carries the scope and licence that actually govern that skill,
    and where each came from. The origin is not bookkeeping: a wrong scope
    inherited from a source is otherwise indistinguishable in a report from one
    declared on the entry, and those have different fixes — one edits the source,
    the other edits the entry.
    """
    if not isinstance(value, list):
        raise ManifestError("%s: 'allow' must be an array, got %s"
                           % (where, _kind(value)))

    entries = []
    for index, raw in enumerate(value):
        if isinstance(raw, str):
            if not raw.strip():
                raise ManifestError(
                    "%s: 'allow' holds a blank entry at [%d]" % (where, index))
            raw = {"name": raw}
        elif not isinstance(raw, dict):
            raise ManifestError(
                "%s: 'allow'[%d] must be a skill name or an object with a "
                "'name', got %s" % (where, index, _kind(raw)))

        at = "%s: allow[%d]" % (where, index)
        for key in raw:
            if _is_comment(key):
                continue
            if key not in ALLOW_ENTRY_KEYS:
                raise ManifestError(
                    _unknown_key_message(key, ALLOW_ENTRY_KEYS, at))
        if "name" not in raw:
            raise ManifestError(
                "%s: missing required key 'name' — an allow entry under source "
                "'%s' has to say which skill it is about" % (at, source_name))

        skill = raw["name"]
        if not isinstance(skill, str) or not skill.strip():
            raise ManifestError("%s: 'name' must be a non-empty string" % at)

        # Replace, never merge. The case per-entry scope exists for is
        # *narrowing* — three Next-only skills inside a repo of twelve — and a
        # merge can only ever widen, which is the direction omitting the key
        # already covers.
        if "applies_to" in raw:
            globs, scope_origin = _globs(raw["applies_to"], at, empty_ok=False), "entry"
        elif source_globs:
            globs, scope_origin = list(source_globs), "source"
        else:
            globs, scope_origin = [], ""

        entry_license = _license(raw.get("license"), at)
        if entry_license:
            license_origin = "entry"
        elif source_license:
            entry_license, license_origin = source_license, "source"
        else:
            license_origin = ""

        entries.append({
            "name": skill.strip(),
            "applies_to": globs,
            "scope_origin": scope_origin,
            "license": entry_license,
            "license_origin": license_origin,
        })
    return entries


def _parse_candidates(value, origin, adopted_skills):
    """Skills deliberately *not* adopted, recorded so onboarding can mention them.

    The gap this fills is one the host cannot: an agent routes to the skills that
    are installed, and can say nothing about one that exists and is not. That is
    knowledge only the person keeping the roster has, so it lives here beside the
    roster rather than being inferred.

    Returns (candidates, warnings).
    """
    if value is None:
        return [], []
    if not isinstance(value, list):
        raise ManifestError("%s: 'candidates' must be an array, got %s"
                           % (origin, _kind(value)))

    candidates = []
    warnings = []
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
        seen[name] = index

        for key in ("repo", "when"):
            if not isinstance(raw[key], str) or not raw[key].strip():
                raise ManifestError("%s: '%s' must be a non-empty string" % (where, key))

        # Read before the overlap check below, which is decided by it.
        status = raw.get("status", "suggested")
        if not isinstance(status, str) or status.strip() not in CANDIDATE_STATUSES:
            raise ManifestError(
                "%s: 'status' must be one of %s, got %r"
                % (where, ", ".join(CANDIDATE_STATUSES), status))
        status = status.strip()

        # Overlap with a source's allow list. One rule keyed on *presence* was
        # right while every candidate was a pitch; `status` made the same overlap
        # mean three different things, and only one of them is a contradiction.
        #
        # Its original justification named two faults — contradictory states, and
        # onboarding suggesting something already linked — and `status` falsified
        # both for `adopted`: that is one fact recorded twice, and only
        # `suggested` is ever pitched. An error naming a fault the file does not
        # have is the shape that points the reader at the wrong fix.
        if name in adopted_skills:
            if status == "suggested":
                raise ManifestError(
                    "%s: '%s' is listed as a candidate but source '%s' already allows "
                    "it — a skill cannot be both adopted and merely suggested"
                    % (where, name, adopted_skills[name]))
            if status == "declined":
                # Declined yet linked, and pitched yet linked, are different
                # faults with different fixes: this one means the decline was
                # never carried out, not that the roster contradicts itself.
                raise ManifestError(
                    "%s: '%s' is recorded as declined, yet source '%s' allows it, so it "
                    "is linked into every session anyway. Drop the allow entry to carry "
                    "the decline out, or change the status to say it was reversed"
                    % (where, name, adopted_skills[name]))
            # `adopted` warns rather than refusing: the duplication is harmless
            # today and rots tomorrow. Drop the skill from `allow` and the
            # candidate still claims adopted, with nothing anywhere reconciling
            # the two — so the warning has to say which record is load-bearing.
            warnings.append(
                "%s: '%s' is recorded twice — source '%s' allows it, and this candidate "
                "calls it adopted. The allow entry is what linking reads; the candidate "
                "is only descriptive. Delete one, or the day the allow entry goes the "
                "candidate will still claim adopted"
                % (where, name, adopted_skills[name]))

        install = raw.get("install", "")
        if not isinstance(install, str):
            raise ManifestError("%s: 'install' must be a string" % where)

        candidates.append({
            "license": _license(raw.get("license"), where),
            "status": status,
            "name": name,
            "repo": raw["repo"].strip(),
            "when": raw["when"].strip(),
            "install": install.strip(),
            "applies_to": _globs(raw.get("applies_to"), where),
        })
    return candidates, warnings


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
        for entry in source["allow"]:
            skill = entry["name"]
            target = skills_dir / skill
            if not root.is_dir():
                status = "missing-source"
            elif not target.is_dir():
                status = "missing-skill"
            else:
                status = "ok"
            rows.append((status, skill, str(target), source["name"]))
    return rows


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
    from lib.config import load as load_config, origin_describe  # noqa: E402

    try:
        path, sources, candidates, warnings = load(args.manifest, load_config())
    except ManifestError as exc:
        sys.stderr.write("error: %s\n" % exc)
        return 2

    for warning in warnings:
        sys.stderr.write("warning: %s\n" % warning)

    origin = ("the --manifest flag" if args.manifest
              else origin_describe("SBW_SKILLS_MANIFEST"))

    if path is None:
        # Said, not left silent — but only in the two modes a person reads.
        # `resolve` and `sources` are parsed by shell callers, and a courtesy
        # line on stdout there would be read as a row.
        #
        # An empty report and an unread roster look identical, and they have
        # different next actions: one means nothing here is relevant, the other
        # means nothing was consulted. Naming the key is what separates them.
        if args.mode in ("relevant", "validate"):
            print("no skills manifest configured — skill roster skipped (%s)"
                  % origin)
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
        return _report_relevant(args.repo, sources, candidates, path, origin)

    if args.mode == "sources":
        # Tab-separated for the fetch script: name, repo, ref, checkout dir.
        for source in sources:
            print("\t".join([source["name"], source["repo"], source["ref"],
                             str(source_root(args.engine, source))]))
        return 0

    for row in resolve(args.engine, sources):
        print("\t".join(row))
    return 0


def _scope_origin_phrase(entry):
    """Where the globs that matched came from. Mirrors ds_origin_describe's job
    for config keys: name the knob, so the reader edits the right one."""
    if entry.get("scope_origin") == "entry":
        return "scope from this entry"
    if entry.get("scope_origin") == "source":
        return "scope inherited from source '%s'" % entry.get("source", "?")
    return "scope from its own applies_to"


def _report_relevant(repo, sources, candidates, path=None, origin=None):
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
        for entry in source["allow"]:
            adopted.append(dict(entry, source=source["name"]))

    a_match, a_unscoped, _ = relevant(adopted, files)
    undecided = [c for c in candidates if c["status"] == "suggested"]
    decided = [c for c in candidates if c["status"] != "suggested"]
    c_match, c_unscoped, _ = relevant(undecided, files)
    d_match, d_unscoped, _ = relevant(decided, files)

    print("skills relevant to %s  (%d file(s) considered)" % (repo, len(files)))
    # Which roster answered, on every run and not only on an interesting one.
    # Every count below is a count *from this manifest*, and two machines with
    # different rosters print the same headings.
    if path is not None:
        print("roster: %s (from %s)" % (path, origin or "the configured value"))
    print()
    print("Adopted and scoped to this repo: %d" % len(a_match))
    for entry in a_match:
        # The scope's origin, not only the scope. A wrong glob inherited from the
        # source reads identically to one declared on the entry, and the fixes
        # are in different places.
        print("  - %s  (matched %s; %s)"
              % (entry["name"], ", ".join(entry["matched_by"]),
                 _scope_origin_phrase(entry)))
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

    # One line each, not the full pitch. Printed rather than filtered out so the
    # decision stays visible — a roster that silently omitted what was rejected
    # would invite re-litigating it, which is the cost the reason was written to
    # avoid. Zero is printed too, for the same reason the other counts are.
    already = d_match + d_unscoped
    print()
    print("Already decided, not pitched: %d" % len(already))
    for entry in already:
        print("  - %s [%s]" % (entry["name"], entry["status"]))
    return 0


if __name__ == "__main__":
    sys.exit(_main(sys.argv[1:]))
