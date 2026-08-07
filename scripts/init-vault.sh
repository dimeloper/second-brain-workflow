#!/usr/bin/env bash
# Create a second-brain vault with the structure the tooling expects.
#
# Usage:
#   ./init-vault.sh --path <dir> --id <id> [--remote <url>] [--adopt] [--no-hook]
#                   [--identity-email <addr>] [--no-config]
#
#   --path     where the vault goes, e.g. ~/vaults/work-brain
#   --id       short identifier, e.g. work — recorded in vault.json and checked
#              by guard-vault-commit.sh before every commit
#   --remote   git remote to add (not pushed; create the repo yourself, private)
#   --adopt    allow a non-empty directory (adds only what is missing)
#   --no-hook  skip installing the pre-commit hook (see below)
#   --identity-email
#              the address commits into this vault must be authored as,
#              recorded in vault.json and enforced by guard-vault-commit.sh.
#              Optional; without it commits are not checked against an author.
#              Only written when vault.json is created — see the note below.
#   --no-config
#              don't write this machine's config file even if none exists.
#
# Idempotent: re-running adds missing pieces and leaves existing files alone.
#
# Writes the machine config (SBW_VAULT + SBW_EXPECTED_VAULT_ID) when no config
# file exists at all, and prints exactly what it wrote. Without it the guard
# fails closed on the very first commit — the state a reader following only the
# README's Quickstart landed in, since the id in vault.json and the machine's
# expected id have to agree and nothing was setting the second one. An existing
# config file is never touched; --no-config skips this entirely.
#
# Installs guard-vault-commit.sh as this vault's pre-commit hook by default —
# the backstop that makes the identity check an invariant of committing here
# at all, rather than something that only runs when update-second-brain
# remembers to invoke it. Both run the exact same script; neither replaces
# the other. `make doctor` reports a vault whose hook is missing or foreign.
#
# Writes no *domain* practice notes — a vault's content is earned, not
# scaffolded. It does seed the four cross-cutting notes that describe how the
# vault itself operates, because `update-second-brain` reads them at runtime.
set -euo pipefail

STANDARDS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/vault-identity.sh
. "${STANDARDS_DIR}/scripts/lib/vault-identity.sh"
# ds_config_path gives one definition of where the config lives, rather than a
# second copy of the XDG logic here. ds_config_load is called for exactly one
# reason — to learn which vault this machine currently points at, so a second
# vault cannot be created claiming the same remote. This script still writes
# the config rather than obeying it: nothing below reads a resolved value to
# decide what to scaffold.
# shellcheck source=scripts/lib/config.sh
. "${STANDARDS_DIR}/scripts/lib/config.sh"
ds_config_load

PATH_ARG=""; ID=""; REMOTE=""; ADOPT=0; NO_HOOK=0; IDENTITY_EMAIL=""; NO_CONFIG=0
while [ $# -gt 0 ]; do
  case "$1" in
    --path)     PATH_ARG="${2:?--path needs a value}"; shift 2 ;;
    --id)       ID="${2:?--id needs a value}"; shift 2 ;;
    --remote)   REMOTE="${2:?--remote needs a value}"; shift 2 ;;
    --adopt)    ADOPT=1; shift ;;
    --no-hook)  NO_HOOK=1; shift ;;
    --identity-email) IDENTITY_EMAIL="${2:?--identity-email needs a value}"; shift 2 ;;
    --no-config) NO_CONFIG=1; shift ;;
    -h|--help) sed -n '2,35p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
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

# A pre-existing vault.json means this is an adopt of someone else's (or a
# wrong) vault, not a fresh one — verify identity before adding anything.
# Shared with guard-vault-commit.sh via scripts/lib/vault-identity.sh, so a
# vault whose id or remote doesn't match cannot silently gain content, even
# though init-vault.sh never touches existing files (write_if_absent) and so
# never needs the full commit guard's staged-diff checks.
if [ -f "${VAULT}/vault.json" ] && ! vault_identity_check "${VAULT}" "${ID}"; then
  echo "init-vault: ${VI_ERROR}" >&2
  echo "init-vault: refusing to adopt — this looks like a different vault." >&2
  exit 1
fi

# --- is this remote already claimed by another vault on this machine? -------
# Following the Quickstart on a machine that already had a work vault produced
# two vaults recording the same remote, with nothing to say so. That is never
# intentional, and it is how one vault's notes end up pushed over another's.
#
# Only the vault this machine's config points at is consulted: it is the one
# other vault we can find without guessing, and the one a session on this
# machine will actually be writing to. Compared on vault_remote_key, so the
# two spellings that produced the real case — one with .git, one without —
# don't read as two different remotes.
#
# Creation only. --adopt against a vault that already records this remote is
# the correct way to use an existing vault, not a conflict.
if [ -n "${REMOTE}" ] && [ ! -f "${VAULT}/vault.json" ]; then
  current="${SBW_VAULT:-}"
  if [ -n "${current}" ] && [ "${current}" != "${VAULT}" ] && [ -f "${current}/vault.json" ]; then
    vault_identity_check "${current}" "" || true
    if [ -n "${VI_REMOTE}" ] && \
       [ "$(vault_remote_key "${VI_REMOTE}")" = "$(vault_remote_key "${REMOTE}")" ]; then
      echo "init-vault: --remote is already claimed by the vault '${VI_ID:-?}' at ${current}" >&2
      echo "       this --remote  ${REMOTE}" >&2
      echo "       ${current}/vault.json  ${VI_REMOTE}" >&2
      echo "       Two vaults sharing one remote is how one vault's notes get pushed" >&2
      echo "       over another's. To use the existing vault on this machine, clone it" >&2
      echo "       and run --adopt against the clone. To create a genuinely new vault," >&2
      echo "       give it its own remote." >&2
      exit 1
    fi
  fi
