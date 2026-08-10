# second-brain-workflow

**Second brain workflow for developers.**

Turn your coding sessions into a growing, queryable knowledge base — instead
of insights evaporating at the end of a chat, or piling up in one rules file
no one re-reads.

![Knowledge graph showing practice notes growing sparse-to-dense across three phases — Session 1, a few sessions later, and months in — as they mature from idea to trialing to enforced, Obsidian graph-view style.](docs/impact.svg)

*Illustrative, not the actual interface. The agent never browses a graph —
it reads the generated `practices/INDEX.md`, one row per note. Graph-view
browsing like this is for you, in Obsidian, over the same vault.*

Say **"update second brain"** at the end of a session and an agent skill
mines what happened — a bug fixed, a design decision made, a pattern that
worked — into individual, versioned practice notes in an Obsidian vault.
Notes start as `idea`s and only mature to `enforced` once you've actually
re-applied them across a few repos, so the knowledge base tracks what's
proven, not just what was written once.

This repo is the generic **engine** that runs that loop: the agent skills,
rule rendering, and vault tooling, versioned here rather than trapped in an
editor's account sync. It ships with none of your own content — `rules/` is
empty and there's no vault bundled — your actual conventions and vault are
expected to live in your own repo(s), private if you like, that this engine
points at.

## What you get

