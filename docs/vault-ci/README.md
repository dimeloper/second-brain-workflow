# Weekly audit for a vault repo

`check-lineage.py` and `rule-budget.py` are the review side of this system:
does an `enforced` note actually have a rule, is that rule's evidence still
real, is the always-on rule set still within budget. Both are read-only and
both run fine locally — but a target you have to remember to run is a target
that quietly stops getting run, which is exactly the problem the capture side
(`update-second-brain`) doesn't have, since it's automated. The engine's own
CI can't close that gap: CI here has no vault. A vault repo does, by
definition — that's where this belongs.

`audit.yml` is a template, not something this engine runs for you. Copy it
into the vault repo you want audited and adjust it there.

## Setup

1. Copy `audit.yml` to `.github/workflows/audit.yml` in your vault repo.

2. Set `ENGINE_REF` in the copied file to the tag you want this workflow
   pinned to — same discipline as any other rollback (see the main
   [README's Versioning section](../../README.md#versioning)). Bump it
   deliberately when you want the audit running newer checks, not
   automatically.

3. **Point it at a rules directory — this is not optional.** Read this
   before assuming a partial audit is possible without one:

   `check-lineage.py` and `rule-budget.py` both exit immediately if their
   rules directory doesn't resolve to a real directory (`sys.exit`, not a
   warning). Neither script has a "vault-only" partial mode — an orphaned
   rule check, a rule-budget estimate, all of it needs the actual `rules/`
   content to compare against. If the workflow can't reach a rules
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

## What it does, and doesn't, fail the run for

Only `check-lineage.py`'s own exit code decides whether the job goes red: `1`
means an orphaned rule was found — a rule actively citing evidence that no
longer exists, the one finding that script itself treats as a real block.
Everything else from both scripts — unpromoted notes, stale claims, thin
evidence (including a near-miss preference marker), an over-budget rule
set — is folded into a single tracking issue (opened once, updated in place
on every run, labeled `audit`) rather than a build break. That's narrower
than local `make audit`, which fails on either script; the difference is
deliberate — a weekly automated run should surface a backlog to work
through, not page anyone for something that isn't actually broken.

One nuance worth knowing: an unparseable vault-derived threshold (a reworded
or missing `promotion-candidates.md`) is *also* a hard, non-zero exit from
`check-lineage.py` — same exit code as an orphaned rule, because both are
"the check couldn't do its job," not "the check ran and found nothing." That
means a broken threshold source will also turn this job red, not just
appear quietly in the issue body. That's intentional: a configuration break
deserves at least as much attention as an orphaned rule, and folding it
silently into the backlog would be exactly the kind of "green but
misleading" result this script is built to avoid — see `check-lineage.py`'s
own docstring for the reasoning.

## Never automated

The human gate from `enforced` note to distilled rule stays human. This
workflow reports and blocks (on orphaned rules only); it never creates,
edits, or promotes a rule or a practice note on its own.
