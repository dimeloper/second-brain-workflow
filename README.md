# second-brain-workflow

**Your agent forgets everything at session end. This remembers only the parts
that turned out to be true.**

Everyone now has a `CLAUDE.md` or an `AGENTS.md`. Nobody has a lifecycle. Every
convention in a rules file was written once, at equal weight, and never
re-examined — so the file grows, gets skimmed, then ignored. This engine gives a
convention a maturity gradient instead: it starts as an `idea`, becomes
`trialing`, and only reaches `enforced` once you have actually re-applied it in
a few repos. Then you distill it into one short rule, and one source renders to
Cursor, Claude Code, and `AGENTS.md`.

**Two load-bearing choices, before you read further.** It assumes git plus a
markdown vault. And **the promotion gate is manual by design** — nothing
promotes a note on your behalf, because a counter that promoted itself would
measure writing, not re-application. Both are decisions, not missing features.
If you wanted automation, this is the wrong tool and nothing further down
changes that.

![Knowledge graph showing practice notes growing sparse-to-dense across three phases — Session 1, a few sessions later, and months in — as they mature from idea to trialing to enforced, Obsidian graph-view style.](docs/impact.svg)

*Illustrative, not the actual interface. The agent never browses a graph — it
reads the generated `practices/INDEX.md`, one row per note. Graph-view browsing
like this is for you, in Obsidian, over the same vault.*

## Who this is for

A developer who uses an agent daily, works across more than one repo, and has
already written a big rules file and watched it stop mattering. That last clause
is the qualifier. Someone who has not hit that wall will not feel the problem,
and the setup cost will read as unjustified — because for them it is.

This repo is the generic **engine** that runs the loop: the agent skills, rule
rendering, and vault tooling, versioned here rather than trapped in an editor's
account sync. It ships with none of your own content — `rules/` is empty and no
vault is bundled. Your conventions and your vault live in your own repo(s),
private if you like, that this engine points at.

## What you get, and when

The value is deferred, and pretending otherwise loses people at week one. Here
is the honest schedule:

| When | What you get |
|------|--------------|
| **Session 1** | Say **update second brain**. The session lands as a daily note, plus two or three proposed practice notes drawn from work you already did. Costs one sentence. |
| **Next morning** | Say **check my tasks**. The follow-ups from that session, this repo's first. The cheapest concrete win, and the one to try before believing anything about maturity gradients. |
| **Week 2** | `obsidian-knowledge-base` starts finding notes that apply to the work at hand, so the agent stops re-deriving decisions you already made. |
| **Month 1** | A note reaches `enforced`. You distill it into one rule; `render.py` emits it for every agent you use, with drift-checking in CI. |
| **Month 3** | `make audit` tells you which rules are orphaned, which claims went stale, and which always-on rules are over budget. |

Row 2 is the demo. It is immediate and legible in a screenshot.

## Quickstart

An afternoon, and two placeholders to substitute — `VAULT_ID` and
`YOUR_ACCOUNT`. The rest is paste-and-run.

`make init` explains what the engine does, prints every configuration key with
its current value and where that value came from, and shows the config it would
write — changing nothing until you add `YES=1`.

```bash
git clone --recurse-submodules "https://github.com/dimeloper/second-brain-workflow.git"
cd second-brain-workflow
latest=$(git tag --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
echo "latest = $latest"                       # empty means no release yet
[ -z "$latest" ] || git checkout "$latest"    # omit these three lines to track main
git submodule update --init --recursive       # a tag checkout does not move the pin

make init                                     # read this; it writes nothing
```

**Pin the release; don't track `main`.** The vault CI templates pin
`ENGINE_REF` to a tag, and `make upgrade` warns about a vault workflow that
pins nothing on the grounds that its checks then run against whatever `main`
is. An unpinned local checkout is the same hazard from the other side: the
pre-commit hook and the CI backstop stop enforcing the same code, and CI exists
precisely to catch what `--no-verify` skips. The `git submodule update` line is
not optional either — a tag checkout after `--recurse-submodules` leaves
`vendor/obsidian-skills` at whatever `main` pinned.

**The vault comes before the config**, because `init-vault.sh` writes the vault
path and its id *together*, and that pairing is what stops them disagreeing.

```bash
vault_id=VAULT_ID                             # personal | work | …
vault_path=~/vaults/${vault_id}-brain         # derived, so the two can't disagree
```

Then **one** of the next two, depending on whether the vault exists yet:

```bash
# A. A new vault. Create the repo yourself first, private, and empty.
./scripts/init-vault.sh --path "$vault_path" --id "$vault_id" \
  --remote "git@github.com:YOUR_ACCOUNT/${vault_id}-brain.git"
```

```bash
# B. A vault that already exists on a remote — a second machine, or a rebuild.
git clone "git@github.com:YOUR_ACCOUNT/${vault_id}-brain.git" "$vault_path"
./scripts/init-vault.sh --path "$vault_path" --id "$vault_id" --adopt
```

Then finish the machine:

```bash
./scripts/sync-skills.sh
make init YES=1 VAULT_ID="$vault_id"          # appends what is missing, runs doctor
```

Getting that branch wrong is the one mistake worth naming here: running **A**
against a vault that already exists on a remote creates a *second* vault
claiming the first one's remote, which is how one vault's notes get pushed over
another's. `init-vault.sh` refuses that outright, and refuses an unedited
`VAULT_ID`, rather than leaving either to be noticed later.

Two vaults means two runs of this, one per machine role — `personal` on a
personal machine, `work` on a work one.

