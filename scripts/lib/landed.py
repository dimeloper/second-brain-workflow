"""Has the work a follow-up describes already landed on the repo's main branch?

    from lib.landed import refs, evaluate, Verdict

A follow-up like "Merge Flutter barcode PR #28 and ship TestFlight IPA" names
something checkable. The repo is on disk, the PR has a state, and the branch
either is or isn't an ancestor of main — but nothing read any of that, so an
item stayed open in the report for as long as it took someone to notice by hand
that it had been done days ago.

Two halves, kept in one module because they share the definition of "a ref":

- **extraction** — which items carry something checkable at all. Most don't, and
  that is what keeps this cheap: an item with no ref is never probed, so the
  cost is proportional to the checkable items rather than to the report.
- **probing** — locating that repo on this machine and asking git or `gh`.

Deliberately conservative in both directions. A missed ref costs one unchecked
item, which is exactly the report you get today. A *wrong* verdict tells you
something is done when it isn't, and this module's whole value is that you can
believe it — so every failure (repo not found, `gh` absent, offline, timed out)
resolves to `unchecked` with the reason attached, never to a guess.

**Never writes, never fetches.** `gh` is a live read and authoritative for PR
state; the git-based verdicts read whatever `origin/*` was last fetched, and say
how old that is rather than pretending to be current. Running `git fetch` across
someone else's checkouts to answer a status question is a side effect a read-only
report has no business having.

Read-only. Stdlib only.
"""

import json
import os
import re
import shutil
import subprocess
import time
from concurrent.futures import ThreadPoolExecutor, TimeoutError as FuturesTimeout
from pathlib import Path

from lib.config import load as load_config
from lib.registry import read as registry_read

# --- what counts as a ref ---------------------------------------------------
#
# Each of these also feeds followup_threads.py's strongest same-thread signal:
# two items naming the same PR are the same task restated. One definition, two
# consumers, for the same reason lib/followups.py gives — two implementations of
# "the item mentions PR #28" would drift into disagreeing, and then the report
# would thread items it refused to check and check items it refused to thread.

# `PR #28`, `pull request 28`, or a bare `#28`. The bare form requires a digit
# immediately after the `#`, which is what keeps `#repo/calorie-counter-ai` —
# present on nearly every item — from reading as a reference to something.
PR_REF_RE = re.compile(
    r'(?:\bPRs?\s*#?|\bpull\s+requests?\s*#?|(?<![\w/])#)(\d{1,6})(?![\w.])',
    re.IGNORECASE)

# A commit, backticked — unquoted prose produces hex-looking false hits, and
# every item in this vault that names a commit backticks it. Hex alone is not
# enough: `3017620422003` is a barcode and `deadbeef` is a word, so a real SHA
# has to have both a digit and a hex letter in it.
#
# The stated cost: an all-digit short SHA is missed, and about one in
# twenty-five is. That is the deliberate side of the trade — the alternative is
# an "unchecked" line under every item quoting a barcode or an order number,
# and the item that prompted this feature quotes one. A missed check reads
# exactly like today's report; a wrong "landed" would not.
SHA_REF_RE = re.compile(r'`([0-9a-f]{7,40})`')

# A branch, backticked, and only with a conventional prefix. Matching any
# slashed token would swallow file paths, which `lib/followups.py` already reads
# as a different kind of evidence entirely.
BRANCH_REF_RE = re.compile(
    r'`((?:feature|feat|fix|bugfix|hotfix|chore|release|refactor|docs|test)'
    r'/[A-Za-z0-9._\-/]+)`')


def _looks_like_sha(value):
    return any(c.isdigit() for c in value) and any(c in "abcdef" for c in value)


