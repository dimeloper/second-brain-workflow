# Auditing the vault

`make audit` runs four read-only scripts against a real vault — the review
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

Record that lineage: add `source:` to the rule's frontmatter, naming the note
or notes it was distilled from by slug (the same slug every `[[wikilink]]` in
the vault already uses). One or several — a rule is routinely distilled from
more than one note, and naming one of seven would leave the other six reading
as unpromoted:

```yaml
source: prefer-signal-apis
source: [validate-at-the-boundary, fail-fast-env-validation]
```

A single slug is read as a one-element list, so both forms are equivalent and
nothing written the old way needs changing. Every slug is checked on its own: a
rule covers each note it names, and is orphaned by any one of them going
missing. Nothing renders it — `source:` never reaches
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
for a different purpose), **maturity above its evidence** (a maturity whose
entry bar the note's evidence does not meet — repos for a scoped note,
`applications:` for a process one where the vault declares that bar; `trialing`
under the idea→trialing bar, `enforced` under the trialing→enforced one, both
read from `00-maps/promotion-candidates.md` rather than a second hardcoded copy
of the numbers; `idea` is the floor and has no bar to miss; a process note with
no `applications:` recorded is *uncounted* and reported as its own backlog line
rather than judged against either bar — exempting a note whose
`**Observed in:**` line says exactly "enforced by preference," this vault's own
way of marking a personal default that was never meant to clear that bar; a
note that's close but doesn't match exactly is still counted *and* named
separately as a near-miss, so a typo can't silently cost a note its exemption),
and **ready to promote** (the same comparison the other way: a repo count that
already clears the *next* bar while the maturity still says otherwise).

`promotion-candidates.md` computes that last one in Dataview, which renders in
Obsidian and nowhere else — so until it was reported here, neither `make audit`
nor CI could answer it, which is where a backlog actually gets read. It is
reported and never acted on: automated promotion was rejected deliberately, and
a report is what keeps a human gate being exercised rather than quietly
stopping.

Both comparisons count **distinct lineages**, not `repos:` entries. A repo that
was renamed, or seeded by `git archive` out of another, is one piece of evidence
under two names, and counting it twice promotes a note on evidence it does not
have — in the entry-bar direction as much as the ready-to-promote one. The
groups are declared in a ` ```lineages ` fence in `00-maps/promotion-candidates.md`,
one group per line, first name labelling the group:

```lineages
dev-standards, dev-conventions, second-brain-workflow
```

Keep the prose beside it explaining *why* a group exists rather than restating
its members, so the two can't drift. A vault with no fence has nothing to
collapse — a normal state, and the report says the counts are raw so a reader
knows which kind of number they have. Where a note's judged count is lower than
the `repos:` list they can see, the line says so (`3 listed, 1 collapsed by
lineage`); the visible list would otherwise be the one they trust.

If either threshold can't be read unambiguously — the file is missing, reworded past
recognition, or states two different numbers — the script exits with a
named, specific error rather than silently skipping the check. A malformed
`lineages` block is fatal the same way and for the same reason: a group of one
name collapses nothing and is a typo, and one repo named in two groups has no
answer. Raw counts silently substituted for lineage counts would be specific,
plausible, and wrong in the direction that generates work.

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

### Provisional rules

A rule may knowingly cite a source below `enforced`. Declare it, with the reason:

```yaml
source: [route-a-generated-asset-workflow-to-a-dedicated-repo]
provisional: read off what the tool writes, so no repo count will mature it
```

It is then counted as **provisional** rather than orphaned — printed on every
run, including when the count is zero, and never failing the audit.

The case it exists for is a rule that is not a distilled practice. A constraint
read off *what an external tool writes* — "this screenshot generator scaffolds a
Next.js app, so it must not run inside yours" — is as true on the first repo as
on the third. It has no evidence curve to climb, so the note it descends from
will sit at `idea` indefinitely and the rule would read as orphaned forever. The
alternatives were both worse: promote the note on one repo, which games the bar
the whole promotion model rests on, or withdraw a constraint that is true today.

**Check whether it is really provisional first.** Several exemptions written
here said some version of *"no repo count will mature this"* — which was true of
any process rule, not of these rules in particular, and was the repo bar's
problem rather than theirs. A note with `applies-to: ""` is now counted in
`applications:` (see [The maturity gradient](REFERENCE.md#the-maturity-gradient)),
so re-application in
the same repo *does* mature it. Reach for `provisional:` only when the rule has
no evidence curve **at all** — not merely no *cross-repo* one.

Two deliberate constraints:

- **Prose, never `true`.** `provisional: true` is rejected by `check-rules.py`. A
  boolean exemption outlives the reason it was added for with nothing left to
  read; a sentence is printed by every audit and can be judged stale by whoever
  reads it. One line — the frontmatter parser has no folded scalars.
- **It excuses an immature source, never a missing one.** A rule naming a note
  that does not exist stays orphaned regardless. With the note gone the lineage
  cannot be read at all, which is the state the check exists for, and letting a
  reason string suppress that would make the field the blanket opt-out it is
  written to avoid being.

Two notes sharing a filename in different `practices/` subdirectories is also a
hard error naming both paths. Rules reference notes by slug alone, so a
collision would otherwise let whichever note loaded last decide whether a rule
read as orphaned.

Otherwise exits 1 only for orphaned rules — that's the one finding that means a
rule is actively citing evidence that no longer exists; everything else,
provisional rules included, is a visible backlog rather than a block.

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
./scripts/check-followups.py --repo acme-backend          # group as another repo
./scripts/check-followups.py --no-repo-grouping           # one flat list
./scripts/check-followups.py --recent                     # the skill's window instead
./scripts/check-followups.py --recent --brief             # this repo in full, others tallied
```

An item carried forward by hand — rewritten into a later note because it is
still open, and reworded on the way — is reported once, as a **thread**: dated
and aged from its first mention, shown in its newest wording, with a
`restated 08-10, 08-11` line naming the notes in between. A heading reading
`(3 threads, 6 items)` means three tasks written across six lines. Matching
requires the same repo and two different notes, so two items written side by side
in one day's section are never collapsed however alike they read. `--no-threads`
reports every restatement separately.

An item naming a pull request, a branch, or a commit can also be checked against
that repo's main branch, and is annotated `[landed]`, `[closed]` (a PR closed
without merging), `[open]`, or `[unchecked]` with the reason. Only **this repo's**
items are probed unless `--landed-all` is passed; the skipped ones are counted in
a footer rather than left looking checked. Nothing is fetched, so a branch or
commit verdict from a checkout last fetched more than a week ago reports
`[unchecked] … too stale to judge` instead of a confident "not merged" — a PR
verdict reads GitHub and never goes stale. This is **on with `--recent` and off
here** — the `make audit` invocation above runs neither `gh`
nor git against another checkout, which is what keeps it working on the vault's
CI runner, where no repo is checked out and `gh` is unauthenticated. `--landed`
opts in anyway; `--no-landed` opts out of the skill's window.

