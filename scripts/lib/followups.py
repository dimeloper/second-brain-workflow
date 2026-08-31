"""Reading `## Follow-ups` items, and attributing each one to a repo.

Two consumers, one implementation — the check-follow-ups skill (recent notes,
interactive) and check-followups.py (every note, long-range). They must agree
about what an item *is* and which repo it belongs to, or the same backlog reads
differently depending on which one you asked. Same reasoning as
lib/vault-identity.sh for the guard/init-vault pair.

    from lib.followups import open_followups, attribute, group_for_repo

Attribution is best-effort by design, and the honest outcome is three-valued:
this repo, another repo, or unknown. Callers **group** on that; they never
filter on it. An open item is a thing you have not done, and its repo is
metadata about it — dropping the item because the metadata is missing loses the
item, and the ones with no repo to infer (an email to send, a dashboard to
check, a decision to make) are exactly the ones that rot longest.

Read-only. Stdlib only.
"""

import re
import subprocess
from pathlib import Path

from lib.frontmatter import parse_frontmatter

FOLLOWUP_ITEM_RE = re.compile(r'^-\s\[ \]\s+(.*)$')
FOLLOWUP_DONE_RE = re.compile(r'^-\s\[x\]\s+(.*)$', re.IGNORECASE)

# The recorded form: a trailing `#repo/<name>` tag, written by
# update-second-brain, which knows the repo because it is running inside it.
# Inference below is the fallback for items written before the convention (and
# for anything hand-typed into Obsidian); this is the exact signal.
REPO_TAG_RE = re.compile(r'(?:^|\s)#repo/([A-Za-z0-9._-]+)')

# What a tick actually meant. `- [x]` on its own records that an item left the
# list and nothing about how — and "done" and "abandoned" look identical once
# ticked while leading to opposite actions when the question comes back. One is
# finished work you can cite; the other is an open risk sitting in somebody
# else's backlog with nobody watching it.
#
# Same shape as `#repo/` deliberately: one namespace, written by the side that
# knows, read by the side that reports.
#
#   - [x] Merge the barcode PR #outcome/done #repo/acme-app
#   - [x] Rewrite the importer in Rust #outcome/dropped — the CSV path was fast enough
#   - [x] Rotate the CRM key #outcome/handed-off #owner/ops-team
OUTCOME_TAG_RE = re.compile(r'(?:^|\s)#outcome/([a-z][a-z-]*)')
OWNER_TAG_RE = re.compile(r'(?:^|\s)#owner/([A-Za-z0-9._-]+)')

# Closing outcomes: the item is finished as far as this list is concerned.
# `superseded` closes because the thing that replaced it is its own item — the
# question was answered, by a different answer than the one that was proposed.
OUTCOME_CLOSING = frozenset({"done", "superseded"})
# Non-closing outcomes: the tick is accurate (nobody is working on it) and the
# work is not finished. `dropped` is a decision to accept a risk; `handed-off`
# is that risk with a name against it. Both stay visible, because the reason
# they were ticked is exactly the reason they stop being looked at.
OUTCOME_UNRESOLVED = frozenset({"dropped", "handed-off"})
OUTCOMES = OUTCOME_CLOSING | OUTCOME_UNRESOLVED


def outcome_for(item):
    """(outcome, owner) for a ticked item — either may be None.

    An unrecognised `#outcome/<word>` is returned as-is rather than dropped: the
    vocabulary is this engine's, the notes are the user's, and silently reading
    an outcome nobody here anticipated as "no outcome" would report a considered
    decision as an unmarked tick.
    """
    m = OUTCOME_TAG_RE.search(item)
    owner = OWNER_TAG_RE.search(item)
    return (m.group(1) if m else None, owner.group(1) if owner else None)


def closes(item):
    """Does ticking this item take it off the open list?

    True for an unmarked `- [x]`, which is what every note written before this
    convention contains — a report that reopened those would be re-raising years
    of finished work on the strength of a missing tag.
    """
    outcome, _ = outcome_for(item)
    return outcome not in OUTCOME_UNRESOLVED


# A bare repo name mentioned in prose, in any of the forms these items actually
# use: backticked, bare, or as a path segment (`~/vaults/second-brain`). Bounded
# on both sides by word characters and `-` only — that is what keeps
# `housemaster-backend` from matching a repo named `backend`, and
# `second-brain-workflow` from matching one named `second-brain`, while still
# matching a name that happens to follow a `/`.
def mention_re(repo):
    return re.compile(r'(?<![\w-])' + re.escape(repo) + r'(?![\w-])')


