---
name: unrender-repo
description: >-
  Retire a repo from the standards system: remove the rule files a render put
  there, drop the local exclusion block, and forget the repo so doctor stops
  reporting it. Preview first, act only on --yes. Use when the user says
  unrender, un-onboard, retire this repo, remove the rendered rules, stop
  tracking this repo, take the standards out of here, or is abandoning a repo
  that doctor keeps naming. Not for deleting a repo — this leaves the repo
  intact and removes only what the engine put in it.
---

# Unrender a repo

The inverse of `onboard-repo`. Removes what `render.py` wrote into a target
repo and takes that repo out of the registry, in one act.

**Preview by default.** This deletes files in a repo the engine does not own,
so the first run always reports and changes nothing.

## The command

```bash
~/second-brain-workflow/scripts/render.py --unrender "<TARGET>"        # preview
~/second-brain-workflow/scripts/render.py --unrender --yes "<TARGET>"  # act
```

Or `make unrender REPO=<TARGET>` / `make unrender REPO=<TARGET> YES=1`.

Show the user the preview output before running with `--yes`, unless they
already asked for it in the same breath ("unrender it", "just do it").

## What it removes

| Removed | Condition |
|---|---|
| `.cursor/rules/*.mdc`, `.claude/rules/*.md` | only files carrying the provenance marker |
| `AGENTS.md`, `CLAUDE.md` | only if they carry the marker |
| `.sbw-version` | always — the engine owns it outright |
| the `.git/info/exclude` block | only if the repo was rendered `--local` |
| the registry entry | if the registry names the repo |
| `.cursor` / `.claude` themselves | only if taking the rules directory out left them empty |

Anything without the marker is hand-written and is left alone — the same rule
`render.py` follows when writing. A hand-written `CLAUDE.md` survives; so does
a `.cursor/rules/local-only.mdc` a human put there.

**It never searches the repo for the marker.** Only the paths render.py itself
writes are candidates. A repo can legitimately contain the marker string as
content — this engine's own landing page quotes the provenance header as copy —
and a grep-based implementation would offer to delete the product.

## Both halves, or neither

Doing half of this by hand is what leaves a repo doctor complains about forever:

- `rm -rf` the repo, or delete the rendered files by hand → the registry still
  names it, and every check reports a **stale entry** or a repo that **drifted**.
- Remove the registry line by hand → the files are still there, and the scan
  reports the repo as **rendered but not registered**.

Running the command is what closes both. If the user is deleting the repo
directory, unrender it *first* — once the directory is gone there is nothing to
run the command against, and only a hand-edit of the registry is left.

## After

Re-onboarding is just a render: `render.py "<TARGET>"`. Nothing about
unrendering is destructive to the repo's own history — every file it removes is
one the engine generated and can generate again.

Report to the user what was removed and that the repo is no longer tracked.
Do not offer to delete the repo directory; that is theirs to do.

## Boundary

- Onboarding a repo, or re-rendering one that drifted: **`onboard-repo`**.
- Removing skills installed on this *machine*: `make uninstall` — a different
  question, and it never touches a target repo.
- A repo the registry names that no longer exists on disk: unrender cannot help
  (there is no directory to act on). Say so, and that the entry is inert.