```bash
./scripts/check-followups.py --recent --no-threads   # every restatement separately
./scripts/check-followups.py --landed                # check refs during the audit too
```

Repos are located by name through the render registry first, then a walk of
`SBW_SCAN_ROOTS` bounded by `SBW_SCAN_DEPTH`, with hits cached in
`${XDG_CONFIG_HOME:-~/.config}/second-brain-workflow/repo-paths`. A repo whose
directory name differs from its origin is not found by the walk; add a
`name<TAB>path` line to that file and it is.

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

A ticked item is reported too, when the tick says the work did not happen. A
closed follow-up carries an outcome — `#outcome/done`, `#outcome/dropped`,
`#outcome/superseded`, `#outcome/handed-off` with `#owner/<name>` — and the last
two are listed in a block of their own, **Closed without being finished**: an
accepted risk, or somebody else's backlog with a name against it. Neither is
open work and neither is finished work, and reporting them as either is the
failure this exists for. A bare `- [x]` closes exactly as it always did, so
every note written before the convention reads unchanged; once a window contains
one outcome tag, a footer counts how many of its ticks carry none. See the
reference's [Follow-ups close with an outcome](REFERENCE.md#follow-ups-close-with-an-outcome).

An item with no repo identified is a normal result, not a gap to close — plenty
of follow-ups (an email awaiting a reply, a key to revoke in a console) belong
to no repo at all. Tagging happens on the write side, in `update-second-brain`,
where the repo is known for certain.

