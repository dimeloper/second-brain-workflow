"""Config resolution for Python consumers.

    from lib.config import load
    cfg = load()
    cfg["SBW_VAULT"]

Precedence: existing environment wins over the config file, which wins over
defaults. CLI flags are the caller's job — apply them on top of load().
Keep in step with lib/config.sh; both implement the same nine keys.
"""

import os
from pathlib import Path

DEFAULTS = {
    "SBW_VAULT": "~/vaults/second-brain",
    "RENDER_TARGETS": "cursor,claude-code,agents",
    "SKILLS_DIRS": "~/.cursor/skills:~/.claude/skills",
    "VENDOR_SKILLS": "obsidian-bases obsidian-markdown",
    # Empty means "no third-party skill sources declared". The roster belongs to
    # the person, not to this repo — same split as SBW_RULES_DIR below, and for
    # the same reason: an engine shipping a curated set of someone else's skills
    # would be shipping an opinion, which `rules/` being empty exists to avoid.
    "SBW_SKILLS_MANIFEST": "",
    # Empty means "not overridden" — render.py falls back to ENGINE/rules.
    "SBW_RULES_DIR": "",
    # Empty by design, not a fallback — no shell consumer reads this key yet
    # (guard-vault-commit.sh / init-vault.sh are bash), but it's tracked here
    # too so the two config implementations never define different key sets.
    "SBW_EXPECTED_VAULT_ID": "",
    # Where the rendered-repo scan looks, and how deep. No Python consumer reads
    # either one yet — the scan is shell — but they are tracked here for the same
    # reason SBW_EXPECTED_VAULT_ID is: a key the two implementations do not both
    # know about is a key one of them warns is unknown.
    "SBW_SCAN_ROOTS": "~",
    "SBW_SCAN_DEPTH": "5",
}


def config_path():
    override = os.environ.get("SBW_CONFIG_FILE")
    if override:
        return Path(override)
    base = os.environ.get("XDG_CONFIG_HOME") or str(Path.home() / ".config")
    return Path(base) / "second-brain-workflow" / "config"


def origin_describe(key):
    """Human phrase for where a key's value came from.

    For an error message that tells the reader which knob to reach for. Kept
    stateless — unlike the shell side, load() never mutates os.environ, so the
    provenance can simply be recomputed rather than snapshotted. Wording must
    match ds_origin_describe in lib/config.sh; test-vault-state.sh asserts it.
    """
    path = config_path()
    if key in os.environ:
        return f"the {key} environment variable"
    if path.is_file():
        for raw in path.read_text(encoding="utf-8").splitlines():
            line = raw.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            if line.partition("=")[0].strip() == key:
                return f"{key} in {path}"
    return f"the built-in default (no {key} in {path})"


def _expand(value):
    """Expand a leading ~ only — a config file must not run shell code."""
    if value == "~" or value.startswith("~/"):
        return str(Path(value).expanduser())
    return value


def load(warn=None):
    cfg = {}
    path = config_path()
    if path.is_file():
        for raw in path.read_text(encoding="utf-8").splitlines():
            line = raw.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, _, value = line.partition("=")
            key, value = key.strip(), value.strip()
            if key not in DEFAULTS:
                if warn:
                    warn(f"{path}: unknown key '{key}'")
                continue
            cfg[key] = _expand(value)

    for key, default in DEFAULTS.items():
        env = os.environ.get(key)
        # Set-but-empty counts as set: an explicitly empty value is a
        # deliberate "none", not a request for the default.
        if env is not None:
            cfg[key] = _expand(env)
        elif key not in cfg:
            cfg[key] = _expand(default)
    return cfg
