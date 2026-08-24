#!/usr/bin/env python3
"""Append one session's block to a daily note without losing another session's.

Two agent sessions wrapping up at the same time both read `2026-08-24.md`, both
compose a block from the copy they read, and both write the whole file back. The
second write drops the first session's block, the commit records the clobbered
state, and `git status` then reports a clean tree — so nothing anywhere says a
day's work just disappeared. That happened on 2026-08-24: an `echo-city-hotel`
wrap-up and a `housemaster-ingestion` wrap-up two minutes apart, recovered only
because one session's transcript was still open.

The fix is to stop doing read-modify-write on a file another process may hold.
This script is compare-and-swap instead:

    stamp = append-daily-block.py --stamp --quiet     # hash of what you read
    ... compose your block in a file ...
    append-daily-block.py --expect "$stamp" --block block.md

If the note moved between the two calls the write is **refused** (exit 3), not
merged blindly and not forced. Recovery is re-reading the note and re-running
the same command with a fresh stamp — the block file is still on disk, and the
merge is section-aware, so your bullets land under the right headers whatever
the other session wrote in the meantime.

Three further properties, each of which was a real defect before it was one:

- **The date comes off the clock here**, not from the caller, so a session that
  began yesterday cannot file today's work under yesterday's note. `--date`
  exists for tests and for a deliberate correction.
- **The merge only ever adds lines.** After building the new text the script
  re-checks that every non-blank line of the note it read is still present, the
  same number of times, and refuses to write if not (exit 5). A rewriter that
  verifies its own rewrite is the only kind that can be trusted with a file it
  did not fully parse.
- **A short lock** (in the system temp dir, never in the vault) serialises the
  read-merge-write, so two invocations landing in the same millisecond cannot
  both pass the hash check.

Usage:
  append-daily-block.py [--vault PATH] [--date YYYY-MM-DD] --stamp [--quiet]
  append-daily-block.py [--vault PATH] [--date YYYY-MM-DD] \\
                        --expect HASH --block FILE [--dry-run]

  --block -     read the block from stdin
  --expect      the hash printed by --stamp, or `absent` if there was no note
  --dry-run     print the merged note to stdout, write nothing

Exit codes: 0 written, 2 usage, 3 stale (someone else wrote), 4 malformed
block, 5 the merge would have lost a line (a bug here; nothing is written).

Vault resolution: --vault, else $SBW_VAULT, else ~/vaults/second-brain
Stdlib only, by design: this must run on a machine with nothing installed.
"""

import argparse
import hashlib
import os
import re
import sys
import tempfile
import time
from datetime import date as date_cls
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from lib.config import load as load_config  # noqa: E402
from lib.config import origin_describe  # noqa: E402
from lib.vault_state import classify  # noqa: E402

# The daily note's shape, in the order a note lays it out. `## Built` may repeat
# as `## Built (label)` for a genuinely distinct work stream — every other
# section is one per day, which is what `keep-one-header-per-section-in-daily-
# notes` in the vault says and what this script enforces mechanically by
# appending to an existing header rather than writing a second one.
CANONICAL = (
    "## Resume here",
    "## Built",
    "## Follow-ups",
    "## Practices followed",
    "## Drift / gaps",
    "## Vault candidates",
    "## Vault writes (approved)",
    "## Vault writes (declined)",
)
RANK = {h: i for i, h in enumerate(CANONICAL)}

BUILT_LABELLED_RE = re.compile(r"^## Built \(.+\)$")
HEADER_RE = re.compile(r"^## ")
DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")

# The template's empty bullet, checkbox form included. A section holding only
# this is a placeholder, not content, so appending to it replaces it instead of
# leaving a stray dash above the first real line — and the lost-line check below
# has to know that, or replacing one reads as losing one.
PLACEHOLDER_RE = re.compile(r"^-\s*(\[[ xX]\]\s*)?$")

LOCK_STALE_SECONDS = 60
LOCK_WAIT_SECONDS = 10


def resolve_vault(explicit):
    if explicit:
        return Path(explicit).expanduser()
    cfg = load_config(warn=lambda m: print(f"warning: {m}", file=sys.stderr))
    return Path(cfg["SBW_VAULT"]).expanduser()


