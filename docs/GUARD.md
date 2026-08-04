# The vault commit guard

Full mechanics for [the README's "A vault per machine"](../README.md#a-vault-per-machine)
model: creating a vault, what the commit guard blocks, the three ways it's
enforced, the trust model behind it, and what `make doctor` checks. Read the
README first for why any of this exists — this is the reference material,
not the pitch.

## Creating a vault

One vault per machine, each with its own `vault.json` (`id`, `remote`):

```bash
./scripts/init-vault.sh --path ~/vaults/work-brain --id work \
  --remote git@github.com:<account>/work-brain.git
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
recorded in `vault.json`, an implausibly large diff, deletion of an `enforced`
note, conflict markers, and anything that looks like a credential.

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
code, that's `make check`. Three checks, read-only, none overlapping:

```bash
VAULT=~/vaults/second-brain make doctor   # or: ./scripts/doctor.sh --vault ...
```

- **Commit-guard hook** — this vault's `pre-commit` hook is installed and is
  ours: the local backstop above.
- **Skill parity across `SKILLS_DIRS`** — a skill installed into one
  configured skills directory but missing from another is invisible from
  whichever agent reads the second one. See the README's
  [Skills](../README.md#skills) section.
- **Vendored submodule drift** — `vendor/obsidian-skills` checked out at a
  commit other than the one this engine checkout's tag actually pins, the
  state a bare `git checkout <tag>` leaves behind. See the README's
  [Rollback](../README.md#versioning) section.

Exits non-zero if anything is worth a look; `-h` prints this same list from
the script itself, so it can't drift out of step with what's actually
checked.
