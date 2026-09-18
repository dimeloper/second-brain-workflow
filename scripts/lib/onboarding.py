"""Whether a repo is onboarded — and whether that question was already answered.

    from lib.onboarding import classify, decline, undecline
    state, detail = classify(repo)

`update-second-brain` runs inside the repo that was worked on, so it is standing
in the one place that knows the answer for free. A repo that has never been
rendered into is a repo whose sessions load none of these rules, and nothing
said so: the wrap-up wrote the daily note, pushed the vault, and left the gap
exactly where it found it.

Five states, and the two that are *not* "not-onboarded" are the point:

    onboarded       the registry names it, or it carries rendered output
    not-onboarded   neither — worth asking about, once
    declined        asked already, answered never. Say nothing.
    skip            the engine checkout or a vault: never onboarding targets
    undetermined    no such directory — cannot tell, and does not guess

`declined` exists because a wrap-up is a per-session event and a decision about
a repo is not. A client's repo, an upstream you contribute to, a throwaway
clone: the honest answer is "no", and a prompt that asks again every session
turns that answer into noise — the state a checkbox-shaped question is worst at.

File: ${XDG_CONFIG_HOME:-~/.config}/second-brain-workflow/onboard-declined —
the same directory and the same format as the repo registry next to it, one
entry per line, `reason=` optional:

    /Users/me/work/their-repo\treason=not mine to add conventions to

Deliberately a *separate* file from the registry. The registry is the set of
repos this machine rendered into; this is the set it deliberately did not, and
folding them together would mean a mode field that has to carry "none" — a
value render.py is right to refuse, since every mode it understands is an answer
to "who sees your conventions".

Read-only apart from decline()/undecline(). Stdlib only.
"""

import os
from pathlib import Path

from lib.registry import read_entries, registry_path, rendered, write_entries

STATES = ("onboarded", "not-onboarded", "declined", "skip", "undetermined")

DECLINED_FILENAME = "onboard-declined"


def declined_path():
    return registry_path().with_name(DECLINED_FILENAME)


def declined_entries(path=None):
    """[(repo_path, fields)] on the never-ask list, in file order."""
    return read_entries(path or declined_path())


def declined_fields(repo, path=None):
    """The recorded fields for `repo`, or None when it is not on the list.

    Matched on realpath, the form decline() stores, so the same repo reached
    through a symlinked parent resolves to its one entry.
    """
    entry = os.path.realpath(str(repo))
    for candidate, fields in declined_entries(path):
        if candidate == entry:
            return fields
    return None


def decline(repo, reason=None, warn=None):
    """Record that onboarding this repo was offered and refused. -> bool.

    The reason is free text and optional, and it is the half worth writing: six
    months later "not mine to add conventions to" is a decision, while a bare
    path is a repo somebody has to re-derive the argument about.
    """
    path = declined_path()
    entry = os.path.realpath(str(repo))
    entries = dict(declined_entries(path))
    fields = dict(entries.get(entry, {}))
    if reason:
        # Tabs and newlines are the record's own separators; a reason carrying
        # one would split into a field nothing reads back.
        fields["reason"] = " ".join(str(reason).split())
    entries[entry] = fields
    return write_entries(
        path, entries, warn,
        describe=lambda p, why: (
            f"could not record the decline in {p}: {why}. The answer holds for "
            "this session; the next wrap-up in this repo will ask again."
        ),
    )


def undecline(repo, warn=None):
    """Take `repo` off the never-ask list. -> True when the list no longer names it.

    A repo the list never named is already off it, so that is True rather than
    an error — the same contract registry.forget() has, and for the same reason:
    the caller asked for a state, not for an event.
    """
    path = declined_path()
    entry = os.path.realpath(str(repo))
    entries = dict(declined_entries(path))
    if entry not in entries:
        return True
    del entries[entry]
    return write_entries(
        path, entries, warn,
        describe=lambda p, why: (
            f"could not update {p}: {why}. The repo is still on the never-ask "
            "list, so a wrap-up here will stay silent about onboarding."
        ),
    )


def engine_root():
    """This engine checkout — scripts/lib/onboarding.py's own grandparent."""
    return Path(__file__).resolve().parent.parent.parent


def is_vault(repo):
    """A vault, by the file that identifies one to every other check here.

    `vault.json` rather than `practices/`: the guard, init-vault and
    lib/vault_state all key off it, and a repo that merely has a practices
    directory is a repo, not a vault.
    """
    return (Path(repo) / "vault.json").is_file()


def is_git_worktree(repo):
    """Is there a git work tree here? `--local` has nothing to work with without
    one — there is no remote to keep the rendered files out of."""
    return (Path(repo) / ".git").exists()


def classify(repo):
    """(state, detail) for one repo path. Reads; never writes, never renders.

    Order matters, and it is not the order the states are listed in:

    1. **skip before anything else** — the engine checkout and a vault are never
       onboarding targets, and asking about either is asking a question with no
       right answer.
    2. **onboarded before declined** — a repo that was declined and later
       onboarded is onboarded, and the stale decline is said out loud rather
       than silently outranking the render that came after it.
    3. **declined before not-onboarded** — that is the whole job of the list.
    """
    root = Path(repo).expanduser()
    if not root.is_dir():
        return "undetermined", f"no such directory: {root}"

    resolved = Path(os.path.realpath(str(root)))
    if resolved == Path(os.path.realpath(str(engine_root()))):
        return "skip", (
            "this is the second-brain-workflow checkout itself — it is the "
            "source of the rules, not a target for them"
        )
    if is_vault(resolved):
        return "skip", (
            "this is a vault (vault.json) — a vault is written to, never "
            "rendered into"
        )

    registry = dict(read_entries())
    registered = str(resolved) in registry
    mode = (registry.get(str(resolved)) or {}).get("mode")
    has_output = rendered(resolved)
    refused = declined_fields(resolved)

    if registered or has_output:
        detail = []
        if registered:
            detail.append(f"registered (mode={mode or 'unknown'})")
        else:
            detail.append(
                "carries rendered output, but the registry does not name it — "
                f"`{engine_root()}/scripts/render.py {resolved}` records it"
            )
        if registered and not has_output:
            # Not this check's business to fix, and not its business to hide
            # either: re-asking "shall I onboard it?" about a repo that is
            # already registered would propose a render as if it were a first
            # one, when what it needs is the drift advice doctor already prints.
            detail.append(
                "no rendered output any more — `make doctor` says what to do"
            )
        if refused is not None:
            detail.append(
                "also on the never-ask list, which is stale now — clear it with "
                "`onboarding-state.py --undecline`"
            )
        return "onboarded", "; ".join(detail)

    if refused is not None:
        reason = refused.get("reason")
        return "declined", (
            f"asked once, answered never{f' — {reason}' if reason else ''}. "
            "`onboarding-state.py --undecline` puts it back in scope."
        )

    quiet = (
        "quiet onboarding (--local) is available"
        if is_git_worktree(resolved)
        else "no git work tree here, so --local has no remote to hide from; "
             "a shared render still works"
    )
    return "not-onboarded", (
        "no .sbw-version, no provenance marker, and the registry does not name "
        f"it. {quiet}"
    )