def refs(item):
    """[(kind, value)] for everything checkable in one item's text, deduped.

    Kinds are "pr", "sha", "branch". Order is stable (pr, sha, branch, each
    in first-appearance order) so a report's evidence line does not reshuffle
    between runs.
    """
    found = []
    seen = set()

    def add(kind, value):
        if (kind, value) not in seen:
            seen.add((kind, value))
            found.append((kind, value))

    for m in PR_REF_RE.finditer(item):
        add("pr", m.group(1).lstrip("0") or m.group(1))
    for m in SHA_REF_RE.finditer(item):
        if _looks_like_sha(m.group(1)):
            add("sha", m.group(1))
    for m in BRANCH_REF_RE.finditer(item):
        add("branch", m.group(1))
    return found


# --- locating the repo ------------------------------------------------------
#
# The render registry cannot answer this on its own. It names the repos the
# engine has *rendered into*, which on this machine is three of them — the repo
# that prompted this feature is not among them, and never will be unless someone
# onboards it. So the registry is a fast first source, not the source.
#
# The scan is the same shape sbw_scan_rendered_repos in lib/registry.sh uses,
# reading the same two config keys, so the two cannot disagree about where repos
# on this machine live or how deep it is reasonable to look.

CACHE_FILE = "repo-paths"

_SKIP_DIRS = {
    "node_modules", "Library", "Applications", "Pods", "build", "dist",
    "vendor", "target", "__pycache__", ".venv", "venv", ".next", ".expo",
    ".dart_tool", "DerivedData",
}


def cache_path():
    base = os.environ.get("XDG_CONFIG_HOME") or str(Path.home() / ".config")
    return Path(base) / "second-brain-workflow" / CACHE_FILE


def read_cache(path=None):
    """{repo name: absolute path}. Missing or unreadable file -> {}.

    `name<TAB>path` per line, blank lines and `#` comments ignored — the same
    hand-editable shape as the render registry next to it, so someone whose repo
    lives somewhere the scan will never reach can just write the line.
    """
    path = Path(path) if path else cache_path()
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        return {}
    out = {}
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        name, tab, target = line.partition("\t")
        if tab and name.strip() and target.strip():
            out[name.strip()] = target.strip()
    return out


def write_cache(mapping, path=None):
    """Replace the cache. Never raises — a read-only report is not a failure
    because a config directory is."""
    path = Path(path) if path else cache_path()
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        body = "".join(f"{name}\t{mapping[name]}\n" for name in sorted(mapping))
        tmp = path.with_name(path.name + ".tmp")
        tmp.write_text(body, encoding="utf-8")
        os.replace(tmp, path)
    except OSError:
        pass


def _git(repo, *args, timeout=10):
    """CompletedProcess, or None when git could not run at all."""
    try:
        return subprocess.run(("git", "-C", str(repo), *args),
                              capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.SubprocessError):
        return None


def origin_name(repo):
    """The repo's name as the vault records it: origin's last path segment.

    Same derivation as lib/followups.current_repo, and for the same reason — a
    checkout is routinely cloned into a differently named directory, and the
    `#repo/` tags were written from origin.
    """
    out = _git(repo, "remote", "get-url", "origin", timeout=5)
    if out is None or out.returncode != 0:
        return None
    url = out.stdout.strip().rstrip("/")
    if not url:
        return None
    name = url.rsplit("/", 1)[-1].rsplit(":", 1)[-1]
    return name[:-4] if name.endswith(".git") else name


def _is_repo(path, name):
    """Is `path` a checkout of `name`? Origin first, directory name as fallback.

    The fallback matters for a repo cloned before it had a remote, and for the
    fixture repos in this project's own tests, which have no origin at all.
    """
    path = Path(path)
    if not (path / ".git").exists():
        return False
    found = origin_name(path)
    return found == name if found else path.name == name


def scan_roots(cfg=None):
    """([Path], depth) — where to look for repos, and how deep."""
    cfg = cfg or load_config()
    roots = [Path(p).expanduser() for p in cfg["SBW_SCAN_ROOTS"].split(":") if p]
    try:
        depth = int(cfg["SBW_SCAN_DEPTH"])
    except (TypeError, ValueError):
        depth = 5
    return roots, max(1, depth)


