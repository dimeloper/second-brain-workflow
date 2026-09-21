"""Slug -> practice note, for the reports that cite practices by name.

A citation in a daily note is a wikilink, and nothing in `[[some-slug]]` says
what it points at. On 2026-09-21 the recent-work footer reported 54 "practices
followed" over one week. One of them was a date — `[[2026-09-15]]` sitting in
the *prose* of another citation — two were rules from the rules repo, one was a
project feature file, and one was a whole sentence containing no link at all. A
number like that cannot be acted on: it reads as a measure of engineering
discipline and is partly a record of which other notes got mentioned.

Resolving each slug against `practices/**` separates the two. A slug that
resolves is a practice. One that does not is *reported as unresolved* rather
than dropped, because a citation that resolves nowhere is a finding about the
note that wrote it — in Obsidian it is a dead link — and quietly excluding it
would hide the drift this exists to surface, which is the same failure as
counting it.

`scope: workflow` marks a practice about how the vault itself is written —
the appender's own invariants, restated by every session wrap-up. They are real
practices and they are not decisions a window made, so a report separates them
instead of letting three of them outweigh everything else in a top-five.

    from lib.practice_index import index, WORKFLOW_SCOPE
    notes = index(vault)                                  # {slug: Entry}
    notes["prove-a-test-fails-without-the-fix"].scope     # None
"""

from collections import namedtuple
from pathlib import Path

from lib.frontmatter import parse_frontmatter

# A practice about writing the vault, not about building software. Set in the
# note's own frontmatter, so the classification lives with the note rather than
# in a list inside whichever report happens to read it.
WORKFLOW_SCOPE = "workflow"

Entry = namedtuple("Entry", "slug path scope domain")


def index(vault):
    """{slug: Entry} for every note under `practices/`, slug being its filename.

    The filename is the slug because that is what a wikilink resolves against in
    Obsidian — matching on a `name:` field instead would make this report agree
    with itself and disagree with the editor the notes are read in.

    A vault with no `practices/` directory yields `{}`. That is not an error
    here: it makes every citation unresolved, which is the honest reading of a
    vault that has no practices in it.
    """
    out = {}
    root = Path(vault) / "practices"
    if not root.is_dir():
        return out
    for path in sorted(root.rglob("*.md")):
        data, _ = parse_frontmatter(path.read_text(encoding="utf-8", errors="replace"))
        data = data or {}
        scope = data.get("scope")
        if isinstance(scope, list):
            # `scope: [workflow]` is the same claim written the other way.
            scope = scope[0] if scope else None
        out[path.stem] = Entry(
            slug=path.stem,
            path=path,
            scope=(scope or None),
            domain=(data.get("domain") or None),
        )
    return out
