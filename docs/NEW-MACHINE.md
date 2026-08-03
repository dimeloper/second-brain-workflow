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
- `shellcheck` only if you plan to run `make lint`

---

## Fresh start

### 1. Clone the engine

```bash
git clone --recurse-submodules \
  git@github.com:dimeloper/second-brain-workflow.git ~/second-brain-workflow
cd ~/second-brain-workflow
```

No SSH key set up yet (or a work machine you don't want to add one to)?
Clone over HTTPS instead — read-only, no auth needed for a public repo:

```bash
git clone --recurse-submodules \
  https://github.com/dimeloper/second-brain-workflow.git ~/second-brain-workflow
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
  git clone git@github.com:<account>/<your-rules-repo>.git ~/dev-conventions
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
./scripts/init-vault.sh --path ~/vaults/<name> --id <id> \
  --remote git@github.com:<account>/<repo>.git
```

`--id` is checked on every commit by the guard, so make it meaningful
(`personal`, `work`). The remote is recorded but **not** pushed to — create the
repo yourself, private, first.

The vault starts with no domain practice notes. It does get four cross-cutting
notes describing how the vault itself operates, because `update-second-brain`
reads them at runtime.

### 5. Configure this machine

```bash
$EDITOR ${XDG_CONFIG_HOME:-~/.config}/second-brain-workflow/config
```

```
SBW_VAULT=~/vaults/<name>
RENDER_TARGETS=claude-code,agents     # or cursor,agents — or all three
SKILLS_DIRS=~/.claude/skills          # narrow it if only one agent is installed
SBW_RULES_DIR=~/dev-conventions/rules   # only if rules live in a separate repo
```

See `config.example` for every key. Precedence is CLI flag > environment > this
file > defaults.

### 6. Prove it works here

```bash
make verify-claude      # if you use Claude Code — costs two model calls
```

Renders into a throwaway repo and checks that a scoped rule loads on a matching
file and not otherwise. Skip it only if you have no rules yet — it needs at
least one glob-scoped rule to test.

For Cursor, see the canary method in the README. There is no automated
equivalent.

### 7. Onboard one repo, then work

```bash
./scripts/render.py /path/to/a/repo
```

Or say **onboard repo** to an agent. Then work normally, and say **update second
brain** at the end of a session. Your first practices come from what you
actually did — do not scaffold them.

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
So the vault is the boundary, enforced per commit:

```bash
./scripts/guard-vault-commit.sh --expect-id <id>
```

It refuses a staged path outside the vault's allowed set, a `vault.json` id that
isn't the one expected, an `origin` that doesn't match `vault.json`, an
implausibly large diff, deletion of an `enforced` note, conflict markers, and
anything resembling a credential. `update-second-brain` runs it before
committing.

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