# Items whose urgency has nothing to do with which repo they are in, and which
# therefore must survive any collapsing of the other-repo groups. Two kinds,
# because two kinds actually showed up: something the note itself calls blocking,
# and a credential that is live until someone acts.
#
# Keyword matching, deliberately, with the asymmetry stated: a false positive
# costs one extra line in a short list, a false negative hides a live key or the
# thing the whole day was waiting on. The reason is always printed, so a wrong
# flag is visible and arguable rather than silent.
FLAG_PATTERNS = (
    ("blocked", (
        r'pause point', r'\bblocked\b', r'\bblocker\b',
        r'\bawaiting\b', r'waiting on',
        # "blocks" and "gates" only when asserted, not when quoted. An item
        # saying "it changes what the guard *blocks*" is discussing the word, not
        # claiming to be blocked — and that false positive is what promoted a
        # second-brain-workflow design question above a live credential.
        r'(?<![*`])\bblocks\b(?![*`])', r'(?<![*`])\bgates\b(?![*`])',
    )),
    ("credential", (
        r'\brotate\b', r'\brevoke[ds]?\b', r'api key', r'\bsecrets?\b',
        r'\bcredentials?\b', r'\btokens?\b', r'\bpasswords?\b',
        r'pasted into chat', r'\bleaked\b', r'\bexposed\b',
    )),
)
_FLAG_RES = tuple((name, tuple(re.compile(p, re.IGNORECASE) for p in pats))
                  for name, pats in FLAG_PATTERNS)


def display(item):
    """The item as a reader wants it: without the tag machinery.

    A tag exists to be matched on, and once it has been, echoing it back on
    every line is noise — worse on the current repo's own list, where it repeats
    identically all the way down. `#outcome/` and `#owner/` go for the same
    reason: the report renders what they mean on the line, in words.
    """
    out = REPO_TAG_RE.sub("", item)
    stripped = OWNER_TAG_RE.sub("", OUTCOME_TAG_RE.sub("", out))
    if stripped != out:
        # Removing a trailing tag can leave the dash that introduced it hanging
        # ("… #outcome/dropped —"). Only ever cleaned up when a tag actually
        # went, so an item that genuinely ends in a dash keeps it.
        out = stripped.rstrip().rstrip("—-")
    return out.rstrip()


def flag_for(item):
    """"blocked" / "credential" / None — why this item outranks its repo.

    Checked in order, so an item that is both reports as blocked: that is the one
    that says nothing else can start.
    """
    for name, regexes in _FLAG_RES:
        if any(r.search(item) for r in regexes):
            return name
    return None

# `scripts/foo.py`, `foo.py`, `path/to/bar.sh` — a filename with an extension,
# or a slashed path. Matched inside backticks only: unquoted prose produces
# false hits on ordinary sentences, and every item that names a real file in
# this vault's notes backticks it.
FILE_REF_RE = re.compile(r'`([^`\s]*[\w-]+\.[A-Za-z0-9]{1,6}|[^`\s]*/[^`\s]+)`')


def _collect(text, want):
    """Text of every item under `## Follow-ups` matching `want`, in order.

    A note with no `## Follow-ups` heading yields nothing rather than erroring —
    notes written before the section existed are still perfectly good notes.

    **Wrapped lines are joined into the item they belong to.** These items are
    prose and routinely run to three or four lines; reading only the first was
    both a truncated report and a broken attribution, since the repo name is as
    likely to sit on the second line as the first. A continuation is an indented
    line under an item — including an indented sub-bullet, which belongs to the
    item above it rather than being an item of its own.
    """
    items = []
    current = None

    def flush():
        nonlocal current
        if current is not None:
            items.append(" ".join(current).strip())
            current = None

    in_section = False
    for line in text.splitlines():
        if line.startswith("## "):
            flush()
            in_section = line.strip() == "## Follow-ups"
            continue
        if not in_section:
            continue

        if want.match(line):
            flush()
            current = [want.match(line).group(1).strip()]
        elif line[:1] == "-":
            flush()  # any other top-level bullet, ticked or not: ends this one
        elif current is not None and line[:1].isspace() and line.strip():
            current.append(line.strip())
        elif not line.strip():
            flush()  # a blank line closes the item; wrapped lines never contain one
    flush()
    return items


def open_followups(text):
    """Every `- [ ]` item under `## Follow-ups` — the things still to do."""
    return _collect(text, FOLLOWUP_ITEM_RE)


def done_followups(text):
    """Every `- [x]` item under `## Follow-ups` — the things already ticked.

    Not a report of its own: nobody wants a list of what they finished. It is
    read so that an item ticked off in *today's* note can close the same task
    left unchecked in an older one, which is otherwise reported as open forever
    — the older wording is never gone back and edited, and shouldn't have to be.

    Every tick, whatever it says. Callers split them with closes() above: a
    `#outcome/dropped` or `#outcome/handed-off` tick is a real statement about
    the item and not a claim that the work happened.
    """
    return _collect(text, FOLLOWUP_DONE_RE)


