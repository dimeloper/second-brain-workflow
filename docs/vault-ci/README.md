# CI for a vault repo

Two independent templates, two different jobs. Neither runs anywhere until
you copy it into your vault repo — the engine's own CI can't run either one
itself, since CI here has no vault.

- **`audit.yml`** — the review side (`check-lineage.py`, `check-rules.py` and
  `rule-budget.py`), weekly, reporting to a tracking issue. See
  [Audit](#audit-audityml) below.
- **`guard.yml`** — the same checks `guard-vault-commit.sh` runs locally
  before every commit, run again against every push — the one layer a local
  `--no-verify` cannot skip. See [Guard](#guard-guardyml) below.

Copy whichever (or both) you want into `.github/workflows/` in your vault
repo, and adjust there — not here.

## Audit (`audit.yml`)

`check-lineage.py`, `check-rules.py` and `rule-budget.py` are the review side
of this system: does an `enforced` note actually have a rule, is that rule's
evidence still real, does its frontmatter say what its author believed, is the
always-on rule set still within budget. All are read-only and all run fine
locally — but a target you have to remember to run is a target
that quietly stops getting run, which is exactly the problem the capture side
(`update-second-brain`) doesn't have, since it's automated.

### Setup

1. Copy `audit.yml` to `.github/workflows/audit.yml` in your vault repo.

2. Set `ENGINE_REF` in the copied file to the tag you want this workflow
   pinned to — same discipline as any other rollback (see the main
   [Versioning section](../REFERENCE.md#versioning)). Bump it
   deliberately when you want the audit running newer checks, not
   automatically.

3. **Point it at a rules directory — this is not optional.** Read this
   before assuming a partial audit is possible without one:

   `check-lineage.py`, `check-rules.py` and `rule-budget.py` all exit
   immediately if their rules directory doesn't resolve to a real directory
   (`sys.exit`, not a warning). None of them has a "vault-only" partial
   mode — an orphaned rule check, a frontmatter check, a rule-budget
   estimate, all of it needs the actual `rules/` content to compare against.
   If the workflow can't reach a rules
   directory, **the audit does not run at all**, full stop; there's no
   softened output to fall back to. The template's "Rules directory not
   configured" step exists to make that failure clear and immediate rather
   than a confusing crash three steps later.

   Two shapes this takes:

   - **Self-contained** — your engine fork already has `rules/*.md` and
     `AGENTS.md` committed directly in it (see the main README's "Fresh
     start" step 2, self-contained option). Delete the "Check out the rules
     repo" step and its two `if:` guards from the copied workflow, and point
     both `--rules-dir` flags at `engine/rules` instead of `rules/rules`.

   - **Split** — rules live in a third, usually private, repo (the common
     case if you're using a shared/public engine fork and keeping your own
     conventions private — see the main README's "point at your rules"
     step for why). Set the `RULES_REPO` repository variable (Settings >
     Secrets and variables > Actions > Variables) to `owner/repo`, then give
     the workflow read access to it — the default `GITHUB_TOKEN` cannot
     reach across repos on its own. Pick one:

     - **Deploy key** (recommended — scoped to exactly one repo, read-only):
       ```bash
       ssh-keygen -t ed25519 -N '' -f rules-deploy-key
       ```
       Add `rules-deploy-key.pub` as a **read-only** Deploy key on the rules
       repo (Settings > Deploy keys). Add the private half (`rules-deploy-key`)
       as this workflow's repo secret `RULES_DEPLOY_KEY` (Settings > Secrets
       and variables > Actions > Secrets).

     - **Fine-grained PAT**, scoped to just the rules repo, `Contents:
       Read-only`. Store it as the `RULES_REPO_TOKEN` secret.

     Setting only one of the two secrets is enough — `actions/checkout` uses
     the SSH key when it's non-empty and falls back to the token otherwise,
     so the workflow doesn't need editing either way.

4. Confirm the repo allows Actions to open issues: Settings > Actions >
   General > Workflow permissions must allow "Read and write permissions"
   (or grant `issues: write` some other way) — otherwise the last step fails
   even though the audit itself ran fine.

5. Run it once by hand (`workflow_dispatch`, the Actions tab) before waiting
   for the weekly schedule, so a configuration mistake shows up immediately
   instead of a week later.

### What it does, and doesn't, fail the run for

Only `check-lineage.py`'s own exit code decides whether the job goes red: `1`
means an orphaned rule was found — a rule actively citing evidence that no
longer exists, the one finding that script itself treats as a real block.
Everything else from the other scripts — unpromoted notes, stale claims, thin
evidence (including a near-miss preference marker), a rule whose frontmatter
doesn't say what its author thought, an over-budget rule set — is folded into
a single tracking issue (opened once, updated in place
on every run, labeled `audit`) rather than a build break. That's narrower
than local `make audit`, which fails on any of them; the difference is
deliberate — a weekly automated run should surface a backlog to work
through, not page anyone for something that isn't actually broken.

One nuance worth knowing: an unparseable vault-derived threshold (a reworded
or missing `promotion-candidates.md`), a rules set where no rule declares a
`source:` at all, and two notes sharing a filename in different `practices/`
subdirectories are *also* hard, non-zero exits from
`check-lineage.py` — same exit code as an orphaned rule, because all of them are
"the check couldn't do its job," not "the check ran and found nothing." That
means a broken threshold source will also turn this job red, not just
appear quietly in the issue body. That's intentional: a configuration break
deserves at least as much attention as an orphaned rule, and folding it
silently into the backlog would be exactly the kind of "green but
misleading" result this script is built to avoid — see `check-lineage.py`'s
own docstring for the reasoning.

### Never automated

The human gate from `enforced` note to distilled rule stays human. This
workflow reports and blocks (on orphaned rules only); it never creates,
edits, or promotes a rule or a practice note on its own.

## Guard (`guard.yml`)

`guard-vault-commit.sh` is what `update-second-brain` and the vault's own
`pre-commit` hook both run before a commit — the checks documented in
[docs/GUARD.md](../GUARD.md) (path allowlist, size caps, no deleting an
`enforced` note, conflict markers, secret-shaped strings, the vault-identity
check, and — where `vault.json` declares one — the **commit-author** check).
Both of those run *before* a commit is made,
which means both are skippable: `git commit --no-verify` skips the hook,
and there is no equivalent to opt out of skipping — including for an agent
that decides a failing check is a reasonable thing to route around.

`guard.yml` runs the identical script — same flags, same checks — against
the pushed commit range instead of a staged index, since there's no staging
area once a push has already happened. This is the layer that can't be
`--no-verify`'d away.

That includes the commit-author check, which in range mode reads **each
commit's recorded author** and names the offending commit, rather than the local
config — by the time this runs, whatever config produced the commit is gone. So
`git commit --no-verify` with the wrong author is caught here, which is the
whole point.

**It only works if `ENGINE_REF` points at a release that has the check.**
Anything before `v0.4.0` predates it entirely, so a workflow pinned there runs a
guard that never looks at authorship — green, and checking less than you think.
The shipped templates track the current release; if you copied them earlier,
bump `ENGINE_REF` deliberately and re-read what you gained.

### Setup

1. Copy `guard.yml` to `.github/workflows/guard.yml` in your vault repo, and
   set `ENGINE_REF` the same way as in `audit.yml`.

2. Set the `EXPECTED_VAULT_ID` repository variable (Settings > Secrets and
   variables > Actions > Variables) to this vault's id (whatever `--id` was
   passed to `init-vault.sh`). **This must be a repository variable, not
   read from `vault.json`** — the same non-circular trust model the local
   guard uses: `vault.json` says what the vault *claims* to be, this
   variable says what's *expected*, and the check only means something if
   the two are independent. If you skip this, the guard does not silently
   pass — `guard-vault-commit.sh` fails closed on an unconfigured
   expectation, in CI exactly as it does locally.

3. Run it once by pushing a trivial, allowed change (or use `git commit
   --allow-empty`) to confirm it goes green before relying on it.

Unlike `audit.yml`, `guard.yml` needs no rules directory and no third repo —
every check it runs is vault-content-only.

### Be honest about what this does and doesn't fix

CI catches a bypass *after* the push, not before. For a private vault,
that's containment, not prevention: by the time this workflow runs, whatever
got committed already left the machine. If a real violation lands (a
misdirected note, a leaked-looking credential), the fix is `git revert` at
minimum, and — if the leak is real, not just a false-positive pattern match
— rewriting history to actually remove it from every clone and rotating
whatever credential was exposed. A green run before the push means the
violation never happened; a red run after means it's caught, not undone.

### Layering, end to end

Three enforcement points, in increasing order of how hard they are to skip:
the skill invocation (`update-second-brain` runs the guard before every
commit it makes) is the fast path; the local `pre-commit` hook is the
backstop for a hand-run `git commit`; `guard.yml` is push-time CI, the one
that survives `--no-verify`. See [docs/GUARD.md](../GUARD.md) for the same
three-layer summary in context.
