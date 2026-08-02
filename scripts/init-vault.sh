#!/usr/bin/env bash
# Create a second-brain vault with the structure the tooling expects.
#
# Usage:
#   ./init-vault.sh --path <dir> --id <id> [--remote <url>] [--adopt]
#
#   --path    where the vault goes, e.g. ~/vaults/work-brain
#   --id      short identifier, e.g. work — recorded in vault.json and checked
#             by guard-vault-commit.sh before every commit
#   --remote  git remote to add (not pushed; create the repo yourself, private)
#   --adopt   allow a non-empty directory (adds only what is missing)
#
# Idempotent: re-running adds missing pieces and leaves existing files alone.
#
# Writes no *domain* practice notes — a vault's content is earned, not
# scaffolded. It does seed the four cross-cutting notes that describe how the
# vault itself operates, because `update-second-brain` reads them at runtime.
set -euo pipefail

STANDARDS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PATH_ARG=""; ID=""; REMOTE=""; ADOPT=0
while [ $# -gt 0 ]; do
  case "$1" in
    --path)   PATH_ARG="${2:?--path needs a value}"; shift 2 ;;
    --id)     ID="${2:?--id needs a value}"; shift 2 ;;
    --remote) REMOTE="${2:?--remote needs a value}"; shift 2 ;;
    --adopt)  ADOPT=1; shift ;;
    -h|--help) sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

[ -n "${PATH_ARG}" ] || { echo "Missing --path" >&2; exit 2; }
[ -n "${ID}" ] || { echo "Missing --id" >&2; exit 2; }
case "${ID}" in
  *[!a-z0-9-]*) echo "--id must be lowercase letters, digits and hyphens: ${ID}" >&2; exit 2 ;;
esac

# Expand a leading ~ without eval.
# shellcheck disable=SC2088  # the "~/" below is a literal pattern being matched,
# not a path we expect the shell to expand — expanding it is the point.
case "${PATH_ARG}" in
  "~/"*) VAULT="${HOME}/${PATH_ARG#\~/}" ;;
  *) VAULT="${PATH_ARG}" ;;
esac

if [ -e "${VAULT}" ] && [ "${ADOPT}" -eq 0 ]; then
  if [ -n "$(ls -A "${VAULT}" 2>/dev/null)" ]; then
    echo "Refusing to write into a non-empty directory: ${VAULT}" >&2
    echo "Pass --adopt to add only what is missing." >&2
    exit 1
  fi
fi

created=0
note() { echo "  $1"; }
make_dir() { [ -d "$1" ] || { mkdir -p "$1"; note "created ${1#"${VAULT}"/}/"; created=$((created+1)); }; }
write_if_absent() {
  local dest="$1"
  if [ -e "${dest}" ]; then return 0; fi
  cat > "${dest}"
  note "created ${dest#"${VAULT}"/}"
  created=$((created+1))
}

echo "Vault: ${VAULT}  (id: ${ID})"
make_dir "${VAULT}"
for d in practices/app practices/backend practices/frontend practices/cross-cutting \
         _templates 00-maps bases; do
  make_dir "${VAULT}/${d}"
done
for d in app backend frontend cross-cutting; do
  [ -e "${VAULT}/practices/${d}/.gitkeep" ] || : > "${VAULT}/practices/${d}/.gitkeep"
done

write_if_absent "${VAULT}/vault.json" <<EOF
{
  "id": "${ID}",
  "remote": "${REMOTE}",
  "schema_version": 1
}
EOF

write_if_absent "${VAULT}/.gitignore" <<'EOF'
.DS_Store
.trash/
.obsidian/workspace.json
.obsidian/workspace-mobile.json
.obsidian/cache/
.obsidian/plugins/*/data.json
EOF

write_if_absent "${VAULT}/_templates/practice-note.md" <<'EOF'
---
domain:
applies-to: ""          # glob this maps to when promoted, e.g. **/*.component.ts
maturity: idea          # idea | trialing | enforced
last-reviewed:
repos: []               # one entry per repo/session observed
                        # length(repos) drives promotion: idea→trialing at 2, →enforced at 3
tags: []
---

# <Imperative practice title>

**Rule:**
**Why:**
**Example:**

**Observed in:** <narrative — repos, files, commits, exceptions>

## Related
-
EOF

write_if_absent "${VAULT}/_templates/daily-note.md" <<'EOF'
# {{date}}

## Built
-