def note_hash(path):
    """`absent` is a state, not an error — the first block of the day creates
    the note, and a caller that read nothing must be able to say so."""
    if not path.exists():
        return "absent"
    return hashlib.sha256(path.read_bytes()).hexdigest()


def header_rank(header, fallback):
    if header in RANK:
        return RANK[header]
    if BUILT_LABELLED_RE.match(header):
        return RANK["## Built"]
    # A section this script doesn't know about — hand-written in Obsidian, or
    # from a future template. It inherits the rank of whatever it follows, so a
    # new section is never inserted into the middle of someone else's block.
    return fallback


def split_sections(text):
    """(preamble_lines, [(header, body_lines), ...]) — every line accounted for."""
    preamble = []
    sections = []
    for line in text.splitlines():
        if HEADER_RE.match(line):
            sections.append([line, []])
        elif sections:
            sections[-1][1].append(line)
        else:
            preamble.append(line)
    return preamble, [(h, b) for h, b in sections]


def strip_edges(lines):
    start, end = 0, len(lines)
    while start < end and not lines[start].strip():
        start += 1
    while end > start and not lines[end - 1].strip():
        end -= 1
    return lines[start:end]


def split_trailing_comment(body):
    """(content, trailing_comment) — the template parks an HTML comment at the
    end of a section explaining the convention for that section. New bullets go
    *above* it, or the explanation drifts into the middle of the day's work."""
    end = len(body)
    while end > 0 and not body[end - 1].strip():
        end -= 1
    if end == 0 or not body[end - 1].strip().endswith("-->"):
        return body, []
    start = end - 1
    while start >= 0 and not body[start].lstrip().startswith("<!--"):
        start -= 1
    if start < 0:
        return body, []
    return body[:start], body[start:]


def is_placeholder(body):
    content = [ln for ln in strip_edges(body) if not ln.lstrip().startswith("<!--")]
    return all(PLACEHOLDER_RE.match(ln) or not ln.strip() for ln in content)


def append_to_body(body, new_lines):
    content, comment = split_trailing_comment(body)
    content = strip_edges(content)
    if is_placeholder(content):
        content = []
    merged = content + strip_edges(new_lines)
    if comment:
        merged = merged + [""] + strip_edges(comment)
    return merged


def render(preamble, sections):
    out = []
    pre = strip_edges(preamble)
    if pre:
        out.extend(pre)
        out.append("")
    for header, body in sections:
        out.append(header)
        body = strip_edges(body)
        if body:
            out.extend(body)
        out.append("")
    while out and not out[-1].strip():
        out.pop()
    return "\n".join(out) + "\n"


def link_line(day, other):
    """The cross-link a midnight crossing needs, worded by direction.

    A session that runs past midnight belongs to two notes, and the convention
    is a line at the top of each pointing at the other. The block format cannot
    carry it — a block is sections only, and this line lives above the first
    header — so it is its own flag rather than something a caller hand-edits
    around the appender. Which would be the whole-file write again, on the one
    night it is most likely to happen.
    """
    return f"Continues [[{other}]]." if other < day else f"Continued in [[{other}]]."


def add_link(note_text, day, other):
    """Insert the cross-link under the title, or leave an existing one alone."""
    line = link_line(day, other)
    lines = note_text.splitlines()
    if any(f"[[{other}]]" in ln for ln in lines[:6]):
        return note_text, False
    at = 1 if lines and lines[0].startswith("# ") else 0
    head = lines[:at]
    tail = lines[at:]
    while tail and not tail[0].strip():
        tail = tail[1:]
    return "\n".join(head + ["", line, ""] + tail) + "\n", True