def _scan_index(roots, depth):
    """{directory name: path} for every checkout under `roots`, in one walk.

    One walk, not one per name. The names that miss are the expensive ones —
    a repo that is not on this machine can only be established by exhausting the
    search — and a report naming four such repos would otherwise pay for four
    full traversals of $HOME to learn the same thing four times.

    Indexed by directory name, and the git remote is never consulted here: a
    `git remote` call per candidate would turn a bounded walk into hundreds of
    subprocesses. The caller confirms the one directory it picked. A repo whose
    directory name differs from its origin is therefore not found by the scan,
    which reports as unchecked and is fixable with one line in the cache file.
    """
    index = {}
    for root in roots:
        if not root.is_dir():
            continue
        base_depth = len(root.parts)
        for dirpath, dirnames, _ in os.walk(root, topdown=True, followlinks=False):
            here = Path(dirpath)
            if len(here.parts) - base_depth >= depth:
                dirnames[:] = []
                continue
            dirnames[:] = [d for d in dirnames
                           if d not in _SKIP_DIRS and not d.startswith(".")]
            for name in dirnames:
                if name not in index and (here / name / ".git").exists():
                    index[name] = here / name
    return index


class Resolver:
    """Repo name -> checkout path, resolved once per run and cached on disk.

    Three sources, cheapest first: the on-disk cache (revalidated, since a repo
    can be moved or deleted), the render registry, then a bounded walk of
    SBW_SCAN_ROOTS. Only the walk is expensive, and only the first run for a
    given repo pays it.

    A name that resolves nowhere is remembered as unresolved *for this run only*
    — never written to the cache, because "not found today" is a fact about
    today's filesystem and caching it would outlive the `git clone` that fixes it.
    """

    def __init__(self, cfg=None, cache=None, roots=None, depth=None):
        self._cache = read_cache(cache) if cache is not False else {}
        self._cache_file = cache if isinstance(cache, (str, Path)) else None
        if roots is None or depth is None:
            scanned_roots, scanned_depth = scan_roots(cfg)
            roots = scanned_roots if roots is None else roots
            depth = scanned_depth if depth is None else depth
        self._roots, self._depth = roots, depth
        self._resolved = {}
        self._index = None
        self._dirty = False

    def __call__(self, name):
        if name in self._resolved:
            return self._resolved[name]

        hit = self._cache.get(name)
        if hit and _is_repo(hit, name):
            self._resolved[name] = Path(hit)
            return self._resolved[name]

        for entry in registry_read():
            if _is_repo(entry, name):
                self._remember(name, Path(entry))
                return self._resolved[name]

        if self._index is None:
            self._index = _scan_index(self._roots, self._depth)
        found = self._index.get(name)
        if found is not None and _is_repo(found, name):
            self._remember(name, found)
            return found

        self._resolved[name] = None
        return None

    def _remember(self, name, path):
        self._resolved[name] = path
        self._cache[name] = str(path)
        self._dirty = True

    def flush(self):
        if self._dirty:
            write_cache(self._cache, self._cache_file)
            self._dirty = False


# --- probing ----------------------------------------------------------------

LANDED, OPEN, CLOSED, UNCHECKED = "landed", "open", "closed", "unchecked"


class Verdict:
    """One ref's answer: a state, the sentence explaining it, and its ref.

    `state` is one of landed / open / closed / unchecked. `closed` is separate
    from both because a PR closed without merging is neither done nor progressing
    — it is the case where the item is still real and the thing you remember
    doing about it has been thrown away.
    """

    __slots__ = ("state", "detail", "ref", "repo")

    def __init__(self, state, detail, ref=None, repo=None):
        self.state, self.detail, self.ref, self.repo = state, detail, ref, repo

    @property
    def landed(self):
        return self.state == LANDED

    def __repr__(self):  # pragma: no cover - debugging aid
        return f"Verdict({self.state!r}, {self.detail!r})"