<!-- Add another "## Built (label)" block per distinct work stream if needed.
     Everything below stays ONE section for the whole day — append to it,
     don't repeat the header. -->

## Practices followed
-

## Drift / gaps
-

## Vault candidates
-

## Vault writes (approved)
-

## Vault writes (declined)
-
EOF

write_if_absent "${VAULT}/00-maps/review-queue.md" <<'EOF'
# Review queue

Notes not reviewed in the last 180 days. (For maturity promotion, see
[[promotion-candidates]] — keep the two concerns apart, or age drowns in
maturity.)

```dataview
TABLE maturity, last-reviewed
FROM "practices"
WHERE date(last-reviewed) < date(today) - dur(180 days)
SORT last-reviewed ASC
```

## Broken links

Wikilinks with no matching file anywhere in the vault.

```dataviewjs
const broken = [];
for (const page of dv.pages()) {
  for (const link of page.file.outlinks) {
    if (!dv.page(link)) {
      broken.push([page.file.link, link.path]);
    }
  }
}
if (broken.length) {
  dv.table(["From", "Broken link"], broken);
} else {
  dv.paragraph("No broken links found.");
}
```
EOF

write_if_absent "${VAULT}/00-maps/promotion-candidates.md" <<'EOF'
# Promotion candidates

Notes that have cleared the maturity bar but haven't been promoted yet.
Evidence = number of entries in each note's `repos:` list.

- `idea` → `trialing`: observed in **2+** repos
- `trialing` → `enforced`: observed in **3+** repos

Clearing the bar is necessary, not sufficient: `trialing` has to be *earned* by
deliberate re-application, so a note promoted today does not become `enforced`
tomorrow on the same evidence.

```dataview
TABLE maturity, length(repos) AS "repos", last-reviewed
FROM "practices"
WHERE (maturity = "idea" AND length(repos) >= 2)
   OR (maturity = "trialing" AND length(repos) >= 3)
SORT length(repos) DESC
```
EOF

if [ -f "${STANDARDS_DIR}/vault-template/practices.base" ]; then
  [ -f "${VAULT}/bases/practices.base" ] || {
    cp "${STANDARDS_DIR}/vault-template/practices.base" "${VAULT}/bases/practices.base"
    note "created bases/practices.base"
    created=$((created+1))
  }
fi

# Seed the vault's own operating rules. These are not domain practices — they
# are the rules `update-second-brain` reads at runtime and follows verbatim, so
# a vault without them runs the capture workflow with its instructions missing.
# They ship as `enforced` under the enforced-by-preference exception: a process
# rule can never satisfy the 3-repo bar it defines.
META_SRC="${STANDARDS_DIR}/vault-template/practices/cross-cutting"
if [ -d "${META_SRC}" ]; then
  today="$(date +%Y-%m-%d)"
  for src in "${META_SRC}"/*.md; do
    [ -e "${src}" ] || continue
    dest="${VAULT}/practices/cross-cutting/$(basename "${src}")"
    [ -e "${dest}" ] && continue
    sed "s/{{DATE}}/${today}/g" "${src}" > "${dest}"
    note "created practices/cross-cutting/$(basename "${src}")"
    created=$((created+1))
  done
fi

if [ ! -d "${VAULT}/.git" ]; then
  git -C "${VAULT}" init -q
  note "git init"
fi
if [ -n "${REMOTE}" ] && ! git -C "${VAULT}" remote get-url origin >/dev/null 2>&1; then
  git -C "${VAULT}" remote add origin "${REMOTE}"
  note "remote origin -> ${REMOTE}"
fi

"${STANDARDS_DIR}/scripts/build-vault-index.py" --vault "${VAULT}" >/dev/null
note "generated practices/INDEX.md"

echo
if [ "${created}" -eq 0 ]; then
  echo "Already complete — nothing to add."
else
  echo "Added ${created} item(s)."
fi
cat <<EOF

Next:
  1. Open ${VAULT} in Obsidian (enable Dataview for 00-maps/).
  2. Point this machine at it:
       SBW_VAULT=${VAULT}
     in \${XDG_CONFIG_HOME:-~/.config}/second-brain-workflow/config
  3. Create the remote yourself — **private** — then push.
  4. Capture a session: say "update second brain".

This vault ships only its own operating rules, in practices/cross-cutting/ —
update-second-brain reads those at runtime. Everything else is earned: domain
practices come from sessions that actually happened, not from a template.
EOF
