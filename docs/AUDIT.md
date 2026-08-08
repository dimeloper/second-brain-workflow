# Auditing the vault

`make audit` runs three read-only scripts against a real vault — the review
side of the capture-then-review loop the README's project model describes.
Read the README first for why this exists; this is the reference material.

```bash
make audit   # or run each script below individually
```

Like `guard` and `vault-index-check`, it needs a real vault and rules
directory, so it isn't part of `make check` — CI runs each script's own test
suite against fixtures instead.

## Lineage: rules ↔ practice notes

Practice notes are the source. When a note reaches `maturity: enforced`, a
human distills it into a rule under `rules/` (in whichever repo
`SBW_RULES_DIR` resolves to), then repos re-sync. Tooling reports; it never
promotes a note to a rule.

Record that lineage: add `source: <note-slug>` to the rule's frontmatter,
naming the note it was distilled from (the same slug every `[[wikilink]]` in
the vault already uses). Nothing renders it — `source:` never reaches
`.mdc`/`.claude/rules/*.md` output — it exists purely so the capture side
(automated) and the review side (otherwise entirely manual) can be
cross-checked:

```bash
./scripts/check-lineage.py --vault ~/vaults/second-brain   # or: make audit
```

Reports, read-only, never writes: an **unpromoted note** (`enforced`, no rule
traces back to it), an **orphaned rule** (its source note is gone or demoted
below `enforced`), a **stale claim** (`enforced`, unreviewed past
`--stale-months`, default 6 — the same 180-day window `review-queue.md` uses
for a different purpose), and **thin evidence** (`enforced` with fewer repos
than the vault's own idea→trialing→enforced bar, read from
`00-maps/promotion-candidates.md` rather than a second hardcoded copy of the
number — exempting a note whose `**Observed in:**` line says exactly
"enforced by preference," this vault's own way of marking a personal default
that was never meant to clear that bar; a note that's close but doesn't
match exactly is still counted as thin evidence *and* named separately as a
near-miss, so a typo can't silently cost a note its exemption). If that
threshold can't be read unambiguously — the file is missing, reworded past
recognition, or states two different numbers — the script exits with a
named, specific error rather than silently skipping the check.

Both lineage directions are computed from the rules that declare a `source:`,
which makes their coverage worth stating explicitly:

- **No rule declares one.** Both directions go vacuous — every `enforced` note
  reads as unpromoted because nothing claims it, and no rule reads as orphaned
  because nothing is ever looked up. The script reports coverage as
  undetermined, names the rules directory it read, prints neither count, and
  exits 1. Thin evidence, near-miss markers and stale claims still print: they
  come from the notes alone and stay valid. A count reachable by the code path
  that learned nothing is worse than no count.
- **Some do, some don't.** The unpromoted count is labelled as computed against
  only the sourced rules, and says how many were excluded — a note listed there
  may be covered by a rule that simply never recorded it, so the number is an
  upper bound.

Two notes sharing a filename in different `practices/` subdirectories is also a
hard error naming both paths. Rules reference notes by slug alone, so a
collision would otherwise let whichever note loaded last decide whether a rule
read as orphaned.

Otherwise exits 1 only for orphaned rules — that's the one finding that means a
rule is actively citing evidence that no longer exists; everything else is a
visible backlog, not a block.

## Stale follow-ups

`make audit` also runs `check-followups.py`, the long-range counterpart to the
`check-follow-ups` skill:

```bash
./scripts/check-followups.py --vault ~/vaults/second-brain   # or: make audit
```

The skill deliberately looks back only as far as the last few daily notes
that actually exist, so it survives a weekend or a vacation gap without
drowning in old news — but an item still `- [ ]` in a note *outside* that
window has nothing surfacing it again; it just stops being seen. This script
covers the rest: every `YYYY-MM-DD.md` at the vault root, not just the recent
few, reporting an open follow-up whose note is older than `--stale-days`
(default 30). Same shape as the stale-claim and thin-evidence findings
above — a backlog to notice, so it always exits 0.

Findings are grouped by repo when run from inside one, `This repo` first, then
`Other repos`, then `No repo identified` — the same ordering the skill uses, and
the same shared implementation (`scripts/lib/followups.py`), so the two can't
drift apart on what an item is or where it belongs. Grouping only: the count
comes before any heading and every item is listed exactly once, whatever repo it
belongs to. Attribution reads a `#repo/<name>` tag first, then the item's own
prose against the repo names the vault already uses, then a file path in the
current repo, then the note's `## Built` context.

```bash
./scripts/check-followups.py --repo housemaster-backend   # group as another repo
./scripts/check-followups.py --no-repo-grouping           # one flat list
./scripts/check-followups.py --recent                     # the skill's window instead
./scripts/check-followups.py --recent --brief             # this repo in full, others tallied
```

`--recent [N]` swaps the age cutoff for the `check-follow-ups` skill's window —
the N most recent notes that exist (default 4), today included, chosen by note
count and never by age, so a vacation-length gap costs nothing. It is the same
selection the skill describes, implemented here so the two cannot drift. Note
that `--stale-days` reports items *strictly* older than its argument, so even
`--stale-days 0` omits today; `--recent` is the only way to include it.

`--brief` is for the common case of standing in one repo: this repo's items in
full, every other repo as a single count line. Still not a filter — the total is
unchanged and the counts say how many exist — with one exception that survives
collapsing, because its urgency has nothing to do with where you are standing:
an item the note calls **blocking**, or a **live credential** to rotate or revoke,
is listed in full whatever repo it belongs to and keeps its repo name. Flags are
markers *in place* in the full report, never a second listing of the same item.

An item with no repo identified is a normal result, not a gap to close — plenty
of follow-ups (an email awaiting a reply, a key to revoke in a console) belong
to no repo at all. Tagging happens on the write side, in `update-second-brain`,
where the repo is known for certain.

## Rule token budget

`make audit` also runs `rule-budget.py`, estimating the always-on rule set's
per-turn cost — a rule with no `paths:` loads on every turn, for every agent,
whether or not it's relevant:

```bash
./scripts/rule-budget.py --targets cursor,claude-code
```

Measures the *rendered* output per target (frontmatter and provenance
comment included, not just the source file), since that's what actually
reaches an agent's context. Fails above a ceiling read from `.rule-budget` —
a plain integer, sibling of wherever `rules/` resolves to, same as
`AGENTS.md` — defaulting to 2000 if that file doesn't exist. This engine
ships no rules of its own, so there's nothing here to calibrate the starting
number against; run `make audit` once you have a real rule set and adjust
from what's actually there, not the other way around. See
`.rule-budget.example`.

## Running it weekly in CI

A target you have to remember to run is a target that quietly stops getting
run — the failure mode `update-second-brain` doesn't have, since it's
automated. The engine's own CI can't close that gap (no vault), but a vault
repo has one by definition: `docs/vault-ci/audit.yml` is a workflow template
a vault repo can copy in to get this running weekly, opening or updating one
tracking issue with the findings rather than a red X for anything short of
an orphaned rule. See `docs/vault-ci/README.md` for setup, including the
honest version of what a private rules repo means for CI access.
