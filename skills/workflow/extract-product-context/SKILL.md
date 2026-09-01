---
name: extract-product-context
description: >-
  Draft a project's context/ — audience, voice, brand — from a product repo's
  own files rather than from memory, daily notes or store copy. Read-only.
  Use when writing or revising context/ for a project doc, when asked who a
  product is for, what it sounds like, or where it stops, or before writing
  anything public about a product. Writing to the vault is the
  update-second-brain skill's job, never this one.
---

# Extract product context

**A product defines itself in its repo. Everything else describes it.**

This skill exists because of a specific, repeatable mistake. On 2026-08-31 the
first `context/` written for an app claimed the product ended at birth. No
source said that — it was inferred from the vocabulary of the store listing and
labelled `[verified]`. The repo held a `ROADMAP.md` with a phase named
*Post-Birth Retention*, install and conversion figures, and a written boundary
against a sibling product. None of it was read, because the two sources that
*talk about* a product — the daily notes and the store copy — are the two that
come to mind, and nothing said to look further.

So the rule this skill enforces is an ordering, not an effort level.

## Run this first

```bash
~/second-brain-workflow/scripts/context-sources.py --repo "$PWD"
```

Read-only, opens nothing. It lists where the repo states itself, in four tiers
of authority, and **names the tiers that are empty** — which is the half that
matters, because an empty tier means the answer is not in this repo and must be
asked for rather than derived from a tier that happens to be full.

## The four tiers, and why the order is the point

| Tier | Holds | Authority |
|---|---|---|
| 1 · product docs | `ROADMAP.md`, `KNOWLEDGE_BASE.md`, `PRODUCT.md`, `docs/features/**` | **Highest.** Written to state intent — what the product is *for*, where it stops, what it refuses to be |
| 2 · store metadata | `store/listings/**`, `metadata/{ios,android}/`, `fastlane/` | The **pitch**. Authoritative on voice and claims; on audience only as marketing believes it |
| 3 · shipped surface | locales, routes, paywall and flag config | What the product **is**. Contradicts tier 2 when they disagree, and it is right |
| 4 · brand | tokens, theme, `app.config.*`, `assets/` | Point at these; do not restate them |

**Tier 1 before tier 2, always.** A roadmap says what the product is for; a
listing says what will make someone install it. They disagree often, and reading
them in the wrong order produces a confident wrong answer — which is the defect
above, exactly.

**When tier 3 contradicts tier 2, tier 3 wins and the contradiction is the
finding.** In the case that produced this skill, the listing was English-only
while the app shipped six locales at full parity. Neither fact is interesting
alone; together they are a gap worth someone's attention.

## Three rules, and they are the skill

**1. Quote, do not characterise.** Put the source's words in the file, in
quotation marks, with the file and section they came from. A paraphrase is an
inference wearing a citation. Where a characterisation is genuinely needed, say
so in the sentence: *"this is a reading of the Plus list, not a quote from it."*

**2. `[verified]` means read on disk today, and never covers a section.** The
marker is per claim. Labelling a heading `[verified]` because its *source* was
verified is how an inference gets smuggled in beside four facts — which is
precisely what happened. If a sentence is your conclusion rather than the file's
statement, it is `[second-hand]` at best, and usually belongs under *Not
established*.

**3. Name what you could not find.** An empty tier, a question no file answers,
a number nobody recorded — write it down as unestablished. A `context/` that
says "no source states the audience" is more useful than one that quietly
supplies a plausible audience, because the first can be fixed by asking and the
second cannot be detected.

## What to write

Draft into `projects/<project>/context/`, one file per question, and **only the
files the evidence supports**:

- `audience.md` — who, what they are trying to do, where the product stops,
  what it refuses to be, and any traction figures the repo records
- `voice.md` — **point** at the canonical artifact if one exists
  (`store/listings/**`, `metadata/**`), and describe only what reading it
  reveals. Hold prose *only* when tier 2 is empty
- `brand.md` — point at tokens or a theme when they exist. When tier 4 has only
  images, say that the prose here is the record because there is no artifact to
  point at

**Do not create a file to complete the set.** A missing `brand.md` because the
repo has no palette source is a correct outcome; inventing one to fill a
template is the failure this skill exists to prevent.

## Then hand off

This skill **never writes to the vault**. Show the draft in full, and let
`update-second-brain` write what is approved — the same contract
`obsidian-knowledge-base` holds. `project-for.py` is how a later session reads
the result back.

## When to run

| Trigger | What to do |
|---|---|
| Writing `context/` for a project | Full pass, tier 1 first |
| "Who is this product for?" | Tier 1, then tier 3. The listing is the last place to look, not the first |
| Before writing anything public — marketing, ASO, social, release notes | `voice.md`'s pointer, then the artifact it points at |
| A `context/` file older than the last few releases | Re-run and diff: a roadmap written against v1.0.1 is evidence about v1.0.1 |
| `check-context-freshness.py` reports one `STALE` | The same re-run, and bump `last-reviewed` only after re-reading — dating a file you did not re-check turns "unverified" into a false "verified" |
| Asked to infer audience or positioning with no repo to hand | Say the repo is where the answer lives, and that you have not read it |
