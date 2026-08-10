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
SOURCE_KEYS_OPTIONAL = ("ref", "skills_subdir", "//")
SOURCE_KEYS = SOURCE_KEYS_REQUIRED + SOURCE_KEYS_OPTIONAL
TOP_KEYS = ("sources", "//")

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
        })

    return sources, warnings


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
    """(path, sources, warnings). path is None when no manifest is configured."""
    path = manifest_path(flag, cfg)
    if path is None:
        return None, [], []
    if not path.is_file():
        raise ManifestError(
            "%s: no such file. This is where the skill roster is expected "
            "because SBW_SKILLS_MANIFEST points here; unset it to run with "
            "workflow skills only." % path)
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as exc:
        raise ManifestError("%s: cannot read: %s" % (path, exc))
    sources, warnings = parse(text, origin=str(path))
    return path, sources, warnings


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


def _main(argv):
    parser = argparse.ArgumentParser(
        description="Parse, validate and resolve a skill-source manifest.")
    parser.add_argument("mode", choices=("resolve", "validate", "sources"))
    parser.add_argument("--engine", default=str(Path(__file__).resolve().parent.parent.parent),
                        help="engine checkout, where vendor/external/ lives")
    parser.add_argument("--manifest", default=None,
                        help="manifest path, overriding env and config")
    args = parser.parse_args(argv)

    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
    from lib.config import load as load_config  # noqa: E402

    try:
        path, sources, warnings = load(args.manifest, load_config())
    except ManifestError as exc:
        sys.stderr.write("error: %s\n" % exc)
        return 2

    for warning in warnings:
        sys.stderr.write("warning: %s\n" % warning)

    if path is None:
        return 0

    if args.mode == "validate":
        print("%s: %d source(s), %d skill(s) allowed"
              % (path, len(sources), sum(len(s["allow"]) for s in sources)))
        return 0

    if args.mode == "sources":
        # Tab-separated for the fetch script: name, repo, ref, checkout dir.
        for source in sources:
            print("\t".join([source["name"], source["repo"], source["ref"],
                             str(source_root(args.engine, source))]))
        return 0

    for row in resolve(args.engine, sources):
        print("\t".join(row))
    return 0


if __name__ == "__main__":
    sys.exit(_main(sys.argv[1:]))