fi

# The pairing of id and repository name is a strong signal, and a mismatch is
# usually the Quickstart followed verbatim — `vault_id=personal` kept because
# it looked like a working default, next to a work remote that was edited.
# A warning, not a refusal: "brain" and "notes" are legitimate names for a
# vault called anything, and refusing a naming convention nobody agreed to
# would be the tool inventing policy.
if [ -n "${REMOTE}" ]; then
  remote_base="$(vault_remote_key "${REMOTE}")"
  remote_base="${remote_base##*/}"
  case "${remote_base}" in
    *"${ID}"*) ;;
    *)
      echo "init-vault: warning: --id '${ID}' does not appear in the remote's name '${remote_base}'." >&2
      echo "       If the id is wrong, stop now: it is recorded in vault.json and in this" >&2
      echo "       machine's config, and the guard compares the two on every commit." >&2
      ;;
  esac
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

# The identity block is written only when the file is created. Adding a key to
# an existing vault.json would be an *edit*, and this script's one invariant
# under --adopt is that it adds missing scaffold files and never rewrites
# content it didn't write. A vault that already exists gets told how to add it
# by hand instead — see the note printed at the end.
if [ -n "${IDENTITY_EMAIL}" ]; then
  write_if_absent "${VAULT}/vault.json" <<EOF
{
  "id": "${ID}",
  "remote": "${REMOTE}",
  "identity": {
    "email": "${IDENTITY_EMAIL}"
  },
  "schema_version": 1
}
EOF
else
  write_if_absent "${VAULT}/vault.json" <<EOF
{
  "id": "${ID}",
  "remote": "${REMOTE}",
  "schema_version": 1
}
EOF
fi

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

## Follow-ups
- [ ]

<!-- Open items you'd otherwise forget by next week. `- [ ]` pending,
     `- [x]` done — check-follow-ups reads these, nothing else. -->

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

# The hook is the backstop: committing here is guarded regardless of whether
# a skill remembered to invoke guard-vault-commit.sh first. It calls that
# same script with no --expect-id of its own — it has nothing trustworthy to
# derive one from (git hands a pre-commit hook no useful context), so it
# relies entirely on SBW_EXPECTED_VAULT_ID / --expect-id resolving on this
# machine, same as any other invocation.
HOOK_MARKER="# second-brain-workflow: vault-commit guard"
if [ "${NO_HOOK}" -eq 0 ]; then
  hook="${VAULT}/.git/hooks/pre-commit"
  if [ -e "${hook}" ]; then
    if grep -qF "${HOOK_MARKER}" "${hook}" 2>/dev/null; then
      : # already ours — left alone, like every other write_if_absent file
    else
      echo "  pre-commit hook already exists and is not ours — left untouched." >&2
      echo "    Add the guard yourself: exec ${STANDARDS_DIR}/scripts/guard-vault-commit.sh --vault \"\$(git rev-parse --show-toplevel)\"" >&2
    fi
  else
    cat > "${hook}" <<EOF
#!/usr/bin/env bash
${HOOK_MARKER} — installed by init-vault.sh.
# Do not edit by hand; re-run init-vault.sh --adopt after an engine update.
set -euo pipefail
exec "${STANDARDS_DIR}/scripts/guard-vault-commit.sh" --vault "\$(git rev-parse --show-toplevel)"
EOF
    chmod +x "${hook}"
    note "installed pre-commit hook"
    created=$((created+1))
  fi
fi

"${STANDARDS_DIR}/scripts/build-vault-index.py" --vault "${VAULT}" >/dev/null
note "generated practices/INDEX.md"

echo
if [ "${created}" -eq 0 ]; then
  echo "Already complete — nothing to add."
else
  echo "Added ${created} item(s)."
fi
# The two things that have to agree — vault.json's id and this machine's
# SBW_EXPECTED_VAULT_ID — are both known right here, so writing them together
# is the one moment they cannot be made to disagree by hand. Without it the
# guard fails closed on the very first commit, which is where a reader
# following only the Quickstart ended up.
#
# This does not weaken the non-circular trust model. What that model forbids is
# the *guard* reading its expectation out of the vault it is checking, so a
# repointed or freshly cloned vault can't vouch for itself. The expectation
# still lives on the machine, in a file this writes once from an id a human
# passed in; nothing later re-derives it from vault.json. Automating a human
# assertion is not the same as letting the vault assert it.
#
# Only ever when the file does not exist. An existing config is the user's,
# may carry keys this knows nothing about, and on a second vault would already
# hold a different expected id — merging into that is not this script's call.
CONFIG_FILE="$(ds_config_path)"
if [ "${NO_CONFIG}" -eq 0 ] && [ ! -e "${CONFIG_FILE}" ]; then
  mkdir -p "$(dirname "${CONFIG_FILE}")"
  cat > "${CONFIG_FILE}" <<EOF
