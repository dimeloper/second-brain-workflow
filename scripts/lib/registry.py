"""The set of repos this machine has rendered into.

    from lib.registry import register, read, registry_path
    register(target, warn=lambda m: print(f"warning: {m}", file=sys.stderr))

`render.py` writes `.sbw-version` *into* the target and, before this, left no
trace on the machine at all — so "re-render every onboarded repo after an
upgrade" had no list to work from. The only available answer was a guessed
directory glob, and a glob that matches nothing is indistinguishable from a
machine that has genuinely onboarded nothing. One of those is fine and the
other leaves every repo on the machine at a stale render.

File: ${XDG_CONFIG_HOME:-~/.config}/second-brain-workflow/repos — one absolute
path per line, blank lines and `#` comments ignored on read. Deliberately *not*
the machine config file: that parser does not strip trailing comments, and this
is a list, not key/value. Deliberately *not* redirected by SBW_CONFIG_FILE
either — that names the config file, not a config directory.

Keep in step with lib/registry.sh; both resolve the same path and read the same
format. Nothing here reads the config file, so there is no precedence chain to
mirror.
"""

import os
from pathlib import Path


def registry_path():
    base = os.environ.get("XDG_CONFIG_HOME") or str(Path.home() / ".config")
    return Path(base) / "second-brain-workflow" / "repos"


def read(path=None):
    """Registered paths, in file order. Missing or unreadable file -> []."""
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
        out.append(line)
    return out


def register(repo, warn=None):
    """Record a successful render of `repo`. -> True when the registry names it.

    realpath, so the same repo reached through a symlinked parent cannot enter
    twice. Sorted and deduped on write, so rendering the same repo twice leaves
    one line.

    Never raises: rendering is the job, and a repo that rendered fine is not a
    failed render because a config directory is read-only. But it never fails
    quietly either — silence here is what produces an undetermined set later
    with nothing to explain it.
    """
    path = registry_path()
    entry = os.path.realpath(str(repo))
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        entries = sorted(set(read(path)) | {entry})
        # Temp file plus replace: a failure partway through must leave the
        # previous list intact rather than truncate it. Same directory, so the
        # replace is atomic.
        tmp = path.with_name(path.name + ".tmp")
        tmp.write_text("".join(e + "\n" for e in entries), encoding="utf-8")
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
