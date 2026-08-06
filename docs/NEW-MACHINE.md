# Setting up a new machine

Two paths. Pick one deliberately — they differ in what arrives with you.

- **[Fresh start](#fresh-start)** — the engine, none of someone else's
  conventions. This is what an adopter does, and what a work machine should do
  when its stack differs from your personal one.
- **[Carry your rules](#carry-your-rules)** — a second machine for the same
  person and the same stack.

Everything below assumes macOS or Linux. Windows is not supported: the scripts
target bash and the skills directories are POSIX paths.

---

## Prerequisites

- `git`, `python3`, `bash` (the system bash 3.2 on macOS is fine)
- The agent(s) you use: Cursor, Claude Code, or both
- Obsidian 1.12+ if you want the vault's Bases views (optional)
- `shellcheck` — required by `make lint`, which fails without it. `make check`
  uses it when present and prints a visible skip line when it isn't, so a
  machine without it still runs everything else. `make test` needs nothing
  beyond the three above.

---

## Fresh start

### 1. Clone the engine

```bash
git clone "git@github.com:dimeloper/second-brain-workflow.git" ~/second-brain-workflow
cd ~/second-brain-workflow
latest=$(git tag --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
echo "latest = $latest"                       # empty means no release yet
[ -z "$latest" ] || git checkout "$latest"    # omit these three lines to track main
git submodule update --init --recursive
```

That pins the newest tagged release — the stable option. See the README's
[Versioning](../README.md#versioning) section for the bump policy and how to
roll back to an older one.

No SSH key set up yet (or a work machine you don't want to add one to)?
Clone over HTTPS instead — read-only, no auth needed for a public repo:

```bash
git clone "https://github.com/dimeloper/second-brain-workflow.git" ~/second-brain-workflow
cd ~/second-brain-workflow
latest=$(git tag --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
echo "latest = $latest"                       # empty means no release yet
[ -z "$latest" ] || git checkout "$latest"    # omit these three lines to track main
git submodule update --init --recursive
```

If you are cloning someone else's engine onto a work machine, use a **read-only
deploy key**. That makes it mechanically impossible to push work-derived
conventions back to a personal repo — a stronger guarantee than remembering not
to.

### 2. Point at your rules

The engine ships with `rules/` empty — it works with zero rules, rendering
nothing and saying so. `AGENTS.md` is optional too: without it, rules still
render and the run warns that `AGENTS.md` and `CLAUDE.md` were skipped. An
empty start is a valid state, not a broken one.

Two ways to add your own conventions:

- **Separate repo (recommended if the engine itself is public and your
  conventions aren't):**
  ```bash
  git clone "git@github.com:YOUR_ACCOUNT/YOUR_RULES_REPO.git" ~/dev-conventions
  ```
  Then point the engine at it — see step 5. `AGENTS.md` lives at that repo's
  root, `rules/*.md` in its `rules/` subdirectory.
- **Self-contained (simplest, fine when the whole checkout is already
  private):** write `rules/*.md` directly here, and
  `cp AGENTS.md.example AGENTS.md` then edit it. No configuration needed —
  this is the engine-relative default.

### 3. Install the skills

```bash
./scripts/sync-skills.sh
```

Installs into every directory in `SKILLS_DIRS` — by default both
`~/.cursor/skills` and `~/.claude/skills`. It never overwrites a real directory
or a symlink owned by another tool; it reports those and exits non-zero.

### 4. Create a vault

```bash
./scripts/init-vault.sh --path ~/vaults/VAULT_NAME --id VAULT_ID \
  --remote "git@github.com:YOUR_ACCOUNT/VAULT_REPO.git"
```

`--id` is what the guard checks *against* on every commit — see step 5 for
telling this machine what to expect — so make it meaningful (`personal`,
`work`). The remote is recorded but **not** pushed to — create the repo
yourself, private, first.

Add `--identity-email you@work.example.com` on a machine where commits must be
authored as a particular address. It records that in `vault.json`, and the
guard then refuses a commit authored as anything else. This is a *different*
axis from `--id`: that one checks which vault is being written to, this one
checks who the commit claims to be from. Getting the first right does not imply
the second — a commit can pass every destination check, push with the right
credentials, and still carry a personal address into an employer's history.
`init-vault.sh` prints the address commits here would actually be authored as,
whether or not you pin one, so a wrong one is visible before the first commit
rather than after the push.

This also installs `guard-vault-commit.sh` as the vault's `pre-commit` hook,
so a hand-run `git commit` here is guarded even with no agent involved —
`--no-hook` opts out. `make doctor VAULT=$HOME/vaults/VAULT_NAME` reports a
vault whose hook is missing or isn't ours — spell it `$HOME`, not `~`, because
zsh does not expand a tilde in a `make` variable argument (bash does, which is
why this one silently works for some people and not others).

The vault starts with no domain practice notes. It does get four cross-cutting
notes describing how the vault itself operates, because `update-second-brain`
reads them at runtime.

When no config file exists yet, this also writes one with `SBW_VAULT` and
`SBW_EXPECTED_VAULT_ID` and prints it. Those two must agree with `--id`, and
here is the one moment both are known, so they can't be made to disagree by
hand. An existing config file is never touched — you get told which line to
add. `--no-config` skips it.

### Give the machine the right git identity

The real fix is not `git config user.email` per repo, which has to be
remembered for every vault and every clone. Key it on the path instead, in
`~/.gitconfig`:

```
[includeIf "gitdir:~/vaults/work-brain/"]
    path = ~/.gitconfig-work
```

with `~/.gitconfig-work` holding:

```
[user]
    email = you@work.example.com
    name = Your Name
```

**The trailing slash on `gitdir:` is required** — without it the condition
matches nothing, silently, and you are back to whatever the global identity
was. Verify with `git -C ~/vaults/work-brain var GIT_AUTHOR_IDENT`, which
resolves the same chain a commit would rather than just reading one config
file, or with `make doctor`, which reports a resolved identity that disagrees
with what `vault.json` declares.

### 5. Configure this machine

Step 4 already wrote `SBW_VAULT` and `SBW_EXPECTED_VAULT_ID` if you had no
config file. Write it in full when you need the other keys, or when a config
already existed and was therefore left alone. Substitute `VAULT_NAME` and
`VAULT_ID`, then paste the whole block — no editor needed, and nothing here
depends on `$EDITOR` being set:

```bash
config="${XDG_CONFIG_HOME:-$HOME/.config}/second-brain-workflow/config"
mkdir -p "$(dirname "$config")"
cat > "$config" <<'EOF'
# Comments must be on their own line — a trailing `# ...` becomes part of the
# value. Write ~/... not $HOME/..., since this file gets no shell expansion.
SBW_VAULT=~/vaults/VAULT_NAME
# or cursor,agents — or all three
RENDER_TARGETS=claude-code,agents
# narrow it if only one agent is installed
SKILLS_DIRS=~/.claude/skills
# only if rules live in a separate repo
SBW_RULES_DIR=~/dev-conventions/rules
# must match --id from step 4
SBW_EXPECTED_VAULT_ID=VAULT_ID
EOF
cat "$config"      # confirm what actually landed
```

See `config.example` for every key. Precedence is CLI flag > environment > this
file > defaults. Two format rules that bite if broken: the file is parsed, not
sourced, so **only a leading `~` is expanded** (`$HOME/...` stays literal), and
**a comment must start its own line** — `SBW_EXPECTED_VAULT_ID=work  # ...`
sets the id to `work  # ...`, and the guard then rejects every commit for an
id mismatch it can't explain.

`SBW_EXPECTED_VAULT_ID` is what makes the commit guard non-circular: it's read
from *this machine's* config, never from the vault's own `vault.json` — so a
repointed or freshly cloned vault can't bring its own "correct" answer along
with it. Without it (and without `--expect-id`), the guard now fails closed
rather than silently skipping the check.

### 6. Prove it works here

```bash
make test               # the toolchain itself, against fixtures — needs no extra tools
make check              # the above plus shellcheck, if it is installed
make verify-claude      # if you use Claude Code — costs two model calls
```

`make test` is the one to reach for first: it touches no real vault, no real
repo and no skills directory, and needs nothing beyond `git`, `python3` and
`bash`. `make check` adds shellcheck and a rule-scoping check, and prints
`shellcheck: skipped` rather than failing if shellcheck isn't installed.

`make verify-claude` renders into a throwaway repo and checks that a scoped
rule loads on a matching file and not otherwise. Skip it only if you have no
rules yet — it needs at least one glob-scoped rule to test.

For Cursor, see the canary method in the README. There is no automated
equivalent.

### 7. Onboard one repo, then work

```bash
./scripts/render.py /path/to/a/repo
```

Or say **onboard repo** to an agent. Then work normally, and say **update second
brain** at the end of a session. Your first practices come from what you
actually did — do not scaffold them.

### What rendering actually produces

`rules/frontend-angular.md` — a `paths:` list plus a body:

```markdown
---
paths:
  - "**/*.component.ts"
  - "**/*.directive.ts"
description: Angular component and reactivity conventions
---

- Use `OnPush` change detection on every component.
- Prefer signals over `BehaviorSubject` for local component state.
```

turns into `.cursor/rules/frontend-angular.mdc`:

```markdown
---
description: Angular component and reactivity conventions
globs: "**/*.component.ts, **/*.directive.ts"
alwaysApply: false
---

<!-- generated by second-brain-workflow@ea38f4b (v0.1.0) from rules/frontend-angular.md -->

- Use `OnPush` change detection on every component.
- Prefer signals over `BehaviorSubject` for local component state.
```

and `.claude/rules/frontend-angular.md` — near-identical to the source, since
that's Claude Code's native shape:

```markdown
---
paths:
  - "**/*.component.ts"
  - "**/*.directive.ts"
description: Angular component and reactivity conventions
---

<!-- generated by second-brain-workflow@ea38f4b (v0.1.0) from rules/frontend-angular.md -->

- Use `OnPush` change detection on every component.
- Prefer signals over `BehaviorSubject` for local component state.
```

Both carry a provenance comment naming the exact commit and engine version
the content came from — edit `rules/frontend-angular.md` and re-render,
never a generated file. See the README's [One rule set, every
agent](../README.md#one-rule-set-every-agent) section for why Claude Code's
shape is canonical and Cursor's `globs` is derived, plus the full targets
table and CI/verification commands.

### 8. Set up CI (optional, per vault)

Two independent templates, both copied into `.github/workflows/` **in the
vault repo**, not here — this engine checkout has no vault, so its own CI can
never run either:

- `docs/vault-ci/audit.yml` — `make audit` (lineage + rule budget) is easy to
  forget once it's not part of any workflow you already run.
- `docs/vault-ci/guard.yml` — the CI backstop from
  ["Keeping two machines apart"](#keeping-two-machines-apart) below; the only
  tier that still catches a `--no-verify` bypass.

See `docs/vault-ci/README.md` for the rules-directory setup (not optional;
both scripts hard-require one) and what does or doesn't fail each run.

---

## Carry your rules

Same as above, but skip the "point at your rules" decision if you're using the
self-contained layout: your `rules/*.md` and `AGENTS.md` come with the clone.
If you keep rules in a separate repo, clone that too and set
`SBW_RULES_DIR` the same as on the first machine. Set
`RENDER_TARGETS` for whichever agents this machine runs, and give the vault a
different `--id` from the other machine's.

---

## Keeping two machines apart

Rules flow outward freely — applying your own conventions to an employer's code
is fine. The direction that must never happen is a practice learned on employer
work landing in a personal or public repo, and that is always a *vault write*.
So the vault is the boundary, enforced per commit by the same script, run
three ways, in increasing order of how hard they are to skip:

```bash
./scripts/guard-vault-commit.sh --expect-id VAULT_ID
```

It refuses a staged path outside the vault's allowed set, a `vault.json` id that
isn't the one expected, an `origin` that doesn't match `vault.json`, an
implausibly large diff, deletion of an `enforced` note, conflict markers, and
anything resembling a credential.

- **The fast path.** `update-second-brain` runs it before every commit it
  makes.
- **The local backstop.** Step 4 installs it as this vault's `pre-commit`
  hook by default, so a hand-run `git commit` here — no skill, no agent — is
  guarded too. `make doctor` reports a vault whose hook is missing or isn't
  ours.
- **The one that can't be skipped.** `git commit --no-verify` skips the
  pre-commit hook, and there's no way to stop that locally. Copy
  `docs/vault-ci/guard.yml` into `.github/workflows/guard.yml` **in the vault
  repo** (same place as step 8's `audit.yml`) so a bypassed commit is still
  caught on push. This is containment, not prevention — CI catches it *after*
  the push. See `docs/vault-ci/README.md` for setup and that caveat in full.

**Never on a work machine:** clone the personal vault, configure personal
remotes, or copy notes across.

---

## Deliberate omissions

- No layer system. One engine, one rule set, one vault per machine.
  `SBW_RULES_DIR` relocates *where* that one rule set lives — a
  separate repo instead of a subdirectory — it does not let two rule sets
  merge on the same machine. If you need that, that is the point at which to
  build layers — not before.
- No automatic push. Every remote is created by you.
- No Windows support.
- No telemetry, and nothing reads across vaults.