- **Capture what you learn** — `update-second-brain` is the only write path
  for practice and daily-note content: captures a session into a daily note, proposes new practice
  notes, promotes existing ones by evidence, then commits and pushes. See
  [Cold path](#cold-path-obsidian-vault).
- **Apply what you already know** — `obsidian-knowledge-base` finds and
  scores notes against the work at hand, read-only, so the agent applies what
  you've already learned instead of re-deriving it every session.
- **Never lose a follow-up** — `check-follow-ups` scans recent daily notes'
  `Follow-ups` sections and reports what's still open, walking back to the
  last notes that actually exist rather than a fixed number of calendar days
  — so it survives a weekend, a holiday, or a vacation gap the same way. Items
  for the repo you're in come first; the rest are grouped below rather than
  filtered out, because a task with no repo to infer is usually the one that's
  been open longest. Anything still open *outside* that window is `make audit`'s
  job. See [Review loop](#review-loop).
- **One rule set, every agent** — write short imperative rules once
  (`rules/*.md`); `render.py` emits Cursor's `.mdc`, Claude Code's
  `CLAUDE.md`, and a portable `AGENTS.md` from the same source, with
  drift-checking for CI. See [One rule set, every agent](#one-rule-set-every-agent).
- **A vault per machine, safely isolated** — a per-commit guard blocks a
  practice learned on employer work from ever landing in a personal or
  public repo. See [A vault per machine](#a-vault-per-machine).

## Quickstart

```bash
git clone --recurse-submodules "https://github.com/dimeloper/second-brain-workflow.git"
cd second-brain-workflow
latest=$(git tag --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
echo "latest = $latest"                       # empty means no release yet
[ -z "$latest" ] || git checkout "$latest"    # omit these three lines to track main
git submodule update --init --recursive

# This machine's role. VAULT_ID is a placeholder, like YOUR_ACCOUNT below.
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

```bash
./scripts/sync-skills.sh
```

Substitute `VAULT_ID` and `YOUR_ACCOUNT`; the rest is paste-and-run. Getting
the branch wrong is not cosmetic: running **A** against a vault that already
exists on a remote creates a *second* vault claiming the first one's remote,
which is how one vault's notes get pushed over another's. `init-vault.sh`
refuses that outright, and refuses an unedited `VAULT_ID`, rather than leaving
either to be noticed later.

Two vaults, so two runs of this, one per machine role — `personal` on a
personal machine, `work` on a work one. Following it verbatim on the second
machine is the mistake it is built to survive: an unreplaced placeholder now
stops the run instead of quietly producing a vault whose id is wrong.

**`vault_id` must match this machine's `SBW_EXPECTED_VAULT_ID`.** Those two
disagreeing is the single most common way to end up with a setup that fails on
its first commit, so `init-vault.sh` writes both together when no config file
exists yet, and prints what it wrote:

```
Wrote /Users/you/.config/second-brain-workflow/config:
    # Written by init-vault.sh. See config.example for every key.
    SBW_VAULT=/Users/you/vaults/second-brain
    SBW_EXPECTED_VAULT_ID=personal
```

If a config file already exists it is never touched — you get told which line
to add instead. `--no-config` skips this entirely. See
[`config.example`](config.example) for every key and
[docs/NEW-MACHINE.md](docs/NEW-MACHINE.md) for writing it by hand.

See [Versioning](#versioning) for the bump policy and how to pin or roll back
to a specific tag instead of the newest. `--remote` is only recorded, not
pushed to — create that repo yourself, private, first.

Two checks run on it at creation. A `--remote` already recorded by the vault
this machine's config points at is **refused**, because two vaults sharing a
remote is how one vault's notes get pushed over another's; the check compares
host, owner and repo, so `.git` and `ssh`/`https` spellings of one repository
don't slip past as two. And an `--id` that doesn't appear in the repository's
name **warns** — usually the sign of a Quickstart followed verbatim, keeping
`vault_id=personal` next to a work remote.

Then just work. Say **"onboard repo"** in a project to wire up rules, and
**"update second brain"** at the end of a session to capture it. See
[docs/NEW-MACHINE.md](docs/NEW-MACHINE.md) for the full walkthrough,
including how to point at a separate private rules repo.

## Hot path

Short, imperative rules (`rules/*.md`) and a portable `AGENTS.md`. The agent
loads these on relevant turns.

By default the engine looks for both as a sibling of its own checkout
(`<engine>/rules`, `<engine>/AGENTS.md`) — fine for a self-contained clone with
its own conventions committed alongside the tooling. To keep rules in a
separate repo instead (the common case if you want the engine itself public
while your conventions stay private), point at it:

```bash
SBW_RULES_DIR=~/dev-conventions/rules ./scripts/render.py --explain
```

or set it once in `${XDG_CONFIG_HOME:-~/.config}/second-brain-workflow/config` (see
`config.example`). `AGENTS.md` is expected as `SBW_RULES_DIR`'s
sibling — i.e. the rules repo's root, not inside `rules/` itself. Precedence:
`--rules-dir` flag > `SBW_RULES_DIR` env > config file > the
engine-relative default.

This is about *where* rules live. For exactly how one rule file becomes
Cursor's, Claude Code's, and `AGENTS.md`'s native formats, see [One rule set,
every agent](#one-rule-set-every-agent).

## Cold path (Obsidian vault)

Long-form practice notes live in your vault (`practices/**`) — `~/vaults/second-brain`
by default, overridable via `SBW_VAULT`.

Agents start from the generated index `practices/INDEX.md` — one file listing
every note with its maturity, repo count, tags and a one-line rule — and open
individual notes only when a row looks relevant. Regenerate it with:

```bash
make vault-index          # or: ./scripts/build-vault-index.py [--vault PATH]
make vault-index-check    # fails if the index is stale
```

Three skills own the vault, and the read/write split is deliberate:

| Skill | Role |
|-------|------|
| `obsidian-knowledge-base` | **read only** — find applicable notes, score work against them |
| `update-second-brain` | **the only write path for content** — daily note, practice proposals, promotions, commit, push |
| `check-follow-ups` | **read only** — unchecked `## Follow-ups` items from recent daily notes, this repo's first |

Say **update second brain** at the end of a session to capture and publish it,
or **check my tasks** any morning to see what's still open. "Recent" is
deliberately narrow — a commitment that fell out of that window is
`make audit`'s job instead (via `check-followups.py`), part of the
[Review loop](#review-loop), not a skill.

### Worked example

A daily note (`2026-08-03.md`) and a practice note it might produce, in full:

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

````markdown
---
domain: backend
applies-to: ""
maturity: idea
last-reviewed: 2026-08-03
repos: ["payments-service"]
tags: [resilience, http]
---

# Bound every outbound call with a timeout

**Rule:** Every HTTP client call to another service gets an explicit timeout;
never rely on the library's default (often "none").

**Why:** An unbounded call turns one slow dependency into an outage for every
request stacked up behind it.

**Example:**

```python
requests.post(url, json=payload, timeout=5)
```

**Observed in:** `payments-service`, 2026-08-03 — added after a provider
outage held requests open for minutes.

## Related
- [[probe-health-with-a-route-that-does-no-work]]
````

`check-follow-ups` would report the one open item above — under **this repo**
when run from `payments-service`, under **other repos** anywhere else, and never
hidden either way. The `#repo/` tag is written by `update-second-brain`, which
knows the repo because it runs inside it; omit it for an item that belongs to no
repo (an email to send, a key to revoke in a console) rather than guessing.
`update-second-brain` is also what writes the practice note once a pattern like
this repeats.

### A vault per machine

One vault per machine, each with its own `vault.json` (`id`, `remote`):

```bash
./scripts/init-vault.sh --path ~/vaults/work-brain --id work \
  --remote "git@github.com:YOUR_ACCOUNT/work-brain.git"
```

This also installs `guard-vault-commit.sh` as the vault's `pre-commit` hook
(`--no-hook` opts out), so a hand-run `git commit` here is guarded even with
no agent involved.

**The vault is the isolation boundary, not the rule set.** Rules flow outward
freely: applying your own conventions to an employer's code is fine. The
direction that must never happen is a practice learned on employer work landing
in a personal or public repo — and that is a vault write. So every commit is
checked against the machine's expected vault identity:

```bash
./scripts/guard-vault-commit.sh --expect-id work
```

enforced three ways — a fast path built into `update-second-brain`, the
pre-commit hook above, and a CI backstop that's the only one of the three
that still catches `git commit --no-verify`. The expected id comes from the
machine's own config, never from the vault being checked, so a repointed or
freshly cloned vault can't vouch for itself. This is why there is no layer
system: the thing that needed isolating was the vault, and a per-commit
identity check does that directly, not a second rule tier. See
[docs/GUARD.md](docs/GUARD.md) for the full mechanics, the trust model
behind the identity check, and what `make doctor` verifies about a machine's
setup.

### Review loop

Practice notes are the source: when one reaches `maturity: enforced`, a human
distills it into a rule, and `source:` in the rule's frontmatter records the
lineage. `make audit` is the review side of that — orphaned rules, stale
claims, thin evidence, rule frontmatter that doesn't say what its author
thought, an over-budget always-on rule set, and a follow-up
commitment still open past the recent window `check-follow-ups` already
covers — all read-only, none blocking except an orphaned rule. See
[docs/AUDIT.md](docs/AUDIT.md) for what each check does and the CI template
that runs it weekly.

## Skills

Local skills live under `skills/` (categorized). Upstream skills are
vendored as a pinned submodule and installed by allowlist:

```bash
git submodule update --init
./scripts/sync-skills.sh         # or: make sync-skills
```

Already done by the Quickstart; re-run after a checkout that moves the
submodule's pin.

| Source | Contents |
|--------|----------|
| `skills/workflow/` | Onboard, vault read/write, follow-up review, per-project MCP |
| `vendor/obsidian-skills/` | [kepano/obsidian-skills](https://github.com/kepano/obsidian-skills) (MIT) — `obsidian-bases`, `obsidian-markdown` |

Skills published by a vendor are installed from that vendor, not copied here —
see `skills/README.md`.

**Manual step, per machine.** Railway's installer writes `use-railway` into
`~/.claude/skills/` only. To reach it from Cursor as well:

```bash
ln -s ~/.claude/skills/use-railway ~/.cursor/skills/use-railway
```

`sync-skills.sh` leaves that link alone — it points outside this repo, so it is
never repointed or pruned. Re-run the command after a fresh Railway install,
or run [`make doctor`](docs/GUARD.md#make-doctor), which detects exactly this — a skill
present in one configured skills directory but missing from another, ours or
not — and prints the exact `ln -s` to fix it. Detection only; it never links
anything itself.

Skills install into **every** directory in `SKILLS_DIRS`, defaulting to
`~/.cursor/skills` and `~/.claude/skills`, so Cursor and Claude Code resolve the
same skills from one source. A local skill shadows a vendored one of the same
name. The sync never overwrites a real directory or a symlink owned by another
tool — it reports the conflict and exits non-zero.

Adjust what gets installed:

```bash
SKILLS_DIRS=~/.claude/skills ./scripts/sync-skills.sh
VENDOR_SKILLS="obsidian-bases obsidian-markdown obsidian-cli" ./scripts/sync-skills.sh
```

### Bringing your own skills

The engine ships five skills of its own and tracks one pinned upstream set. It
does **not** ship a roster of other people's skills, for the same reason
[`rules/`](#the-rules-live-somewhere-else) ships empty: a curated selection of
someone else's craft skills is an opinion, and the engine's job is the mechanism.

Declare the ones you want in a `skills.json` next to your own `rules/`, and point
the machine config at it:

```
# ~/.config/second-brain-workflow/config
SBW_SKILLS_MANIFEST=~/dev-conventions/skills.json
```

```json
{
  "sources": [
    {
      "name": "motion",
      "repo": "https://github.com/someone/skills",
      "ref": "0dd13f5be1c4a2f7e9b8d6c5a4930817264f5abc",
      "allow": ["animate", "review-animations"]
    }
  ]
}
```

See [`skills.json.example`](skills.json.example) for every field. Then:

```bash
make fetch-skills          # preview; YES=1 clones each source at its pin
make sync-skills           # link the allowed skills in
make doctor                # reports unfetched, wrong-sha, or undeclared links
```

Three rules worth knowing before you write one:

- **`ref` is required, and should be a full sha.** An unpinned source means two
  machines reading the same manifest install different skills on different days,
  which is the whole failure the manifest exists to prevent. An abbreviated ref
  is accepted with a warning; the placeholder from the example is refused.
- **`allow` is required and per-source.** There is no "install everything" —
  every adopted skill is charged against the same session budget as your own.
- **Record the `license`.** Omitting it warns on every run. What you are allowed
  to do with someone else's content gets asked once at adoption and then never
  again, which is exactly the kind of question that wants a mechanical prompt —
  an unlicensed repo is all-rights-reserved by default. Free text, so "there
  isn't one" can be recorded as the finding it is.
- **A skill of yours wins.** A same-named local skill shadows the adopted one,
  and the sync says so rather than silently preferring one.

Sources are cloned into `vendor/external/`, which is **gitignored**. That is
deliberately not a submodule: a submodule records its pin in `.gitmodules`, and
this repo is public, so your roster would ship with the engine.

A skill that ships **its own installer** does not belong in a manifest — install
it the vendor's way and let it be a real directory. `sync-skills.sh` refuses to
touch one, which is what keeps `use-railway` working.

#### Which skills apply to a repo

```bash
make skills-for REPO=/path/to/repo
```

Two lists, both from your own `skills.json`:

```
Adopted and scoped to this repo: 5
  - animate  (matched App.tsx, app/(onboarding)/_layout.tsx, …)
  - app-store-screenshots  (matched app.json, eas.json)

Not adopted, worth considering here: 1
  - impeccable — design-heavy frontend wanting a visual-polish pass. Invasive:
    writes PRODUCT.md/DESIGN.md and registers an edit-time hook. Project scope only.
      install: npx impeccable install --scope=project
```

The second list is the point, and it is the one thing an agent host cannot do for
itself: it routes to the skills that are **installed** and can say nothing about
one that exists and is not. Add `applies_to` globs to a source to scope it, and a
top-level `candidates` array for skills you have deliberately *not* adopted —
`name`, `repo` and `when` required, `install`, `license` and `applies_to`
optional. Write
`when` about the **cost** as well as the benefit; the reason to read the list is
to decide.

A skill with no `applies_to` is reported as applying everywhere rather than as a
miss — it was never claimed to be repo-specific, so calling it irrelevant would
assert something nobody said.

A candidate carries an optional `status`: `suggested` (default), `adopted` or
`declined`. Only `suggested` gets pitched — the other two are decisions already
made, listed one line each under *Already decided, not pitched*. They stay in the
list rather than being deleted, because **the value of a rejected option is the
reason it was rejected**; delete the entry and the next session re-evaluates from
scratch and may reach a different answer for no new reason. `adopted` also covers
a skill installed the vendor's own way, which is genuinely adopted while
appearing in no source's `allow` list.

The `onboard-repo` skill runs this at step 2b and **reports without installing**:
adopting a skill is a standing choice about every future session, and several
write into the project.

### Which practices a repo has never had

```bash
make practices-for REPO=/path/to/repo
```

Only `enforced` notes become rules, and only rules reach a repo — so on a large
vault the notes at `idea` and `trialing` are invisible to a repo you just
onboarded. This reports them, filtered to the ones this repo is **not** already
in the `repos:` of, in two tiers:

- **Governs files here** — the note's own `applies-to` glob matches real files,
  named with the file that matched. These carry a **promotion delta**:
  `-> applying here clears ENFORCED`.
- **Same domain, judgement required** — matched on the repo's inferred stack
  alone. **No promotion claim**, because a guess that said "clears ENFORCED"
  would invite adding a `repos:` entry for a note that does not govern this repo.

The delta is the point: promotion runs on `length(repos)`, so one deliberate
application is often the single act that clears a rung — and knowing which note
is one repo short used to depend on remembering. The bars are read from the
vault's own `00-maps/promotion-candidates.md`; an unreadable one is a **hard
error**, never a default, because a report computed against a guessed bar names
specific notes as ready when they are not.

It **reports and never applies**, and neither does `onboard-repo`'s step 2c. The
vault's rule is that `trialing` is *earned by deliberate re-application, not just
counted*, so applying a dozen notes in one pass would manufacture exactly the
evidence the bar exists to measure. Apply one, then record it through
`update-second-brain`.

Cross-cutting notes without a matching glob are excluded and the count is
printed — they apply everywhere, so listing a hundred of them would bury the
repo-specific ones.

**Narrowing `SKILLS_DIRS` later does not uninstall anything.** The Quickstart
runs `sync-skills.sh` before a machine config exists, so the default applies and
both directories get the links; a config written afterwards naming only one
leaves the other install in place. `make doctor` reports links of ours found
outside `SKILLS_DIRS`, and `make uninstall` looks there too — marking them, so
what `YES=1` widens to reach is visible before it acts.

### Removing them again

```bash
make uninstall            # print what would go, change nothing
make uninstall YES=1      # actually remove
```

Previewing is the default and `--yes` is the only thing that acts, because the
alternative is symlink archaeology: `sync-skills.sh` installs by name into
directories that also hold other tools' installs, so "delete the ones that look
like ours" is a guess. Each link is instead resolved to an absolute path and
compared against this checkout — never matched on the text
`second-brain-workflow`, which a relative link like
`../../.agents/skills/find-skills` doesn't contain at all.

It also removes links left **dangling** by a deleted checkout, which is the one
state nothing else can clean up: the path they name is gone, so the only
evidence is a target that no longer resolves plus this engine's skills layout.
Run it from any checkout — it does not need to be the one the links point into.

Never touched: a real directory (a hand-maintained skill), a link resolving
anywhere outside this checkout (another tool's install, such as Railway's
`use-railway`), the skills directories themselves, and a broken link that isn't
ours. **It also does not remove your vault, your machine config, or the
rendered rules in repos you onboarded** — delete `.cursor/rules`,
`.claude/rules`, `AGENTS.md`, `CLAUDE.md` and `.sbw-version` per repo if you
want those gone. The [repo registry](#the-repo-registry) stays too, so a
reinstall still knows where this machine has rendered.

## Onboard a repo

Say **onboard repo**. The agent follows `onboard-repo`: syncs rules, adds a thin
project onboarding rule, points at vault practices, and wires project-scoped MCP.

Or manually:

```bash
./scripts/sync-rules.sh /path/to/target-repo
./scripts/sync-skills.sh   # once per machine, or after pulling skill changes
```

### The repo registry

A successful render appends the target's real path to
`${XDG_CONFIG_HOME:-~/.config}/second-brain-workflow/repos` — one absolute path
per line, deduped and sorted, blank lines and `#` comments ignored on read. It
is the only record of *where* this machine has rendered, and the reason
"re-render every onboarded repo" is a list rather than a guess: `render.py`
writes `.sbw-version` into the target and nothing on the machine, so before
this the only way to find onboarded repos was a directory glob — and a glob
that matches nothing is indistinguishable from a machine that has genuinely
onboarded nothing.

`--check` and `--dry-run` never write it, the same contract `.sbw-version` has.
A registry that can't be written (read-only home, unwritable config directory)
warns on stderr and the render still succeeds — rendering is the job — but it
does warn, because an unrecorded render is how the set becomes undetermined
later with nothing left to explain it.

### Both directions, from two sources

The registry alone cannot answer "which repos on this machine are onboarded" —
it holds what renders recorded, so one render on a machine with a dozen
pre-registry repos looks exactly like complete coverage. So
[`make doctor`](docs/GUARD.md#make-doctor) also **scans** for repos carrying
rendered output (a `.sbw-version`, or the provenance marker in `AGENTS.md` /
`CLAUDE.md` — the same rule every other registry check uses) and compares the
two sets:

- **Registered, but gone or no longer rendered** — named, never pruned. A repo
  on an unmounted volume is not a deleted repo.
- **Rendered, but not registered** — named, with `./scripts/render.py <repo>`
  to register it, or leave it if that repo is abandoned. Nothing adopts it for
  you.

A scan cannot claim completeness: a repo on another volume, or nested deeper
than the depth limit, is outside it. So **every report states its scope** —
`roots=… depth=…` — on clean runs too, and a root that could not be read is
named rather than dropped. Set `SBW_SCAN_ROOTS` (colon-separated, default
`$HOME`) and `SBW_SCAN_DEPTH` (default `5`) in the config file to widen it; see
`config.example`.

Finding nothing within a stated boundary is a result. **Undetermined** is now
only what it says: no configured root could be read, so there was no second
source to compare against at all. `make uninstall` leaves the registry file
alone.

## One rule set, every agent

`rules/*.md` (wherever `SBW_RULES_DIR` resolves to) is the canonical
source. `scripts/render.py` emits each agent's native format —
`sync-rules.sh` is a thin wrapper around it:

```yaml
---
paths:
  - "**/*.component.ts"
description: Angular component and reactivity conventions
---
```

| Target | Output | Always-on | Scoped |
|--------|--------|-----------|--------|
| `cursor` | `.cursor/rules/*.mdc` | `alwaysApply: true` | derived `globs` string |
| `claude-code` | `.claude/rules/*.md`, root `CLAUDE.md` | rule with no `paths` | `paths:` passed through |
| `agents` | `AGENTS.md` | whole file | — |

For a full worked example — one source file next to the exact `.mdc` and
`.claude/rules/*.md` it produces — see
[docs/NEW-MACHINE.md](docs/NEW-MACHINE.md#what-rendering-actually-produces).

The source format is Claude Code's native shape, so that emitter is a
near-identity and Cursor's comma-separated `globs` is the derived one. That
direction is deliberate: a comma-separated string cannot carry a brace group
like `{ts,tsx}`, so making it canonical would forbid braces everywhere instead
of only where they can't be represented.

A rule with `paths` is scoped; a rule without is always-on. There is no
`alwaysApply` field, so "scoped *and* always-on" is unrepresentable rather than
something a check has to catch.

Claude Code reads `CLAUDE.md`, not `AGENTS.md`, so the generated `CLAUDE.md`
imports `@AGENTS.md` rather than forking it.

```bash
./scripts/render.py /path/to/repo                      # all configured targets
./scripts/render.py /path/to/repo --targets cursor     # one target
./scripts/render.py /path/to/repo --check              # exit 1 on drift; for CI
./scripts/render.py --explain                          # resolution per target
```

`RENDER_TARGETS` sets the default per machine. Every output is a real file with
a provenance header naming the source SHA (the rules repo's own commit when it
differs from the engine's) and source path. Never edit a rendered file in the
target — edit it at its source and re-render. Files without the header are
treated as hand-written and are never overwritten or pruned; each target prunes
only its own outputs.

Rendering rejects globs that would silently match nothing. An unbalanced `[`
is always an error. A brace group containing a comma is an error only when
`cursor` is a target, since Cursor's single `globs` string cannot carry it —
Claude Code expands braces natively, so `--targets claude-code` accepts them.

### Confirming a rule actually loads

The checks above prove the *files* are right, not that an agent read them.

**Claude Code — automated:**

```bash
make verify-claude
```

Renders into a throwaway repo and runs two headless sessions with an
`InstructionsLoaded` hook attached: reading a file that matches a rule's globs
must load the rule, and reading one that matches nothing must not. The second
case is the one that matters — without it, "the rule loaded" is equally
consistent with every rule always loading, which would make scoping decorative.
Verified 2026-08-02 on macOS against Claude Code 2.1.220:

```
    session_start    CLAUDE.md
    include          AGENTS.md          <- the @AGENTS.md import resolves
    path_glob_match  frontend-angular.md
```

and, for a non-matching file, the first two only. Run it on any new machine
before trusting the toolchain there.

**Cursor — manual.** Cursor has no headless agent and its logs record nothing
about rule attachment, so this one needs eyes. Do not test it by asking the
agent about project conventions: it will read `.cursor/rules/` as ordinary files
and answer convincingly whether or not the glob matched. That produces a false
pass.

Use a canary the model cannot know and has no reason to look up. Append to one
scoped rule in a throwaway repo:

```
- The project codeword is QUOKKA-4417. If asked for the project codeword, reply
  with exactly that.
```

Then in two fresh chats ask `What is the project codeword?` — once with a
matching file as the active tab, once with a non-matching one. Answering
instantly means the rule was in context; searching the repo first means it was
not.

Verified 2026-08-02 on Cursor 3.14.7: known immediately on `*.component.ts`, and
on a `.txt` file the agent had to grep for it. Scoping confirmed on both agents.

## Versioning

`VERSION` at the repo root — [releases](https://github.com/dimeloper/second-brain-workflow/releases)
are tagged `v<VERSION>`. Bump policy:

- **Patch** — docs, wording, anything that doesn't change behavior.
- **Minor** — a new rule field, a new emitter, or new-but-additive behavior;
  existing rules and already-onboarded repos keep working unchanged.
- **Major** — anything that requires action in an already-onboarded repo to
  keep working (a changed rendered format, a removed field, a renamed
  config key).

**Cutting a release:** move [`CHANGELOG.md`](CHANGELOG.md)'s `[Unreleased]`
entries under a new `## [X.Y.Z] - YYYY-MM-DD` heading (add the two
comparison links at the file's bottom), bump `VERSION` to match, bump
`ENGINE_REF` in **both** `docs/vault-ci/*.yml` templates to the new tag, tag
`v<VERSION>`, and point the GitHub Release's notes at that changelog section
rather than writing them by hand — one place to describe what changed, not
two that can say different things. A **Major** entry in the changelog always
names the specific action required, since that's the part a commit log
can't supply on its own. `tests/test-release-consistency.sh` enforces the
`VERSION`/changelog/`ENGINE_REF` half of that list, because a template pinned
several releases back gives an adopter a workflow that quietly runs fewer
checks than they think.

Every rendered file's provenance comment names both the commit and the
engine version it came from, and a plain `.sbw-version` file is written at
the target repo's root alongside the rendered output — nothing else in the
target carried this before, so this is the one new file `render.py` writes
outside `.cursor/rules`, `.claude/rules`, `AGENTS.md` and `CLAUDE.md`. Like
any other rendered file, `--check` reports a stale `.sbw-version` as drift —
visible as "this repo hasn't re-rendered since the engine moved on." Unlike
every other rendered file, it can't carry the usual provenance comment (it's
a bare version string, not markdown), so it's the one file `render.py`
always overwrites rather than checking for a hand-written override — don't
hand-edit it.

See [Quickstart](#quickstart) for cloning at the newest release; drop the
`git checkout` line there to track `main` instead.

### Upgrading a set-up machine

```bash
make upgrade              # preview: print what would happen, change nothing
make upgrade YES=1        # switch the checkout, then report
```

Preview is the default and `YES=1` is the only thing that acts, the same
convention as [`make uninstall`](#removing-them-again). It prints
`current → target`, then **every `### Major` section from `CHANGELOG.md` in that
range, verbatim, before proposing anything** — that step is the skippable one
and the only one carrying required action, which is why it comes first and why
it is read from the target ref's own changelog rather than the working tree's.
Then, in order: refuse if the checkout is dirty or holds local commits the
target doesn't contain, switch the checkout, update the submodule, re-link
skills, run [`doctor`](docs/GUARD.md#make-doctor) inline, run `render.py
--check` across every onboarded repo — from the registry *and* the scan, so a
repo the registry does not name is still checked — reporting drift per repo with
the exact command that fixes each, and report a vault CI `ENGINE_REF` left
behind the target.

Every one of those reports states the scan's scope, on clean runs too — see
[the repo registry](#the-repo-registry). In preview, drift is measured against
the checkout as it stands, so its counts are lower bounds and the summary line
says so: switching stamps a new
version into every rendered file and into `.sbw-version`, so expect every
registered repo to need re-rendering afterwards. A preview targeting the
version already checked out has nothing pending, and says it plainly.

It never renders, commits, pushes, or writes to a vault. `--check` reports and
you decide; a stale `ENGINE_REF` is named, not edited.

`make upgrade REF=v0.9.0` targets a specific tag instead of the newest, and
`NO_FETCH=1` skips contacting the remote. Exit codes: `0` nothing to act on,
`1` findings, `2` refused (or `doctor` found a misconfiguration), `3` **the
onboarded repo set is undetermined** — meaning no scan root could be read, so
there was no second source to compare the registry against and the question
"which repos need re-rendering" has no answer. The run says so and fails rather
than printing a zero that reads as success. An empty registry is *not* that
state: the scan answers it, and a repo it finds is drift-checked and labelled
as unregistered, with one command that re-renders and registers it.

**Rollback:** in the engine checkout,

```bash
version=v0.2.0                            # the release to roll back to
git checkout "$version"
git submodule update --init --recursive   # vendor/obsidian-skills is pinned per-commit, not per-tag
./scripts/sync-skills.sh                  # installed skills are symlinks into that submodule
```

then re-render each onboarded repo (`./scripts/render.py <repo>`) — the
[repo registry](#the-repo-registry) is the list of which those are, and
`make upgrade REF=v0.2.0` runs this whole sequence (minus the render) with a
preview first. Checking
out a tag alone does not move `vendor/obsidian-skills` to the commit that tag
pinned — skipping the submodule step leaves vendored skills at whatever they
were before the rollback, which defeats the point of pinning. [`make
doctor`](docs/GUARD.md#make-doctor) reports a submodule left at the wrong commit, so a
switch-and-forget doesn't go unnoticed. Rules and vault content are untouched
by any of this — only the tooling that renders/audits/installs them moves.

## License

MIT — see [LICENSE](LICENSE).