def unmarked_ticks(text):
    """`- [x]` items carrying no `#outcome/` tag at all.

    Counted, never listed. The point is not to nag about history — every note
    written before the convention is full of these — but to say, once a vault has
    started recording outcomes, how much of the window still cannot answer "was
    that finished, or abandoned?".
    """
    return [item for item in done_followups(text) if not OUTCOME_TAG_RE.search(item)]


REPO_NAME_RE = re.compile(r'^[A-Za-z0-9][A-Za-z0-9._-]*$')


def vault_repos(vault):
    """Repo names this vault already knows — the vocabulary prose is matched on.

    Two sources, both things the vault already records rather than anything
    invented here:

    - practice notes' `repos:` frontmatter, which has been naming the repos a
      practice was observed in since long before this, consistently spelled
    - `#repo/<name>` tags already written into daily notes, so the write-side
      convention teaches this side new repo names as a side effect of being used

    Matching against a closed vocabulary is what stops inference from turning
    ordinary hyphenated prose into a repo. The cost is that a repo the vault has
    never mentioned reads as unattributed until one item carries its tag — which
    is the honest answer, and self-correcting from the first tagged item on.
    """
    names = set()
    vault = Path(vault)

    def add(value):
        value = (value or "").strip()
        # `repos:` is free text and has picked up the occasional non-repo note
        # ("local-mac (2026-07-28)"). A repo name has no spaces.
        if value and REPO_NAME_RE.match(value):
            names.add(value)

    practices = vault / "practices"
    if practices.is_dir():
        for note in practices.rglob("*.md"):
            data, _ = parse_frontmatter(note.read_text(encoding="utf-8", errors="replace"))
            if not data:
                continue
            repos = data.get("repos")
            if isinstance(repos, list):
                for r in repos:
                    add(r)
            elif isinstance(repos, str):
                add(repos)

    for note in vault.glob("*.md"):
        for m in REPO_TAG_RE.finditer(note.read_text(encoding="utf-8", errors="replace")):
            add(m.group(1))

    return names


def note_context_repo(text, known_repos):
    """The one repo a whole daily note is about, from its `## Built` section(s).

    Most follow-ups are written in the middle of a day's work and never repeat
    the repo, because in context it was obvious — while the `## Built` bullets
    right above them do name it ("`housemaster-backend`: finished …"). That
    makes the note a usable fallback for its own items.

    **The heading counts, and counts most.** A note that spans several work
    streams labels each one `## Built (<repo>: what happened)`, so the label is
    the most deliberate statement of a repo anywhere in the note. Reading only
    the bullets threw that away and — worse — let a single incidental mention in
    one body win on a day whose three labels named three different repos, which
    is the exact wrong answer this function's strictness exists to avoid.

    Deliberately strict: returned only when the `## Built` heading(s) and bullets
    together name exactly one known repo. A day that touched three is precisely
    the day this would guess wrong, and a wrong repo is worse than none — it
    files the item under somewhere you will not look for it.
    """
    built = []
    in_built = False
    for line in text.splitlines():
        if line.startswith("## "):
            in_built = line.strip().startswith("## Built")
            if in_built:
                built.append(line)   # the label names the repo — keep it
            continue
        if in_built:
            built.append(line)
    blob = "\n".join(built)
    hits = {r for r in known_repos if mention_re(r).search(blob)}
    return hits.pop() if len(hits) == 1 else None


def current_repo(start=None):
    """(name, basis) for the repo a caller is standing in, or (None, reason).

    Name is the origin URL's final path segment when there is an origin, else
    the toplevel directory's name — origin first because that is what the vault
    records, and a local checkout is routinely cloned into a differently named
    directory. `basis` is returned so a report can say what it matched on
    instead of leaving a surprising grouping unexplained.
    """
    cwd = str(start) if start else None

    def git(*args):
        try:
            out = subprocess.run(("git", *args), cwd=cwd, capture_output=True,
                                 text=True, timeout=5)
        except (OSError, subprocess.SubprocessError):
            return None
        return out.stdout.strip() if out.returncode == 0 else None

    if git("rev-parse", "--is-inside-work-tree") != "true":
        return None, "not inside a git repository"

    url = git("remote", "get-url", "origin")
    if url:
        name = url.rstrip("/").rsplit("/", 1)[-1].rsplit(":", 1)[-1]
        if name.endswith(".git"):
            name = name[:-4]
        if name:
            return name, "origin URL"

    top = git("rev-parse", "--show-toplevel")
    if top:
        return Path(top).name, "checkout directory name (no origin)"
    return None, "not inside a git repository"