def default_base(repo):
    """The ref to ask "did this land" against, and how we knew.

    origin's HEAD when the checkout records one, then the conventional remote
    names, then the *local* branches — the last because a repo with no remote at
    all still has a main, and refusing to answer for it would make this
    untestable without a network.
    """
    out = _git(repo, "symbolic-ref", "--short", "refs/remotes/origin/HEAD", timeout=5)
    if out is not None and out.returncode == 0 and out.stdout.strip():
        return out.stdout.strip()
    for candidate in ("origin/main", "origin/master", "main", "master"):
        out = _git(repo, "rev-parse", "--verify", "--quiet", candidate, timeout=5)
        if out is not None and out.returncode == 0:
            return candidate
    return None


def fetch_age_days(repo):
    """Days since this checkout last heard from its remote, or None.

    A git-based verdict is only as current as the last fetch, and this module
    deliberately does not fetch. Saying how stale the answer is turns that from a
    hidden assumption into a line the reader can weigh.
    """
    for name in ("FETCH_HEAD", "refs/remotes/origin/HEAD"):
        path = Path(repo) / ".git" / name
        try:
            return int((time.time() - path.stat().st_mtime) // 86400)
        except OSError:
            continue
    return None


def _ancestor(repo, rev, base):
    out = _git(repo, "merge-base", "--is-ancestor", rev, base)
    if out is None:
        return None
    if out.returncode == 0:
        return True
    if out.returncode == 1:
        return False
    return None  # 128: unknown revision — not "no", "cannot say"


def _freshness(repo):
    age = fetch_age_days(repo)
    if age is None:
        return ""
    return " (last fetched today)" if age < 1 else f" (last fetched {age}d ago)"


def probe_pr(repo, number, repo_name):
    if shutil.which("gh") is None:
        return Verdict(UNCHECKED, f"PR #{number} unchecked — gh not installed",
                       ("pr", number), repo_name)
    try:
        out = subprocess.run(
            ("gh", "pr", "view", str(number), "--json", "number,state,mergedAt"),
            cwd=str(repo), capture_output=True, text=True, timeout=15)
    except (OSError, subprocess.SubprocessError):
        return Verdict(UNCHECKED, f"PR #{number} unchecked — gh did not run",
                       ("pr", number), repo_name)
    if out.returncode != 0:
        reason = (out.stderr or "").strip().splitlines()
        why = reason[0] if reason else "gh reported an error"
        return Verdict(UNCHECKED, f"PR #{number} unchecked — {why}",
                       ("pr", number), repo_name)
    try:
        data = json.loads(out.stdout)
    except ValueError:
        return Verdict(UNCHECKED, f"PR #{number} unchecked — unreadable gh output",
                       ("pr", number), repo_name)

    state = (data.get("state") or "").upper()
    merged = (data.get("mergedAt") or "")[:10]
    if state == "MERGED":
        when = f" {merged}" if merged else ""
        return Verdict(LANDED, f"PR #{number} merged{when}", ("pr", number), repo_name)
    if state == "CLOSED":
        return Verdict(CLOSED, f"PR #{number} closed without merging",
                       ("pr", number), repo_name)
    return Verdict(OPEN, f"PR #{number} open, not merged", ("pr", number), repo_name)


def probe_sha(repo, sha, repo_name):
    base = default_base(repo)
    if base is None:
        return Verdict(UNCHECKED, f"`{sha}` unchecked — no main branch found",
                       ("sha", sha), repo_name)
    answer = _ancestor(repo, sha, base)
    if answer is None:
        return Verdict(UNCHECKED, f"`{sha}` unchecked — not a commit in this checkout",
                       ("sha", sha), repo_name)
    if answer:
        return Verdict(LANDED, f"`{sha}` is on {base}{_freshness(repo)}",
                       ("sha", sha), repo_name)
    return Verdict(OPEN, f"`{sha}` not on {base}{_freshness(repo)}",
                   ("sha", sha), repo_name)


def probe_branch(repo, branch, repo_name):
    base = default_base(repo)
    if base is None:
        return Verdict(UNCHECKED, f"`{branch}` unchecked — no main branch found",
                       ("branch", branch), repo_name)
    tip = None
    for candidate in (f"origin/{branch}", branch):
        out = _git(repo, "rev-parse", "--verify", "--quiet", candidate, timeout=5)
        if out is not None and out.returncode == 0:
            tip = candidate
            break
    if tip is None:
        return Verdict(UNCHECKED, f"`{branch}` unchecked — no such branch in this checkout",
                       ("branch", branch), repo_name)
    if tip == base:
        return Verdict(UNCHECKED, f"`{branch}` unchecked — it is the base branch",
                       ("branch", branch), repo_name)
    answer = _ancestor(repo, tip, base)
    if answer is None:
        return Verdict(UNCHECKED, f"`{branch}` unchecked — could not compare with {base}",
                       ("branch", branch), repo_name)
    if answer:
        return Verdict(LANDED, f"`{branch}` is merged into {base}{_freshness(repo)}",
                       ("branch", branch), repo_name)
    return Verdict(OPEN, f"`{branch}` not merged into {base}{_freshness(repo)}",
                   ("branch", branch), repo_name)


_PROBES = {"pr": probe_pr, "sha": probe_sha, "branch": probe_branch}


def _verdict_rank(verdict):
    # What a reader most needs to see first when one item carries several refs.
    # `landed` outranks the rest because it is the one that changes what you do
    # next; `unchecked` sorts last because it is the absence of an answer.
    return {LANDED: 0, CLOSED: 1, OPEN: 2, UNCHECKED: 3}[verdict.state]


def evaluate(subjects, resolver=None, max_workers=4, budget=20.0):
    """{key: [Verdict]} for every subject carrying a checkable ref.

    `subjects` is [(key, text, repo_name)]. A subject with no ref, or with no
    repo to check it against, is simply absent from the result — the caller
    prints what it got and says nothing about the rest, which is the honest
    report when there was never anything to check.

    Bounded on purpose. This runs while someone waits for a task list: probes go
    out in parallel, each subprocess has its own timeout, and the pool as a whole
    has `budget` seconds before the stragglers are reported as timed out rather
    than waited on.
    """
    resolver = resolver if resolver is not None else Resolver()
    work = []
    for key, text, repo_name in subjects:
        if not repo_name:
            continue
        item_refs = refs(text)
        if not item_refs:
            continue
        repo = resolver(repo_name)
        if repo is None:
            work.append((key, None, repo_name, item_refs[:1]))
            continue
        work.append((key, repo, repo_name, item_refs))

    results = {}
    jobs = []
    with ThreadPoolExecutor(max_workers=max_workers) as pool:
        for key, repo, repo_name, item_refs in work:
            if repo is None:
                results.setdefault(key, []).append(Verdict(
                    UNCHECKED,
                    f"unchecked — no checkout of `{repo_name}` found under SBW_SCAN_ROOTS",
                    None, repo_name))
                continue
            for kind, value in item_refs:
                jobs.append((key, kind, value, repo_name,
                             pool.submit(_PROBES[kind], repo, value, repo_name)))

        deadline = time.monotonic() + budget
        for key, kind, value, repo_name, future in jobs:
            remaining = max(0.0, deadline - time.monotonic())
            try:
                results.setdefault(key, []).append(future.result(timeout=remaining))
            except FuturesTimeout:
                future.cancel()
                results.setdefault(key, []).append(Verdict(
                    UNCHECKED, f"`{value}` unchecked — timed out", (kind, value),
                    repo_name))
            except Exception:  # noqa: BLE001 - a probe must never break the report
                results.setdefault(key, []).append(Verdict(
                    UNCHECKED, f"`{value}` unchecked — probe failed", (kind, value),
                    repo_name))

    if hasattr(resolver, "flush"):
        resolver.flush()
    for key in results:
        results[key].sort(key=_verdict_rank)
    return results
