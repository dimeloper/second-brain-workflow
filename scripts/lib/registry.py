"""The set of repos this machine has rendered into, and how each was rendered.

    from lib.registry import register, read, mode_of, registry_path
    register(target, mode="local", warn=lambda m: print(f"warning: {m}", file=sys.stderr))

`render.py` writes `.sbw-version` *into* the target and, before this, left no
trace on the machine at all — so "re-render every onboarded repo after an
upgrade" had no list to work from. The only available answer was a guessed
directory glob, and a glob that matches nothing is indistinguishable from a
machine that has genuinely onboarded nothing. One of those is fine and the
other leaves every repo on the machine at a stale render.

File: ${XDG_CONFIG_HOME:-~/.config}/second-brain-workflow/repos — one entry per
line, blank lines and `#` comments ignored on read. An entry is an absolute
path, optionally followed by TAB-separated `key=value` fields:

    /Users/me/dev/my-repo
    /Users/me/work/their-repo\tmode=local

`mode` is the render mode: `local` (the rendered files are kept out of that
repo's remote via `.git/info/exclude`) or `shared`. It is recorded here because
the registry recorded *which* repos are onboarded and not *how*, and the only
record of the mode was a marked block inside that one clone's `.git/info/exclude`
— which `adopt.sh` read and `render.py`, `make render` and `repos-check.sh` did
not. So the fix command `make upgrade` prints re-rendered a `--local` repo in
shared mode, the new files landed outside the exclude block, and in a repo where
those paths are tracked that is personal conventions committed to a shared
remote. A path with no `mode` field predates this and is *unknown*, not shared:
see render.py, which infers it once from the exclude block and records the answer.

Unknown fields are preserved on write, so a newer engine's key survives a render
by an older one rather than being silently dropped.

Deliberately *not* the machine config file: that parser does not strip trailing
comments, and this is a list, not key/value. Deliberately *not* redirected by
SBW_CONFIG_FILE either — that names the config file, not a config directory.

Keep in step with lib/registry.sh; both resolve the same path and read the same
format. Nothing here reads the config file, so there is no precedence chain to
mirror.
"""

import os
from pathlib import Path

# The values `mode` may carry. A line holding anything else is a state this
# engine does not understand, and render.py refuses rather than picking one —
# guessing would be guessing about who sees your conventions.
MODES = ("local", "shared")


def registry_path():
    base = os.environ.get("XDG_CONFIG_HOME") or str(Path.home() / ".config")
    return Path(base) / "second-brain-workflow" / "repos"


def _parse(line):
    """One entry -> (path, {field: value}). Fields are TAB-separated key=value."""
    path, _, rest = line.partition("\t")
    fields = {}
    for chunk in rest.split("\t"):
        chunk = chunk.strip()
        if not chunk:
            continue
        key, sep, value = chunk.partition("=")
        if sep:
            fields[key.strip()] = value.strip()
    return path.strip(), fields


def _format(path, fields):
    parts = [path]
    parts.extend(f"{k}={fields[k]}" for k in sorted(fields) if fields[k] != "")
    return "\t".join(parts)


def read_entries(path=None):
    """[(repo_path, fields)] in file order. Missing or unreadable file -> []."""
    path = Path(path) if path else registry_path()
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        return []
    out = []
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        repo, fields = _parse(line)
        if repo:
            out.append((repo, fields))
    return out


def read(path=None):
    """Registered paths, in file order. Missing or unreadable file -> []."""
    return [repo for repo, _ in read_entries(path)]


def mode_of(repo, path=None):
    """The recorded render mode for `repo`, or None when the line carries none.

    None is *unknown*, not `shared`: every line written before the field existed
    has no mode, and reading those as shared is exactly the silent switch this
    field was added to stop. The caller decides what to do with an unknown —
    render.py infers it once and records the answer.

    Matched on realpath, the form `register` stores, so the same repo reached
    through a symlinked parent resolves to its one entry.
    """
    entry = os.path.realpath(str(repo))
    for candidate, fields in read_entries(path):
        if candidate == entry:
            return fields.get("mode") or None
    return None


def register(repo, mode=None, warn=None):
    """Record a successful render of `repo`. -> True when the registry names it.

    realpath, so the same repo reached through a symlinked parent cannot enter
    twice. Sorted and deduped on write, so rendering the same repo twice leaves
    one line.

    `mode` is recorded when given, and an existing mode is left alone when it is
    not: a caller that has no opinion must not erase a recorded one.

    Never raises: rendering is the job, and a repo that rendered fine is not a
    failed render because a config directory is read-only. But it never fails
    quietly either — silence here is what produces an undetermined set later
    with nothing to explain it.
    """
    path = registry_path()
    entry = os.path.realpath(str(repo))
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        entries = dict(read_entries(path))
        fields = dict(entries.get(entry, {}))
        if mode:
            fields["mode"] = mode
        entries[entry] = fields
        # Temp file plus replace: a failure partway through must leave the
        # previous list intact rather than truncate it. Same directory, so the
        # replace is atomic.
        tmp = path.with_name(path.name + ".tmp")
        tmp.write_text(
            "".join(_format(p, entries[p]) + "\n" for p in sorted(entries)),
            encoding="utf-8",
        )
        os.replace(tmp, path)
        return True
    except OSError as exc:
        if warn:
            warn(
                f"rendered, but could not record this repo in {path}: "
                f"{exc.strerror or exc}. Until a render succeeds in writing it, "
                "doctor reports the onboarded repo set as undetermined."
            )
        return False