def attribute(item, known_repos, current=None, repo_files=None, context=None):
    """(repo, basis) for one follow-up item, or (None, None) if unattributable.

    Signals, strongest first — an explicit tag beats a guess, a guess from the
    item's own words beats one from its surroundings, and every basis is
    returned so a report can show its work instead of asserting a grouping:

    1. a `#repo/<name>` tag, whatever `known_repos` says — it was recorded by
       something that knew, and an unfamiliar name means a new repo, not a typo
       to second-guess
    2. a known repo name appearing in the item's prose
    3. a backticked file path tracked in `repo_files`, which resolves to
       `current` — the caller's own checkout is the only one whose files can be
       listed, so this signal can confirm "mine" and never names someone else's
    4. `context`, the single repo the item's note is about (see
       note_context_repo) — the weakest, and the only one that can be right
       about the day while wrong about the item
    """
    m = REPO_TAG_RE.search(item)
    if m:
        return m.group(1), "#repo tag"

    hits = sorted(r for r in known_repos if mention_re(r).search(item))
    if len(hits) == 1:
        return hits[0], "repo named in the item"
    if len(hits) > 1:
        # Two repos named in one item. Longest wins only when it *contains* the
        # others (`housemaster-backend` over `backend`); genuinely distinct
        # repos in one item mean the item spans both, and picking one would be
        # a coin flip presented as a fact.
        longest = max(hits, key=len)
        if all(h == longest or h in longest for h in hits):
            return longest, "repo named in the item"
        return None, None

    if current and repo_files:
        for ref in FILE_REF_RE.findall(item):
            if ref.lstrip("./") in repo_files:
                return current, "file tracked in this repo"

    if context:
        return context, "this note's ## Built section, not the item itself"
    return None, None


def repo_file_index(root, limit=20000):
    """Tracked paths in a repo, as a set, for matching a backticked file ref.

    Tracked only: an untracked build artefact is not evidence an item belongs
    here. Bounded, because this runs interactively and a monorepo should cost a
    truncated index rather than a hang — a miss degrades to "unattributed",
    which the caller still reports.
    """
    try:
        out = subprocess.run(("git", "ls-files"), cwd=str(root), capture_output=True,
                             text=True, timeout=10)
    except (OSError, subprocess.SubprocessError):
        return set()
    if out.returncode != 0:
        return set()
    paths = set()
    for line in out.stdout.splitlines()[:limit]:
        line = line.strip()
        if not line:
            continue
        paths.add(line)
        paths.add(line.rsplit("/", 1)[-1])  # basename, for `guard-vault-commit.sh`
    return paths


def annotate(records, known_repos, current=None, repo_files=None, text=None,
             context=None):
    """Stamp each record with `repo` and `basis`, in place. -> the same list.

    Attribution used to happen as a side effect of grouping, which was fine while
    grouping was the only thing that needed it. Threading needs it *earlier* —
    two items can only be the same task if they belong to the same repo — and
    doing it twice would mean two answers to one question. So it is a step of its
    own now, and group_for_repo below reads what this wrote.
    """
    get = text or (lambda i: i)
    ctx = context or (lambda i: None)
    for record in records:
        found, basis = attribute(get(record), known_repos, current, repo_files,
                                 ctx(record))
        record["repo"], record["basis"] = found, basis
    return records


def group_for_repo(items, repo, known_repos, repo_files=None, text=None, context=None):
    """Split items into (mine, elsewhere, unknown), preserving input order.

    Every input item lands in exactly one bucket and none are discarded — the
    caller is expected to print all three, because the total is the number the
    reader came for. `mine` is empty when `repo` is None; nothing is "mine"
    when we don't know where we are.

    `items` may be plain strings or richer records; pass `text` to pull the item
    text out of a record, and the record itself is what comes back. Each element
    is returned as (item, basis) so a report can attribute its own guess rather
    than presenting a grouping as if it were recorded fact. `context` is a
    callable from record to that note's context repo, for the weakest signal.
    """
    get = text or (lambda i: i)
    ctx = context or (lambda i: None)
    mine, elsewhere, unknown = [], [], []
    for item in items:
        # Pre-stamped by annotate() when the caller ran it — grouping must reach
        # the same verdict as threading did, and the way to guarantee that is to
        # reuse the answer rather than to recompute it identically.
        if isinstance(item, dict) and "repo" in item:
            found, basis = item["repo"], item["basis"]
        else:
            found, basis = attribute(get(item), known_repos, repo, repo_files,
                                     ctx(item))
        if found is None:
            unknown.append((item, None))
        elif repo and found == repo:
            mine.append((item, basis))
        else:
            elsewhere.append((item, f"{found} — {basis}"))
    return mine, elsewhere, unknown
