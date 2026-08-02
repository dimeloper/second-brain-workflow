"""Config resolution for Python consumers.

    from lib.config import load
    cfg = load()
    cfg["DEV_STANDARDS_VAULT"]

Precedence: existing environment wins over the config file, which wins over
defaults. CLI flags are the caller's job — apply them on top of load().
Keep in step with lib/config.sh; both implement the same five keys.
"""

import os
from pathlib import Path

DEFAULTS = {
    "DEV_STANDARDS_VAULT": "~/vaults/second-brain",
    "RENDER_TARGETS": "cursor,claude-code,agents",
    "SKILLS_DIRS": "~/.cursor/skills:~/.claude/skills",
    "VENDOR_SKILLS": "obsidian-bases obsidian-markdown",
    # Empty means "not overridden" — render.py falls back to ENGINE/rules.
    "DEV_STANDARDS_RULES_DIR": "",
}


def config_path():
    override = os.environ.get("DS_CONFIG_FILE")
    if override:
        return Path(override)
    base = os.environ.get("XDG_CONFIG_HOME") or str(Path.home() / ".config")
    return Path(base) / "dev-standards" / "config"


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