## Rule frontmatter

`make audit` also runs `check-rules.py`, which validates the *shape* of every
rule's frontmatter rather than its content:

```bash
./scripts/check-rules.py --rules-dir ~/dev-conventions/rules
```

The failure it exists for is a misspelled key. Frontmatter is a plain mapping,
so an unrecognised key isn't an error anywhere — it's just a key nobody reads:

```yaml
sourse: prefer-signal-apis     # lineage silently unrecorded
path:  "**/*.ts"               # rule silently always-on, and billed for it
```

Both render, both look right in review, and both mean the opposite of what was
written — strictly worse than a missing field, which at least reports as
missing. So any key outside `paths`, `description` and `source` is an error
naming the offender and listing the known set. A rule with no `source:` at all,
an empty `source:`/`paths:`, and an unparseable frontmatter block are errors
too.

It deliberately does not check `description`, or whether globs survive Cursor's
comma-separated form: `render.py` already owns both, they change what renders,
and two scripts holding separate opinions about one field is how they drift.
This one owns the file's shape; `render.py` owns its output.

`rule.md.example` in the engine root is the annotated template for the format,
and a parity test fails if it and the validator fall out of step — a convention
living in a script but not in the template someone copies is exactly how
`source:` came to be missing from every hand-written rule in the first place.

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

## Note markdown

`make audit` also runs `check-markdown.py`, which is the one thing here that
looks at the *text* of a note rather than its frontmatter:

```bash
./scripts/check-markdown.py --vault ~/vaults/second-brain
```

It reports **one** defect: a code span that wraps across a line break.
CommonMark converts the line ending inside a span to a space and then strips at
most one leading space, so a hard-wrapped bullet's continuation indent survives
*inside* the span:

```markdown
- `eks-deploy-staging.yml` has had one throughout (`group:
  staging-<release>-<ns>`, `cancel-in-progress: false`).
```

renders as `group:` followed by **three** spaces. A config key that renders
wrong is a config key somebody copies wrong, in a document whose whole job is to
be trusted as a record. It has a second symptom too: while the span is wrapped,
the `<release>` and `<ns>` on the continuation line sit outside any single-line
span, so a tool reasoning line-by-line reads them as raw HTML tags.

**This is deliberately not a markdown linter.** The notes are hand-written prose
with deliberate hard wrapping, and most of what a general linter flags — line
length, list markers, heading spacing — is house style it would be wrong about.
The rule shipped with six real instances behind it, all found by eye on
2026-08-31 while every check the engine runs stayed green. A second rule goes in
when it has evidence of its own.

**Finding here, gate there.** `build-vault-index.py` reports the same problem —
it already opens every note, so it is the cheapest place to notice — but its
warnings print to stderr and do not affect its exit code, which is by design.
This script is the one that fails.

**Not in the commit guard**, and that is a decision rather than an omission. The
guard reads the staged *diff*, and a wrapped span is a property of two adjacent
lines: edit one of the pair and the diff shows a line with an odd backtick count
and no way to tell whether its partner closes it. The guard's contract is *this
write is aimed somewhere it should not go*; prose quality is not that.

`practices/**` and `projects/**` are scanned. **Daily notes are not** — every
note written before this check existed is full of prose nobody is going to
re-wrap, and the vault's own rule for `#outcome/` tags applies unchanged: check
what is being written, do not retrofit.

## Running it weekly in CI

A target you have to remember to run is a target that quietly stops getting
run — the failure mode `update-second-brain` doesn't have, since it's
automated. The engine's own CI can't close that gap (no vault), but a vault
repo has one by definition: `docs/vault-ci/audit.yml` is a workflow template
a vault repo can copy in to get this running weekly, opening or updating one
tracking issue with the findings rather than a red X for anything short of
an orphaned rule. See `docs/vault-ci/README.md` for setup, including the
honest version of what a private rules repo means for CI access.
