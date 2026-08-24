# The vault commit guard

Full mechanics for [the reference's "A vault per machine"](REFERENCE.md#a-vault-per-machine)
model: creating a vault, what the commit guard blocks, the three ways it's
enforced, the trust model behind it, and what `make doctor` checks. Read the
README first for why any of this exists — this is the reference material,
not the pitch.

## Creating a vault

One vault per machine, each with its own `vault.json` (`id`, `remote`):

```bash
./scripts/init-vault.sh --path ~/vaults/work-brain --id work \
  --remote "git@github.com:YOUR_ACCOUNT/work-brain.git"
```

It scaffolds `practices/{app,backend,frontend,cross-cutting}`, `_templates/`,
`00-maps/`, `bases/`, a `.gitignore` and `vault.json`, runs `git init`, and
generates an empty index. It seeds no *domain* practice notes — those are earned
from real work — but does write the four cross-cutting notes describing how the
vault itself operates, because `update-second-brain` reads them at runtime.
Re-running is safe; `--adopt` lets it fill gaps in an existing vault — and,
since `--adopt` is the one other path that can add content to a vault, it
verifies the same identity (`vault.json`'s `id` and `remote`) the commit guard
checks below, via the shared `scripts/lib/vault-identity.sh`, before adding
anything. It only ever adds missing fixed scaffold files though — never
arbitrary content, never an overwrite, never a delete — so it doesn't need
the guard's path/size/secret checks, only the identity check.

**Remotes are compared as host, owner and repo**, not as literal strings.
`git@github.com:ORG/brain.git` and `https://github.com/ORG/brain` are one
repository written two ways, and the two sides of this comparison are written
by different hands — a human into `vault.json`, `git clone` or
`actions/checkout` into `origin` — so they disagree about transport and a
trailing `.git` routinely. Reading that as a repoint is a false alarm on a
correct setup, which is the fastest way to teach someone the check is noise.
Nothing else is normalised: a different host, owner or repo name is still a
repoint. `init-vault.sh` records the remote with a trailing `/` or `.git`
removed for the same reason, leaving transport exactly as given.

## The commit guard

**The vault is the isolation boundary, not the rule set.** Rules flow outward
freely: applying your own conventions to an employer's code is fine. The
direction that must never happen is a practice learned on employer work landing
in a personal or public repo — and that is a vault write. So every commit is
checked:

```bash
./scripts/guard-vault-commit.sh --expect-id work
```

or, so it doesn't need the flag every time, set once per machine in
`${XDG_CONFIG_HOME:-~/.config}/second-brain-workflow/config`:

```
SBW_EXPECTED_VAULT_ID=work
```

It blocks a staged path outside the vault's allowed set, a `vault.json` id that
isn't the one this machine expects, an `origin` that doesn't match the one
recorded in `vault.json`, a commit author that isn't the identity `vault.json`
declares, an implausibly large diff, deletion of an `enforced` note, content
vanishing from a daily note, conflict markers, and anything that looks like a
credential.

### Daily notes only ever grow

Two agent sessions wrapping up at the same time both read today's note, both
compose a block from the copy they read, and both write the whole file back. The
second write drops the first session's block, the commit records the clobbered
state, and `git status` then reports a clean tree — so nothing anywhere says a
day's work has gone. It happened twice on one evening; one block was recovered
only because a transcript was still open.

So a commit that removes lines from a `YYYY-MM-DD.md` is refused. A removed line
is fine if something took its place — the same line, the same line with its
checkbox ticked, or a line still carrying its opening clause (a typo fix, a
corrected SHA). What fails is content that simply stopped existing. Practice
notes are exempt: they are edited in place constantly, and holding them to
append-only would make this the check everyone routes around.

The prevention lives in
[`append-daily-block.py`](../scripts/append-daily-block.py), which `update-second-brain`
writes through: it takes the hash of the note you read and refuses the write if
the note moved in between. This check is the backstop for everything that
doesn't go through it.

One deliberate case removes lines legitimately — moving work into the note for
the day it actually happened. It needs both doors, because the two enforcement
tiers see different things:

```bash
./scripts/guard-vault-commit.sh --expect-id work --allow-daily-rewrite
git commit -m "docs: move the block to the day it happened

Daily-rewrite: filed a day late; boundary fixed against commit timestamps"
```

The flag answers the local run, which has no commit message yet; the trailer
answers the CI run, which has no command line. Use one without the other and CI
refuses what your machine allowed.

## Commit authorship

Everything above asks where content is *going*. This asks who the commit says
it is *from* — the mirror axis, and the two are independent. A commit can
satisfy every destination check, push with the correct credentials, and still
be authored by a personal identity, because `user.email` resolves from a chain
none of those checks look at. That happened: the first commit into an
employer-owned vault carried a personal address, and nothing noticed until it
was already in the repo's history.

Opt in per vault, with an `identity` object in `vault.json`:

```json
{
  "id": "work",
  "remote": "git@github.com:YOUR_ACCOUNT/work-brain.git",
  "identity": {
    "email": "you@work.example.com",
    "email_pattern": ".*@work\\.example\\.com$",
    "name": "Your Name"
  }
}
```

All three keys are optional. `email` must match exactly. `email_pattern` is a
regex, for EMU or `noreply` addresses that vary per repo where no single
address can be pinned — when both are present the pattern decides and `email`
is the address offered in the fix message. `name` is checked only if given. An
`identity` object that is absent, or present but empty, checks nothing; a
vault written before this existed behaves exactly as it did.

Those three are also the **whole vocabulary**, and a key outside it is an error
rather than a key to ignore. A misspelled `email_patern` declares nothing every
tool here can see: the guard would pass, and `make doctor` would report a vault
with no identity block at all — true of the parser, false of the file, and
pointing at the wrong fix. The check exists to stop an identity going unchecked
silently, so it refuses to be defeated one typo deep.

`--identity-email` on `init-vault.sh` writes the block when it creates a
`vault.json`. It won't edit one that already exists — that script only ever
adds scaffold it wrote itself — so it prints the JSON to add by hand instead.

**This blocks rather than warns**, which is a deliberate choice about a finding
that is a hygiene and attribution problem rather than a content leak. A warning
is effectively what the machine already produced: everything looked fine, and
the wrong author is now permanent in someone else's history. Before the commit
the fix is one command; after the push it needs a history rewrite on a repo you
may not control. And because the check is opt-in per vault, a block only ever
happens where someone declared they wanted one — so it can't become the routine
nuisance that teaches `git commit --no-verify`, which is the one habit that
would genuinely weaken every other check here.

A declared identity that *can't be read* — malformed JSON, `identity` set to
something that isn't an object, or an unrecognised key — fails closed rather
than passing. "Declared but unreadable" silently becoming "nothing to check" is
the same class of bug as the one this check exists to close.

The check runs in **three tiers**, and every one of them enforces it:

| Tier | What it reads | Skipped by |
|---|---|---|
| The staged index, invoked directly (`update-second-brain`) | the identity the commit *would* carry — `git var GIT_AUTHOR_IDENT`, which resolves `includeIf`, the environment and every fallback | not running it |
| The same, through the pre-commit hook | as above | `--no-verify` |
| `--range`/`--rev`, in CI | each commit's *recorded* author, named individually | nothing |

The last tier reads what the commit recorded rather than the current local
config, because by the time `docs/vault-ci/guard.yml` runs, whatever config
produced the commit is gone — and it is the only tier a local `--no-verify`
can't skip. `tests/test-author-identity.sh` asserts each tier independently, so
a check present in one path and absent in a parallel one fails the suite.

**An empty diff does not skip this check.** Every other check here reads the
diff and genuinely has nothing to examine without one, so the guard returns
early — but a commit that changes nothing still records an author, permanently.
Until that split existed, `git commit --allow-empty` was a bypass that didn't
even need `--no-verify`, and because the same early return gated `--range`, a
pushed empty commit cleared CI too. The "nothing staged" message now names
which half it skipped, since the old wording read as though the commit itself
had been cleared.

`make doctor` reports the same mismatch against the identity a commit *would*
be made with, so it surfaces at setup time instead of at the first commit.

## Adopting an existing vault

**New machine, vault already on a remote** — the common second-machine case,
and the one that goes wrong quietly if you follow the creation path instead.
Clone first, then adopt the clone:

```bash
git clone "git@github.com:YOUR_ACCOUNT/work-brain.git" ~/vaults/work-brain
./scripts/init-vault.sh --path ~/vaults/work-brain --id work --adopt
```

`--adopt` allows a non-empty directory and adds only what is missing —
directories, templates, the cross-cutting operating notes, the pre-commit hook.
It never edits or overwrites a file that already exists, `vault.json` included.
Before adding anything it runs the same identity check the commit guard runs,
so adopting the *wrong* vault fails rather than silently mixing two.

Creating instead of adopting is the mistake worth naming: you get a second
vault whose `vault.json` claims the first one's remote, and two vaults sharing
a remote is how one vault's notes get pushed over another's. `init-vault.sh`
refuses a `--remote` already claimed by the vault this machine's config points
at, naming the conflict.

What `--adopt` will *not* do is upgrade a manifest — that is the next section,
and the two halves of the same story.

## Upgrading an existing vault

**A vault only has the `vault.json` keys that existed when it was created.**
Every capability added since — the `identity` block above is the first, and
won't be the last — applies to vaults made after it shipped. There is no
automatic migration, and the two things that look like one aren't:

- **[`init-vault.sh --adopt`](#adopting-an-existing-vault) fills scaffold
  *files* only.** It adds missing directories, templates and cross-cutting
  notes, and it never edits an existing `vault.json`, because its one invariant
  is that it doesn't rewrite content it didn't write. So it will not add an
  `identity` block, and re-running it will not upgrade a manifest.
- **`--identity-email` only writes into a `vault.json` it creates.** Passed
  against a vault that already has one, it prints the JSON to add and changes
  nothing.

So the upgrade path is deliberately manual, and `make doctor` is what tells you
an upgrade is available: a vault with no `identity` block gets a line naming the
exact key to add. Add it to `vault.json` by hand:

```json
{
  "id": "work",
  "remote": "https://github.com/YOUR_ACCOUNT/work-brain.git",
  "identity": { "email_pattern": ".*@example\\.com$" },
  "schema_version": 1
}
```

then confirm the tooling reads it:

```bash
make doctor VAULT="$HOME/vaults/VAULT_NAME"
```

A vault that pins an identity reports `commits here would be authored as …`,
and a resolved address that disagrees with the declaration is an error (exit
2). If you get the "pins no commit author" line instead, the key didn't parse —
check it's inside the top-level object and that the JSON is still valid.

**Vaults predating v0.4.0 are the ones that matter most here**, because the
incident that motivated the check happened in one: a personal address in an
employer-owned vault's history, with every check that existed at the time
passing.

## Three enforcement tiers

Three things run this exact script, in increasing order of how hard they are
to skip, and none is a substitute for another:

- **The fast path.** `update-second-brain` runs it before every commit it
  makes — the common case, since that skill is the only write path for
  content.
- **The local backstop.** `init-vault.sh` installs it as this vault's
  `pre-commit` hook by default, so a hand-run `git commit` inside the vault —
  no skill, no agent, nobody remembering to invoke anything — is guarded too.
  It's idempotent (`--no-hook` opts out; re-running never clobbers an
  existing hook, ours or not) and derives its `--expect-id` the same way any
  other invocation does, since a git hook has nothing vault-specific it could
  trustworthily derive one from itself. `make doctor` reports a vault whose
  hook is missing or isn't ours, so an unguarded machine is visible rather
  than silently exposed.
- **The one that can't be skipped.** `git commit --no-verify` skips the
  pre-commit hook — including by an agent that decides a failing check is a
  reasonable thing to route around — and GitHub offers no pre-receive hook
  outside Enterprise. `--range`/`--rev` let this same script check a pushed
  commit range instead of a staged index (there's no staging area once a
  push has already happened), so `docs/vault-ci/guard.yml` can run it in CI
  on every push. **Be honest about what this does and doesn't fix:** CI
  catches a bypass *after* the push, not before — for a private vault that's
  containment, not prevention. The fix at that point is `git revert`, plus
  history rewriting and a rotated credential if whatever leaked was real, not
  an assumption that a red X means nothing happened. See
  `docs/vault-ci/README.md` for setup and this same caveat in more detail.

## Trust model

The expected id is a property of the *machine*, resolved from
`--expect-id` > `SBW_EXPECTED_VAULT_ID` env > the machine config file — never
from `vault.json` in the vault being checked. If it came from the vault
itself, a repointed or freshly cloned vault would bring its own "correct"
answer along with it, and the check would prove nothing. `vault.json` says
what the vault *claims* to be; the machine config says what this machine
*expects*; the guard's job is only to confirm the two agree. An adopter
wiring this up must set `SBW_EXPECTED_VAULT_ID` (or pass `--expect-id`)
independently of anything in the vault directory itself — if neither
resolves, the guard fails closed rather than silently skipping the check.

This is why there is no layer system. The thing that needed isolating was the
vault, and a per-commit identity check does that directly.

## `make doctor`

Machine/vault health — not content, that's [`make audit`](AUDIT.md), and not
code, that's `make check`. Read-only, and none of it overlapping:

```bash
make doctor                                     # resolved vault, same as the script
VAULT="$HOME/vaults/second-brain" make doctor   # or: ./scripts/doctor.sh --vault ...
```

With nothing passed, every vault-taking `make` target resolves through
`scripts/lib/resolve-vault.sh` — the same environment > config file > default
chain the scripts themselves use, so `make doctor` and `./scripts/doctor.sh`
can't name different vaults. Write `$HOME`, never `~`, when you do pass a path
on the command line: make performs no tilde expansion, and neither does zsh in
a variable argument, so `VAULT=~/vaults/...` stats nothing.

- **Commit-guard hook** — this vault's `pre-commit` hook is installed and is
  ours: the local backstop above.
- **Skill parity across `SKILLS_DIRS`** — a skill installed into one
  configured skills directory but missing from another is invisible from
  whichever agent reads the second one. See the reference's
  [Skills](REFERENCE.md#skills) section.
- **Skill-roster parity** — the third-party skills a `skills.json` declares,
  against what is actually on this machine, in three directions: a source that
  was never fetched, a source whose checkout sits at a **different sha** than the
  manifest pins, and a link that no source declares any more (a skill dropped
  from an `allow` list, whose link survives until a sync prunes it). The middle
  one is the reason this check exists: a wrong-sha skill works perfectly, so two
  machines can be running different versions of the same adopted skill with
  nothing anywhere reporting it. Skipped entirely when no manifest is configured
  — the check reads a declared roster, so with none declared there is nothing to
  compare and it must not manufacture a finding. See the reference's
  [Bringing your own skills](REFERENCE.md#bringing-your-own-skills) section.
- **Vendored submodule drift** — `vendor/obsidian-skills` checked out at a
  commit other than the one this engine checkout's tag actually pins, the
  state a bare `git checkout <tag>` leaves behind. See the reference's
  [Rollback](REFERENCE.md#rollback) section.
- **The repo registry, both directions** — the registry is compared against a
  scan of this machine for repos carrying rendered output, because the registry
  alone only knows what a render told it. Registered repos that are gone or no
  longer rendered are named and never pruned (a repo on an unmounted volume is
  not a deleted repo); repos that are rendered but *not* registered are named
  with the command that registers each. Every report states the scan's scope —
  `roots=… depth=…`, on clean runs too — because a scan cannot claim
  completeness, and *undetermined* now means only that no configured root could
  be read. See the reference's [repo registry](REFERENCE.md#the-repo-registry)
  section.

`-h` prints this same list from the script itself, so it can't drift out of
step with what's actually checked.

### Exit codes

| Code | Meaning |
|------|---------|
| 0 | everything checked out |
| 1 | warnings only — setup is unfinished, but nothing is misconfigured |
| 2 | at least one error — something is configured wrong, and finishing setup won't fix it |

Warnings stay non-zero deliberately. Every check here exists to surface a
state nothing else surfaces — a stale submodule still renders fine, a skill
missing from one skills directory is invisible from the other agent — so a
scheduled run that exited 0 on those findings would be decorative. What made
this confusing mid-setup wasn't the exit code but one message and one
severity covering two different problems.

Those are now told apart, along with two more states, because the fix for
each is in a different place:

| State | Severity | Because |
|-------|----------|---------|
| path doesn't exist | error (2) | the configuration points nowhere; the message names the knob that produced the path — the `--vault` flag, the `SBW_VAULT` environment variable, the config file, or the built-in default |
| exists, not a git repo | warning (1) | setup is unfinished — `init-vault.sh --adopt` finishes it |
| git repo, no `vault.json` | warning (1) | nothing identifies it as a vault, so the identity check has nothing to compare against |
| git repo with `vault.json` | — | the hook checks below apply |

`guard-vault-commit.sh` classifies a path the same way, through the shared
`scripts/lib/vault-state.sh`, so the guard and the checkup never describe one
broken path two different ways. The Python auditors (`check-lineage.py`,
`check-followups.py`, `build-vault-index.py`) use the Python mirror of it for
the same reason.
