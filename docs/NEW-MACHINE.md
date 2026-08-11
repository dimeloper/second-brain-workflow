# Setting up a new machine

**Two questions before anything else.** Both change what you run, and getting
the second one wrong creates a duplicate vault rather than using the one you
have.

**1. Which rules arrive with you?** Pick deliberately.

- **[Fresh start](#fresh-start)** — the engine, none of someone else's
  conventions. This is what an adopter does, and what a work machine should do
  when its stack differs from your personal one.
- **[Carry your rules](#carry-your-rules)** — a second machine for the same
  person and the same stack.

**2. Does this vault already exist on a remote?**

- **No — it is the first machine for this vault.** `init-vault.sh` creates it,
  and you create the (private, empty) repo first.
- **Yes — a second machine, or a rebuild of one you had.** `git clone` it
  first, then `init-vault.sh --adopt` against the clone. This is the common
  case for a second machine, and it is the one that goes wrong quietly:
  creating instead of adopting gives you a second vault claiming the first
  one's remote, which is how one vault's notes get pushed over another's.
  `init-vault.sh` now refuses that outright — see
  [Adopting an existing vault](GUARD.md#adopting-an-existing-vault).

> **Get this one thing right.** The vault's `--id` and this machine's
> `SBW_EXPECTED_VAULT_ID` must be the same string. Those two disagreeing is the
> single most common way to end up with a setup that dies on its first commit,
> and the error you get names an id you never typed. `init-vault.sh` writes both
> together when no config file exists yet, so the usual way to break it is
> editing one of them afterwards.

Every step ends with a **Check** — the exact command, and the output to expect
from it. Run it before moving on; each one catches a distinct way the step
before it silently half-worked. If something looks wrong, see
[Troubleshooting](#troubleshooting) at the bottom, which is built from real
first-setup failures rather than imagined ones.

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
- **A git identity that suits this machine.** Not optional and easy to miss:
  commits into the vault are authored by whatever `user.email` resolves to, and
  on a fresh work machine that is usually still a personal address. See
  [Give the machine the right git identity](#give-the-machine-the-right-git-identity).
- **Credentials that can push to the vault remote.** On a managed machine where
  an EMU or SSO account can't easily take an SSH key, HTTPS plus a
  fine-grained personal access token is the realistic path. Nothing here
  pushes for you, so this only has to work by the time *you* push.

---

## The short way

```bash
git clone --recurse-submodules git@github.com:dimeloper/second-brain-workflow.git \
  ~/second-brain-workflow
cd ~/second-brain-workflow
latest=$(git tag --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1)
[ -z "$latest" ] || git checkout "$latest"    # omit these three lines to track main
git submodule update --init --recursive

make init
```

`make init` explains what this engine does, prints every configuration key with
its current value and where that value came from, reports what it found on this
machine, and shows the config it would write. It changes nothing until you add
`YES=1`, and it ends by running `doctor`.

It will not choose `SBW_EXPECTED_VAULT_ID` for you — that key is what makes the
commit guard's identity check non-circular, and a script that read it from the
vault's own `vault.json` would be answering the question the check exists to
ask. Pass it:

```bash
make init YES=1 VAULT_ID=personal
```

It also never overwrites a value already in your config; it appends only the
keys that are missing. Creating the vault itself is still step 4 below, and
`init` names the command when the vault is not there yet.

The rest of this document is the long way — every step spelled out, and the
reference for anything `init` reports that you want to understand or change.

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

**Check.**

```bash
echo "latest = $latest"
git submodule status
```

```
latest = v0.4.0
 a1dc48e68138490d522c04cbf5822214c6eb1202 vendor/obsidian-skills (heads/main)
```

An empty `latest` means no release tag resolved — the checkout was skipped and
you are on `main`, which is fine as long as you meant it. On the submodule line
the **leading character is the whole point**: a space means in sync, `-` means
never initialized (re-run the `git submodule update`), `+` means checked out at
a different commit than this tag pins. Vendored skills still link and render in
the `+` state, which is why nothing else notices it.

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

**Check.**

```bash
./scripts/render.py --explain
```

It prints where `rules/` and `AGENTS.md` resolved from and what each target
would emit. Nothing listed and no error means an empty rule set, which is a
valid starting state — not a failure to fix now.

### 3. Install the skills

```bash
./scripts/sync-skills.sh
```

Installs into every directory in `SKILLS_DIRS` — by default both
`~/.cursor/skills` and `~/.claude/skills`. It never overwrites a real directory
or a symlink owned by another tool; it reports those and exits non-zero.

To undo it — including starting this setup over — `make uninstall` previews and
`make uninstall YES=1` acts. It removes only links it can account for, handles
links left dangling by a checkout you already deleted, and leaves your vault,
your config file and any onboarded repo's rendered rules alone. See the
README's [Removing them again](../README.md#removing-them-again).

**Check.** The count on the last line per directory is the assertion — it should
be the number of skills you expect, in *every* configured directory:

```
/Users/you/.claude/skills
  check-follow-ups -> /Users/you/second-brain-workflow/skills/workflow/check-follow-ups
  ...
  obsidian-markdown -> /Users/you/second-brain-workflow/vendor/obsidian-skills/skills/obsidian-markdown
  7 skill(s)
```

One line per skill — the target shown is the link's real target, the same thing
`readlink` would print — then the count. Fewer than expected, or a `!!` line,
means a name collided with something already there and was left alone.

Seven is the count with no third-party roster declared. If your rules repo
carries a `skills.json`, do the next step first and re-run this one — the count
goes up by however many skills your `allow` lists name.

### 3b. Fetch your own skill roster (only if you have one)

Skip this entirely if you have no `skills.json`. Nothing later depends on it, and
the engine ships no roster of its own.

```bash
# in the machine config, alongside SBW_RULES_DIR
SBW_SKILLS_MANIFEST=~/dev-conventions/skills.json

make fetch-skills            # preview: what would be cloned, and at which sha
make fetch-skills YES=1      # clone each source into vendor/external/
./scripts/sync-skills.sh     # link the allowed skills in
```

This is the one step that reaches the network, which is why it is separate from
the sync. `vendor/external/` is gitignored, so nothing you fetch is ever
committed here.

**Check.** `make fetch-skills` a second time, and every source should already be
at its pin:

```
motion
  repo: https://github.com/someone/skills
  ref:  0dd13f5be1c4a2f7e9b8d6c5a4930817264f5abc
  already at 0dd13f5be1c4a2f7e9b8d6c5a4930817264f5abc

1 up to date, 0 to fetch.
```

`already at <sha>` on every source is the assertion. Anything else means the
checkout moved, and re-running with `YES=1` re-pins it. If a source reports
`not fetched` from `sync-skills.sh` instead, the fetch has not run yet —
`sync-skills.sh` never clones, deliberately.

### 4. Create a vault

```bash
./scripts/init-vault.sh --path ~/vaults/VAULT_NAME --id VAULT_ID \
  --remote "https://github.com/YOUR_ACCOUNT/VAULT_REPO.git"
```

`--id` is what the guard checks *against* on every commit, so make it meaningful
(`personal`, `work`) — and see the note at the top of this page about it
matching `SBW_EXPECTED_VAULT_ID`. The remote is recorded but **not** pushed
to — create the repo yourself, private, first.

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
`--no-hook` opts out.

The vault starts with no domain practice notes. It does get four cross-cutting
notes describing how the vault itself operates, because `update-second-brain`
reads them at runtime.

When no config file exists yet, this also writes one with `SBW_VAULT` and
`SBW_EXPECTED_VAULT_ID` and prints it. Those two must agree with `--id`, and
here is the one moment both are known, so they can't be made to disagree by
hand. An existing config file is never touched — you get told which line to
add. `--no-config` skips it.

**Check.** Three things, and all three were informative in a real setup:

```bash
cat ~/vaults/VAULT_NAME/vault.json
grep -c 'second-brain-workflow: vault-commit guard' ~/vaults/VAULT_NAME/.git/hooks/pre-commit
git -C ~/vaults/VAULT_NAME remote -v
```

```
{
  "id": "work",
  "remote": "https://github.com/YOUR_ACCOUNT/work-brain.git",
  "schema_version": 1
}
1
origin	https://github.com/YOUR_ACCOUNT/work-brain.git (fetch)
origin	https://github.com/YOUR_ACCOUNT/work-brain.git (push)
```

The `id` must be the string you meant. `grep -c` returning `1` is what proves
the hook is *ours* rather than merely present — a foreign `pre-commit` hook
passes an `ls` and guards nothing. Empty `remote -v` output means `--remote` was
omitted; you can add it later with `git remote add origin`, but `vault.json`
will still say `""`, and the guard compares the two.

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
matches nothing, silently, and you are back to whatever the global identity was.

**Check.**

```bash
git -C ~/vaults/VAULT_NAME var GIT_AUTHOR_IDENT
```

```
Your Name <you@work.example.com> 1785997372 +0300
```

`git var` is the right question to ask: it resolves `includeIf`, the
environment and every fallback, which reading one config file does not. If the
address here is not the one you want in the vault's history, fix it *now* —
after a push it takes a history rewrite on a repo you may not control.

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
# must match --id from step 4
SBW_EXPECTED_VAULT_ID=VAULT_ID
EOF
cat "$config"      # confirm what actually landed
```

Those two are the only keys with no sensible default for this machine. The rest
have working defaults and are **choices**, so they are not in a block described
as paste-and-run — pasting a choice is how a Cursor user ends up rendering
`claude-code,agents`. Add the ones you actually want:

```bash
# Only the agents you use. Default: cursor,claude-code,agents
echo 'RENDER_TARGETS=cursor,agents'                >> "$config"

# Only the skills directories you use. Default: both.
# Read the SKILLS_DIRS note under step 3 first — narrowing does not uninstall.
echo 'SKILLS_DIRS=~/.cursor/skills'                >> "$config"

# Only if rules live in a separate repo.
echo 'SBW_RULES_DIR=~/dev-conventions/rules'       >> "$config"
```

`make init` writes the same keys, previews first, and appends only what is
missing — see [the short way](#the-short-way).

See `config.example` for every key. Precedence is CLI flag > environment > this
file > defaults. Two format rules that bite if broken: the file is parsed, not
sourced, so **only a leading `~` is expanded** (`$HOME/...` stays literal), and
**a comment must start its own line** — `SBW_EXPECTED_VAULT_ID=work  # ...`
sets the id to `work  # ...`, and the guard then rejects every commit for an
id mismatch it can't explain.

`SBW_EXPECTED_VAULT_ID` is what makes the commit guard non-circular: it's read
from *this machine's* config, never from the vault's own `vault.json` — so a
repointed or freshly cloned vault can't bring its own "correct" answer along
with it. Without it (and without `--expect-id`), the guard fails closed rather
than silently skipping the check.

**Check.** This is the checkpoint that catches a config the tooling can't see:

```bash
make doctor VAULT="$HOME/vaults/VAULT_NAME"
```

```
second-brain-workflow doctor — vault: ~/vaults/work-brain
  ok    commit guard installed as a pre-commit hook in ~/vaults/work-brain
  ok    vault.json pins no commit author — the check is opt-in, so it is not running here
        a vault created before this feature has no identity block; add one to enable it:
          "identity": { "email": "you@example.com" }
  ok    only one skills directory configured — nothing to compare across
  warn  1 of our skill link(s) in ~/.cursor/skills, which is not in SKILLS_DIRS
  ok    no rules to render — <engine>/rules holds none (from the default — SBW_RULES_DIR is unset)
        This machine renders nothing into a repo. That is a supported way to run
        the engine; set SBW_RULES_DIR in <config> if it is not what you wanted.
  ok    no skills manifest configured — roster checks skipped
        (set SBW_SKILLS_MANIFEST in <config> to declare one)
  ok    vendored submodule(s) match the commit this checkout pins
  ok    no repos carry rendered output here, and the registry names none
        scanned scope: roots=~ depth=5

1 thing(s) worth a look — setup unfinished, nothing misconfigured.
```

**That `warn` is produced by this walkthrough**, and it is correct. Step 3 ran
`sync-skills.sh` before any config existed, so it installed into the built-in
default — *both* `~/.cursor/skills` and `~/.claude/skills`. Narrowing
`SKILLS_DIRS` above does not uninstall anything; it stops the tooling looking at
the other directory, and this check exists to say so rather than let an install
go quietly unmanaged. Either widen `SKILLS_DIRS` again, or run
`./scripts/uninstall.sh` and re-run `sync-skills.sh` with the config in place.

**Exit `1`, not `0`.** A first run through these steps ends with warnings, which
is the *setup unfinished* code and not a failure.

If your rules live elsewhere, the `no rules to render` line is where you will see
it — it names any rules directory it finds on the machine that `SBW_RULES_DIR`
does not point at.

Write `$HOME`, not `~`: make performs no tilde expansion, and neither does zsh
in a variable argument, so `VAULT=~/vaults/...` stats nothing. Plain
`make doctor` with no `VAULT=` resolves the vault from this config the same way
the scripts do, which is the better check that the config is being read at all.

Exit codes: `0` all clear, `1` warnings (setup unfinished), `2` at least one
error (something is misconfigured and finishing setup won't fix it). See
[docs/GUARD.md](GUARD.md#exit-codes).

### 6. Prove the toolchain works here

```bash
make test               # the toolchain itself, against fixtures — needs no extra tools
make check              # the above plus shellcheck, if it is installed
make verify-claude      # if you use Claude Code — costs three model calls
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

### 7. Make the first commit

The setup isn't proven until a commit has actually gone through the guard.

```bash
cd ~/vaults/VAULT_NAME
git add -A
git commit -m "practices: first note"
```

**Check.** The guard's own line must appear *above* git's:

```
guard: ok — 17 file(s), 303 line(s), vault 'work'
[main (root-commit) 09ccdf3] practices: first note
 17 files changed, 303 insertions(+)
```

That line is the whole point of this checkpoint: it proves the hook ran, that it
resolved an expected id, and that the vault it saw is the one you named. No
`guard:` line at all means the hook never ran — check step 4's `grep -c`. A
`guard:` line that refuses is doing its job; find the message in
[Troubleshooting](#troubleshooting).

What it checked, in one commit: every staged path is inside the vault's allowed
set, `vault.json`'s id is the one this machine expects, `origin` matches what
`vault.json` records, the commit's author matches any declared identity, the
diff isn't implausibly large, no `enforced` note was deleted, and nothing looks
like a conflict marker or a credential.

### 8. Onboard one repo, then work

```bash
./scripts/render.py /path/to/a/repo
```

Or say **onboard repo** to an agent. Then work normally, and say **update second
brain** at the end of a session. Your first practices come from what you
actually did — do not scaffold them.

**Check.** `./scripts/render.py /path/to/a/repo --check` exits 0 when the
rendered files match what the current rules would produce, and 1 on drift. Run
it in that repo's CI, not just here.

The render also records this repo in
`${XDG_CONFIG_HOME:-$HOME/.config}/second-brain-workflow/repos`, so that later
"re-render everything" is a list rather than a glob you have to guess — see the
README's [repo registry](../README.md#the-repo-registry). `--check` and
`--dry-run` don't write it. On a machine that onboarded repos before this
existed, `make doctor` scans for them and names each one it finds that the
registry does not — re-rendering registers it.

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

### 9. Set up CI (optional, per vault)

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

**Check.** Run each copied workflow once by hand from the vault repo's Actions
tab (`workflow_dispatch`) rather than waiting for the schedule or the next push.
A misconfigured `ENGINE_REF`, a missing rules-repo secret or an Actions
permission that won't let `audit.yml` open its tracking issue all surface
immediately that way, instead of a week later in a run nobody is watching.

---

## Troubleshooting

Every row here is something that actually went wrong during a first setup, not
a hypothetical.

| Symptom | Cause and fix |
|---|---|
| `make doctor` says **All checks passed** on a machine that renders nothing into any repo | Before v0.21.0 no check looked at the rules directory, so a machine with `SBW_RULES_DIR` unset and an unreferenced rules repo cloned beside the engine reported clean. `doctor` now prints a rules line in all four states and names any rules directory it finds. Set `SBW_RULES_DIR`. |
| `make init YES=1` wrote `SBW_VAULT` pointing at a vault that does not exist, and the first commit fails on an id mismatch | Running `init` before creating the vault, on a version before v0.22.1. `init-vault.sh` writes the vault path and its id together and leaves an existing config alone, so a config written first is never corrected. Create the vault first; current `init` refuses to write the key and says so. |
| `zsh: no such file or directory: account` | You pasted a snippet containing `<account>`; zsh read `<account>` as a redirection and aborted the command *before* the script ran — while the next line of the block still executed, leaving a half-finished setup. The docs no longer contain such placeholders; if you are following an older copy, replace every `<...>` before pasting. |
| `zsh: no such file or directory: /Users/…/config` right after a `mkdir` | An unset `$EDITOR` expanded to nothing, so the shell tried to execute the path. Nothing is wrong with the directory. Use step 5's heredoc, which needs no editor. |
| `fatal: empty string is not a valid pathspec` | `git checkout "$latest"` with no release tag resolved. Step 1's snippet echoes `latest` and skips the checkout when it is empty. |
| `guard: no expected vault id configured for this machine` | `SBW_EXPECTED_VAULT_ID` isn't set anywhere, and the guard fails closed rather than guessing. Set it in the config file (step 5) — or re-run `init-vault.sh` on a machine with no config and it writes it for you. |
| `guard: vault id mismatch: expected 'personal', found 'work'` | The classic disagreement from the top of this page. One of the two is wrong; decide which, then fix that one. |
| `guard: vault id mismatch: expected 'work   # must match --id', found 'work'` | An inline comment in the config file became part of the value. Comments must start their own line. |
| `guard: commit author does not match the identity …` | `user.email` resolves to the wrong address for this vault. The message carries the exact `git config` command; the durable fix is the `includeIf` above. |
| Commits already pushed under the wrong name | The author is recorded in history, so fixing config now changes nothing already committed. `git log --format='%h %ae'` shows the damage; correcting it means rewriting history on that repo. Set the identity *before* the first commit — step 4's output and `make doctor` both tell you in advance. |
| `no such path: ~/vaults/… — it came from SBW_VAULT in …/config` | The configured vault path doesn't exist. The message names which knob produced it, so you know which one to correct. This is an error (exit 2), not unfinished setup. |
| `… exists but is not a git repo — setup is unfinished` | The directory is there but was never initialised. Run `init-vault.sh … --adopt`. This is distinct from the row above on purpose: one means the configuration is wrong, the other that setup stopped early. |
| `make doctor` reports a different vault than your config names | Older versions re-derived the vault in make syntax, which cannot read the config file, so every `make` target used the built-in default. Fixed; if you still see it, check for `SBW_VAULT` or `VAULT` exported in your shell, and note that `VAULT=~/…` on a make command line stays a literal tilde — use `$HOME`. |
| `shellcheck not installed` then `make: *** [lint] Error 1`, and no tests ran | Exactly what it says, and `make lint` treats it as an error because you asked for it by name. `make check` instead prints `skipped — install shellcheck to enable` and runs everything else. `make test` needs no extra tools at all. |
| Skills missing from one agent but not the other | A name collided in one directory, or Railway wrote `use-railway` into `~/.claude/skills` only. `make doctor` reports the asymmetry and prints the exact `ln -s`. |
| Broken skill links after deleting a checkout | `make uninstall` from *any* checkout finds them — it reports each as `dangling, from a deleted checkout` — and `YES=1` removes them. A broken link that isn't ours is listed and left alone. |

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
isn't the one expected, an `origin` that doesn't match `vault.json`, a commit
author that isn't the declared identity, an implausibly large diff, deletion of
an `enforced` note, conflict markers, and anything resembling a credential.

- **The fast path.** `update-second-brain` runs it before every commit it
  makes.
- **The local backstop.** Step 4 installs it as this vault's `pre-commit`
  hook by default, so a hand-run `git commit` here — no skill, no agent — is
  guarded too. `make doctor` reports a vault whose hook is missing or isn't
  ours.
- **The one that can't be skipped.** `git commit --no-verify` skips the
  pre-commit hook, and there's no way to stop that locally. Copy
  `docs/vault-ci/guard.yml` into `.github/workflows/guard.yml` **in the vault
  repo** (same place as step 9's `audit.yml`) so a bypassed commit is still
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