def merge(note_text, block_text):
    """Return (merged_text, touched_headers). Only ever adds lines."""
    block_preamble, block_sections = split_sections(block_text)
    stray = [ln for ln in block_preamble if ln.strip()]
    if stray:
        raise Malformed(
            "the block has content above its first `## ` header:\n"
            f"       {stray[0].strip()!r}\n"
            "       A block is sections only — the note owns its own title."
        )
    if not block_sections:
        raise Malformed(
            "the block has no `## ` section header.\n"
            "       Every line of a block belongs under one of: "
            + ", ".join(CANONICAL)
        )
    for header, _ in block_sections:
        if header not in RANK and not BUILT_LABELLED_RE.match(header):
            raise Malformed(
                f"unknown section header in the block: {header}\n"
                "       Allowed: " + ", ".join(CANONICAL) + ", or `## Built (label)`."
            )

    preamble, sections = split_sections(note_text)
    touched = []
    for header, body in block_sections:
        existing = next((i for i, (h, _) in enumerate(sections) if h == header), None)
        if existing is not None:
            sections[existing] = (header, append_to_body(sections[existing][1], body))
            touched.append(header)
            continue
        rank = header_rank(header, len(CANONICAL))
        # Before the first section that sorts after this one; equal ranks stay
        # put, which is what keeps a new `## Built (label)` after the Built
        # blocks already there rather than ahead of them.
        seen = -1
        insert_at = len(sections)
        for i, (h, _) in enumerate(sections):
            seen = header_rank(h, max(seen, 0))
            if seen > rank:
                insert_at = i
                break
        sections.insert(insert_at, (header, strip_edges(body)))
        touched.append(header)
    return render(preamble, sections), touched


class Malformed(Exception):
    pass


def lost_lines(before, after):
    """Non-blank lines the merge dropped, as a multiset difference.

    Blank lines are excluded on purpose: rendering normalises the blank line
    between sections, and a spacing change is not a lost update. So is the
    template's empty bullet, which appending to a placeholder section replaces
    by design. Everything that carries meaning is compared exactly, count
    included, so a bullet duplicated into a second section still fails.
    """

    def meaningful(line):
        return bool(line.strip()) and not PLACEHOLDER_RE.match(line.strip())

    counts = {}
    for line in after.splitlines():
        if meaningful(line):
            counts[line] = counts.get(line, 0) + 1
    missing = []
    for line in before.splitlines():
        if not meaningful(line):
            continue
        if counts.get(line, 0) <= 0:
            missing.append(line)
        else:
            counts[line] -= 1
    return missing


def lock_path(note):
    key = hashlib.sha1(str(note.resolve()).encode("utf-8")).hexdigest()[:16]
    return Path(tempfile.gettempdir()) / f"sbw-daily-{key}.lock"