# Written by init-vault.sh. See config.example for every key.
SBW_VAULT=${VAULT}
SBW_EXPECTED_VAULT_ID=${ID}
EOF
  echo
  echo "Wrote ${CONFIG_FILE}:"
  sed 's/^/    /' "${CONFIG_FILE}"
elif [ "${NO_CONFIG}" -eq 0 ]; then
  echo
  echo "${CONFIG_FILE} already exists — left untouched."
  if ! grep -q "^[[:space:]]*SBW_EXPECTED_VAULT_ID[[:space:]]*=[[:space:]]*${ID}[[:space:]]*$" \
         "${CONFIG_FILE}" 2>/dev/null; then
    echo "It does not set SBW_EXPECTED_VAULT_ID=${ID}, so the guard will refuse"
    echo "commits into this vault until it does. Add or change that line:"
    echo "    SBW_EXPECTED_VAULT_ID=${ID}"
  fi
fi

# Always print the identity a commit here would carry, pinned or not. Seeing it
# at creation time is what would have caught a personal address on a work
# machine before the first commit rather than after the push. Deliberately not
# the heuristic the review floated — guessing which address "should" apply from
# --remote's host is cleverness that is wrong sometimes, and a wrong guess here
# is worse than stating the fact and letting the reader judge.
resolved_ident="$(git -C "${VAULT}" var GIT_AUTHOR_IDENT 2>/dev/null || true)"
resolved_email=""
if [ -n "${resolved_ident}" ]; then
  resolved_email="${resolved_ident#*<}"
  resolved_email="${resolved_email%%>*}"
fi

echo
if [ -n "${resolved_email}" ]; then
  echo "Commits in this vault would be authored as: ${resolved_email}"
else
  echo "Commits here have no resolvable author identity yet (git config user.email is unset)."
fi

if [ -n "${IDENTITY_EMAIL}" ]; then
  # Test for the address, not merely for an "identity" key: on a re-run against
  # a vault that already pins a *different* address, the file was not touched,
  # and claiming it "pins it to ${IDENTITY_EMAIL}" would report something
  # untrue about the very check being set up.
  if grep -q "\"email\"[[:space:]]*:[[:space:]]*\"${IDENTITY_EMAIL}\"" \
       "${VAULT}/vault.json" 2>/dev/null; then
    echo "vault.json pins it to ${IDENTITY_EMAIL} — the guard refuses a commit from any other address."
  else
    echo "vault.json already existed, so --identity-email was not written into it (this"
    echo "script never rewrites content it didn't write). Add it by hand to enable the check:"
    echo "    \"identity\": { \"email\": \"${IDENTITY_EMAIL}\" }"
  fi
elif ! grep -q '"identity"' "${VAULT}/vault.json" 2>/dev/null; then
  echo "No author identity is pinned, so commits are not checked against one."
  echo "To enable it, pass --identity-email, or add to vault.json:"
  echo "    \"identity\": { \"email\": \"you@example.com\" }"
fi

if [ -n "${resolved_email}" ] && [ -n "${IDENTITY_EMAIL}" ] \
   && [ "${resolved_email}" != "${IDENTITY_EMAIL}" ]; then
  echo
  echo "MISMATCH — this machine would author as ${resolved_email}, not ${IDENTITY_EMAIL}."
  echo "Fix it now, before the first commit:"
  echo "    git -C ${VAULT} config user.email '${IDENTITY_EMAIL}'"
  echo "Or machine-wide for everything under that path — see docs/NEW-MACHINE.md:"
  echo "    [includeIf \"gitdir:${VAULT}/\"]   # trailing slash required"
  echo "        path = ~/.gitconfig-work"
fi

# Step 2 depends on what actually happened above: telling someone to write a
# config line this script just wrote is a contradiction, and following it would
# be a no-op that reads like a missed step.
if grep -q "^[[:space:]]*SBW_VAULT[[:space:]]*=[[:space:]]*${VAULT}[[:space:]]*$" \
     "${CONFIG_FILE}" 2>/dev/null; then
  step2="This machine already points at it — ${CONFIG_FILE} says so."
else
  step2="Point this machine at it:
       SBW_VAULT=${VAULT}
     in ${CONFIG_FILE}"
fi

cat <<EOF

Next:
  1. Open ${VAULT} in Obsidian (enable Dataview for 00-maps/).
  2. ${step2}
  3. Create the remote yourself — **private** — then push.
  4. Capture a session: say "update second brain".

This vault ships only its own operating rules, in practices/cross-cutting/ —
update-second-brain reads those at runtime. Everything else is earned: domain
practices come from sessions that actually happened, not from a template.
EOF
