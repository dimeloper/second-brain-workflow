"""Shared frontmatter parser for Python consumers.

Used by build-vault-index.py (practice notes) and check-lineage.py (both
practice notes and rules — the two share the same `---`-delimited YAML
frontmatter + markdown body shape). Factored out so there is one parser
rather than two that can drift apart, same reasoning as
scripts/lib/vault-identity.sh for the shell side.

Deliberately not used by render.py: that one needs a simpler, warning-free
parse in a hot rendering path (just `paths` and `description`), and changing
it isn't necessary for either consumer here.

    from lib.frontmatter import parse_frontmatter
    data, warnings = parse_frontmatter(path.read_text())
"""

import re


def strip_comment(value):
    """Drop a trailing YAML comment, respecting quotes."""
    out, quote = [], None
    for i, ch in enumerate(value):
        if quote:
            out.append(ch)
            if ch == quote:
                quote = None
        elif ch in "\"'":
            quote = ch
            out.append(ch)
        elif ch == "#" and (i == 0 or value[i - 1].isspace()):
            break
        else:
            out.append(ch)
    return "".join(out).strip()


def unquote(value):
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
        return value[1:-1]
    return value


def parse_list(value):
    inner = value.strip()
    if inner.startswith("[") and inner.endswith("]"):
        inner = inner[1:-1]
    return [unquote(p.strip()) for p in inner.split(",") if p.strip()]


def parse_frontmatter(text):
    """Minimal parser for the shapes this vault/rules actually use.

    Handles `key: value`, quoted values, inline lists and block lists. Anything
    else is reported rather than guessed at — a silent misparse would put wrong
    data in a report, which is worse than a warning.

    Returns (data, warnings). data is None (not {}) when there is no
    frontmatter block at all, so a caller can tell "empty frontmatter" apart
    from "no frontmatter block found."
    """
    if not text.startswith("---\n"):
        return None, ["no frontmatter block"]
    end = text.find("\n---", 4)
    if end == -1:
        return None, ["unterminated frontmatter block"]

    data, warnings, key = {}, [], None
    for raw in text[4:end].splitlines():
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        if raw.lstrip().startswith("- ") and key:
            data.setdefault(key, [])
            if isinstance(data[key], list):
                data[key].append(unquote(strip_comment(raw.lstrip()[2:])))
            continue
        m = re.match(r"^([A-Za-z][\w-]*):(.*)$", raw)
        if not m:
            warnings.append(f"unparsed line: {raw.strip()[:60]}")
            continue
        key, value = m.group(1), strip_comment(m.group(2))
        if value.startswith("["):
            data[key] = parse_list(value)
        elif value == "":
            data[key] = []
        else:
            data[key] = unquote(value)
    return data, warnings