class Lock:
    """A tiny mkdir-style lock in the temp dir, never in the vault — a lock file
    inside the vault would be a path the commit guard has to know about, and a
    stray one would show up in Obsidian."""

    def __init__(self, path):
        self.path = path
        self.fd = None

    def __enter__(self):
        deadline = time.monotonic() + LOCK_WAIT_SECONDS
        while True:
            try:
                self.fd = os.open(self.path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
                os.write(self.fd, f"{os.getpid()} {int(time.time())}\n".encode("utf-8"))
                return self
            except FileExistsError:
                if self._break_if_stale():
                    continue
                if time.monotonic() > deadline:
                    print(
                        f"warning: gave up waiting for {self.path} — another wrap-up "
                        "is still writing. The hash check below is still the "
                        "authority; a stale read is refused either way.",
                        file=sys.stderr,
                    )
                    return self
                time.sleep(0.05)

    def _break_if_stale(self):
        try:
            age = time.time() - self.path.stat().st_mtime
        except FileNotFoundError:
            return True
        if age > LOCK_STALE_SECONDS:
            print(f"warning: breaking a {int(age)}s-old lock at {self.path}", file=sys.stderr)
            self.path.unlink(missing_ok=True)
            return True
        return False

    def __exit__(self, *exc):
        if self.fd is not None:
            os.close(self.fd)
            self.path.unlink(missing_ok=True)
        return False


def write_atomic(path, text):
    """Temp file in the same directory, then `os.replace`. A reader either sees
    the old note or the new one — never the half-written middle, which is the
    state an editor with the file open would otherwise pick up.

    Same directory because `os.replace` is only atomic within one filesystem.
    That leaves a dotfile in the vault if the process is killed outright between
    the two steps — invisible in Obsidian, but a path the commit guard's
    allowlist would refuse, which is a confusing way to learn about it. So sweep
    any of ours left behind first; a write takes milliseconds, so anything older
    than the lock's staleness window is debris.
    """
    now = time.time()
    for stale in path.parent.glob(f".{path.name}.*.tmp"):
        try:
            if now - stale.stat().st_mtime > LOCK_STALE_SECONDS:
                stale.unlink()
        except OSError:
            pass
    fd, tmp = tempfile.mkstemp(dir=str(path.parent), prefix=f".{path.name}.", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(text)
        os.replace(tmp, path)
    except BaseException:
        Path(tmp).unlink(missing_ok=True)
        raise


def read_block(spec):
    if spec == "-":
        return sys.stdin.read()
    path = Path(spec).expanduser()
    if not path.is_file():
        sys.exit(f"append-daily-block: no such block file: {path}")
    return path.read_text(encoding="utf-8")


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--vault", help="vault path (default: $SBW_VAULT)")
    ap.add_argument("--date", help="YYYY-MM-DD (default: today, off the clock)")
    ap.add_argument("--stamp", action="store_true", help="print the note's current hash and stop")
    ap.add_argument("--quiet", action="store_true", help="--stamp prints the hash alone")
    ap.add_argument("--expect", help="the hash from --stamp, or `absent`")
    ap.add_argument("--block", help="file holding the block to append, or `-` for stdin")
    ap.add_argument("--link", metavar="YYYY-MM-DD",
                    help="cross-link this note to another day's, above the first header "
                         "(for a session that ran past midnight). Idempotent.")
    ap.add_argument("--dry-run", action="store_true", help="print the merged note, write nothing")
    args = ap.parse_args()

    if args.date and not DATE_RE.match(args.date):
        ap.error("--date must be YYYY-MM-DD")
    if args.link and not DATE_RE.match(args.link):
        ap.error("--link must be YYYY-MM-DD")
    if not args.stamp and not args.block and not args.link:
        ap.error("need --stamp, or --block/--link with --expect")
    if args.link and not args.expect:
        ap.error("--link needs --expect, for the same reason --block does")
    if args.block and not args.expect:
        ap.error(
            "--block needs --expect: run --stamp when you read the note and pass "
            "that hash back. Without it this is the read-modify-write that loses "
            "another session's block."
        )

    vault = resolve_vault(args.vault)
    state, message = classify(
        vault, "the --vault flag" if args.vault else origin_describe("SBW_VAULT")
    )
    if state == "missing":
        sys.exit(message)

    # Off the clock, every invocation. A caller that has been running since
    # yesterday has yesterday's date in context and no way to notice.
    day = args.date or date_cls.today().isoformat()
    note = vault / f"{day}.md"

    if args.stamp:
        current = note_hash(note)
        if args.quiet:
            print(current)
        else:
            print(f"date  {day}")
            print(f"note  {note}")
            print(f"state {'present' if current != 'absent' else 'absent'}")
            print(f"hash  {current}")
        return 0

    with Lock(lock_path(note)):
        current = note_hash(note)
        if current != args.expect:
            print(
                f"append-daily-block: {note.name} changed since you read it.\n"
                f"       expected {args.expect}\n"
                f"       on disk  {current}\n"
                "       Another session wrote to today's note. Nothing was written.\n"
                "       Re-read the note, re-run --stamp, and re-run this command with\n"
                "       the same --block file: the merge is section-aware, so your\n"
                "       bullets land under the right headers whatever landed first.",
                file=sys.stderr,
            )
            return 3

        before = note.read_text(encoding="utf-8") if current != "absent" else f"# {day}\n"
        merged, touched = before, []
        if args.block:
            try:
                merged, touched = merge(merged, read_block(args.block))
            except Malformed as exc:
                print(f"append-daily-block: {exc}", file=sys.stderr)
                return 4
        if args.link:
            merged, linked = add_link(merged, day, args.link)
            touched = touched + [f"link → {args.link}"] if linked else touched

        missing = lost_lines(before, merged)
        if missing:
            print(
                "append-daily-block: the merge would have dropped "
                f"{len(missing)} line(s) — refusing to write.\n"
                + "\n".join(f"       - {ln.strip()}" for ln in missing[:5]),
                file=sys.stderr,
            )
            return 5

        if args.dry_run:
            sys.stdout.write(merged)
            return 0

        # An idempotent --link on a note that already carries it changes
        # nothing. Say so rather than reporting a write of zero lines, and skip
        # the write: rewriting identical bytes is a no-op to every reader except
        # the person reading the output.
        if merged == before:
            print(f"{note} unchanged — nothing to add")
            return 0

        write_atomic(note, merged)

    added = len(merged.splitlines()) - len(before.splitlines())
    print(f"Wrote {note} (+{added} lines, {', '.join(touched)})")
    print(f"hash  {note_hash(note)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