[docs/NEW-MACHINE.md](docs/NEW-MACHINE.md) is the long way: every step with a
**Check.** after it, pinning to a release instead of tracking `main`, pointing
at a separate private rules repo, giving the machine the right git identity, and
a troubleshooting table built from real first-setup failures. Every refusal this
tooling can produce is explained there.

## Your first session

The first useful moment is the end of the *next* session, not the end of setup.
Work normally, then say:

> **update second brain**

An agent skill mines what happened — a bug fixed, a design decision made, a
pattern that worked — into a daily note, and proposes practice notes for the
parts that look durable. You approve them; nothing is written otherwise. Then it
commits and pushes the vault.

The daily note it writes:

```markdown
# 2026-08-03

## Built
- Added a request timeout to the payments client

## Follow-ups
- [ ] Add a test that fails without the timeout, per PR feedback #repo/payments-service
- [x] Bumped the client's retry count to match #repo/payments-service

## Practices followed
- bound-every-outbound-call-with-a-timeout

## Drift / gaps
-

## Vault candidates
- Bounding outbound calls with a timeout, seen twice now
```

Next morning, in any repo:

> **check my tasks**

`check-follow-ups` reports the one open item above — under **this repo** when
run from `payments-service`, under **other repos** anywhere else, and never
hidden either way. It walks back to the last daily notes that actually exist
rather than a fixed number of calendar days, so a weekend, a holiday or a
vacation gap does not swallow anything.

That is the whole loop. Say **onboard repo** in a project to wire rules into it,
and keep going. Practice notes accumulate from what you actually did — do not
scaffold them.

## Why this doesn't rot

This is the part that matters at month six rather than week one. Each item below
is a short summary; [docs/REFERENCE.md](docs/REFERENCE.md) is the full mechanics.

- **The maturity gradient is earned, not counted.** A note starts at `idea` from
  one observation, reaches `trialing` only after deliberate re-application in a
  second unrelated repo, and `enforced` only after holding across three or more
  without contradiction — one rung per pass. Clearing a bar is necessary, not
  sufficient, and **you** do the promoting. See
  [the maturity gradient](docs/REFERENCE.md#the-maturity-gradient).
- **One rule set, every agent.** Write short imperative rules once
  (`rules/*.md`); `render.py` emits Cursor's `.mdc`, Claude Code's `CLAUDE.md`,
  and a portable `AGENTS.md` from the same source, each with a provenance header
  naming the source SHA, and `--check` fails CI on drift. See
  [One rule set, every agent](docs/REFERENCE.md#one-rule-set-every-agent).
- **The rule set has a budget.** `rule-budget.py` measures what an always-on
  rule set costs every session and reports when it is over — the mechanism that
  stops the rendered output becoming the same unread wall the vault exists to
  replace. See [Review loop](docs/REFERENCE.md#review-loop).
- **Lineage is recorded, and audited.** A rule's `source:` frontmatter names the
  practice note it came from. `make audit` reports orphaned rules, stale claims,
  thin evidence, and follow-ups still open past the window `check-follow-ups`
  covers — read-only, nothing blocking but an orphaned rule. See
  [docs/AUDIT.md](docs/AUDIT.md).
- **One vault per machine, isolated per commit.** Rules flow outward freely;
  a practice learned on employer work landing in a personal or public repo is a
  *vault write*, so every commit is checked against the machine's expected vault
  identity — read from this machine's config, never from the vault being
  checked. Enforced three ways, one of which survives `--no-verify`. See
  [docs/GUARD.md](docs/GUARD.md).
- **Rendering into a repo you do not own.** `--local` renders normally and adds
  exactly the files it wrote to that repo's `.git/info/exclude`, so the rules
  load in your sessions and the remote never sees them. It refuses if a path it
  would write is already tracked, rather than half-keeping the promise. See
  [Rendering into a repo you do not own](docs/REFERENCE.md#rendering-into-a-repo-you-do-not-own).
- **Bring your own skills.** The engine ships five of its own and no roster of
  other people's. Declare the ones you want in a `skills.json`, pinned by sha
  and allowlisted per source, so two machines reading the same manifest install
  the same thing. See
  [Bringing your own skills](docs/REFERENCE.md#bringing-your-own-skills).
- **Upgrades tell you what breaks first.** `make upgrade` previews by default,
  prints every `### Major` changelog section in range verbatim before proposing
  anything, then drift-checks every onboarded repo — from a registry *and* a
  scan, so a repo the registry never recorded is still checked. See
  [Versioning](docs/REFERENCE.md#versioning).
- **`make doctor` says what this machine cannot do.** Including whether it has
  any rules to render at all, and whether an empty rules directory is a decision
  or an unfinished setup. See [`make doctor`](docs/GUARD.md#make-doctor).

## Documentation

| Document | What is in it |
|----------|---------------|
| [docs/NEW-MACHINE.md](docs/NEW-MACHINE.md) | Setup, step by step, with a **Check.** after each; the git-identity setup; every refusal explained; troubleshooting from real failures |
| [docs/REFERENCE.md](docs/REFERENCE.md) | Rendering, skills and the manifest, the repo registry, the vault layout, versioning and upgrades |
| [docs/GUARD.md](docs/GUARD.md) | The commit guard's mechanics, its trust model, and what `make doctor` verifies |
| [docs/AUDIT.md](docs/AUDIT.md) | Each audit check, and the CI template that runs them weekly |
| [config.example](config.example) | Every configuration key |

## License

MIT — see [LICENSE](LICENSE).
