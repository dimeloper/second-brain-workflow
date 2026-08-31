#!/usr/bin/env bash
# init-vault.sh: scaffolding, the seeded operating rules, and idempotency.
# shellcheck source=tests/lib.sh
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
setup_sandbox

INIT="${ENGINE}/scripts/init-vault.sh"
V="${SANDBOX}/v"

echo "init-vault.sh"

"${INIT}" --path "${V}" --id work --remote "git@example.com:me/wb.git" >/dev/null 2>&1
assert_exit 0 $? "creates a vault"

for d in practices/app practices/backend practices/frontend practices/cross-cutting \
         _templates 00-maps bases projects; do
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ -d "${V}/${d}" ]; then pass "created ${d}/"; else fail "created ${d}/"; fi
done

assert_file "${V}/vault.json"                      "writes vault.json"
assert_file "${V}/_templates/practice-note.md"     "writes the practice template"
assert_file "${V}/_templates/daily-note.md"        "writes the daily template"

# The #repo/ tag is written by update-second-brain, but an item typed straight
# into Obsidian has only the template to learn the convention from — and an
# untagged item is the one that groups under "no repo identified" forever.
TESTS_RUN=$((TESTS_RUN + 1))
if grep -q '#repo/' "${V}/_templates/daily-note.md"; then
  pass "the daily template documents the #repo/ follow-up tag"
else
  fail "the daily template documents the #repo/ follow-up tag" \
    "$(cat "${V}/_templates/daily-note.md")"
fi

# `## Resume here` was written into a real daily note before existing in any
# template, which is how the next session that has never seen it either drops it
# or opens a second one. A section in a note and in no template is not a
# convention yet.
TESTS_RUN=$((TESTS_RUN + 1))
if grep -q 'Resume here' "${V}/_templates/daily-note.md"; then
  pass "the daily template describes the optional ## Resume here block"
else
  fail "the daily template describes the optional ## Resume here block" \
    "$(cat "${V}/_templates/daily-note.md")"
fi
assert_file "${V}/_templates/project-note.md"       "writes the project template"

# projects/ is scaffolded empty. Git does not track an empty directory, so
# without a .gitkeep a fresh clone arrives without it and the first project doc
# lands somewhere nobody could see was intended.
assert_file "${V}/projects/.gitkeep"               "projects/ survives a clone"
TESTS_RUN=$((TESTS_RUN + 1))
if [ -z "$(find "${V}/projects" -name '*.md' -print -quit)" ]; then
  pass "projects/ starts empty — a project doc is earned, not scaffolded"
else
  fail "projects/ starts empty — a project doc is earned, not scaffolded"
fi

# A project doc is neither a practice note nor a daily note, and the template is
# the only place a reader learns which. Both halves matter: the claim marker is
# what keeps a second-hand assertion from reading as verified, and the outcome
# tag is what keeps a closed question from reading as an answered one.
for want in 'TL;DR' 'Cast' 'Timeline' 'Contested points' 'Open questions' \
            'Artifacts and links' 'second-hand' 'verified' '#outcome/'; do
  assert_contains "${V}/_templates/project-note.md" "${want}" \
    "the project template carries ${want}"
done
assert_contains "${V}/_templates/project-note.md" 'never promotes' \
  "...and says plainly that it never promotes"

# The daily template is where an item typed straight into Obsidian learns the
# convention. A bare `- [x]` cannot say whether work was finished or abandoned,
# and those lead to opposite actions when the question comes back.
assert_contains "${V}/_templates/daily-note.md" '#outcome/' \
  "the daily template documents the follow-up outcome tag"

assert_file "${V}/00-maps/promotion-candidates.md" "writes the promotion query"
assert_file "${V}/practices/INDEX.md"              "generates the index"
assert_contains "${V}/vault.json" '"id": "work"'   "records the vault id"

# --- pre-commit hook installed by default ------------------------------------
assert_file "${V}/.git/hooks/pre-commit" "installs a pre-commit hook by default"
TESTS_RUN=$((TESTS_RUN + 1))
if [ -x "${V}/.git/hooks/pre-commit" ]; then pass "hook is executable"; else fail "hook is executable"; fi
assert_contains "${V}/.git/hooks/pre-commit" "second-brain-workflow: vault-commit guard" \
  "hook is recognizably ours"
assert_contains "${V}/.git/hooks/pre-commit" "guard-vault-commit.sh" \
  "hook calls the guard script"

# The four notes update-second-brain reads at runtime. Without them the capture
# workflow runs with its own instructions missing.
for n in propose-then-approve-vault-writes keep-one-header-per-section-in-daily-notes \
         promote-practices-through-maturity-stages record-declined-vault-candidates; do
  assert_file "${V}/practices/cross-cutting/${n}.md" "seeds ${n}"
done

assert_contains "${V}/practices/cross-cutting/propose-then-approve-vault-writes.md" \
  "^maturity: enforced" "seeded rules ship as enforced-by-preference"
assert_not_contains "${V}/practices/cross-cutting/propose-then-approve-vault-writes.md" \
  "{{DATE}}" "date placeholder is substituted"
assert_contains "${V}/practices/INDEX.md" "propose-then-approve" "seeded rules reach the index"

# A seeded vault must not ship dangling wikilinks — they would show up in the
# review queue's broken-link report on day one.
TESTS_RUN=$((TESTS_RUN + 1))
if python3 - "${V}" <<'PY'
import glob, os, re, sys
root = sys.argv[1]
names = {os.path.basename(p)[:-3] for p in glob.glob(f"{root}/practices/*/*.md")}
bad = [(os.path.basename(p), l)
       for p in glob.glob(f"{root}/practices/*/*.md")
       for l in re.findall(r"\[\[([^\]]+)\]\]", open(p).read())
       if l not in names]
sys.exit(1 if bad else 0)
PY
then pass "no dangling wikilinks in a fresh vault"; else fail "no dangling wikilinks in a fresh vault"; fi

# No domain practice notes — content is earned, not scaffolded.
TESTS_RUN=$((TESTS_RUN + 1))
n_domain=$(find "${V}/practices/app" "${V}/practices/backend" "${V}/practices/frontend" \
            -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
if [ "${n_domain}" -eq 0 ]; then
  pass "seeds no domain practice notes"
else
  fail "seeds no domain practice notes" "found ${n_domain}"
fi

# --- idempotency and adoption ------------------------------------------------
"${INIT}" --path "${V}" --id work --adopt >/dev/null 2>&1
assert_exit 0 $? "re-run with --adopt is safe"

out="$("${INIT}" --path "${V}" --id work --adopt 2>&1)"
TESTS_RUN=$((TESTS_RUN + 1))
if grep -q "Already complete" <<< "${out}"; then
  pass "second run adds nothing"
else
  fail "second run adds nothing" "${out}"
fi

# A hand-edited seeded rule is never overwritten.
echo "LOCAL EDIT" >> "${V}/practices/cross-cutting/propose-then-approve-vault-writes.md"
"${INIT}" --path "${V}" --id work --adopt >/dev/null 2>&1
assert_contains "${V}/practices/cross-cutting/propose-then-approve-vault-writes.md" \
  "LOCAL EDIT" "does not overwrite an edited seeded rule"

# --- adopt identity check -----------------------------------------------------
# --adopt must not silently scaffold content into someone else's (or the
# wrong) vault. A directory that already has a vault.json is treated as a
# pre-existing vault whose id (and remote, once git is involved) must agree.
OTHER="${SANDBOX}/other"
mkdir -p "${OTHER}"
cat > "${OTHER}/vault.json" <<'EOF'
{
  "id": "personal",
  "remote": "",
  "schema_version": 1
}
EOF
"${INIT}" --path "${OTHER}" --id work --adopt >/dev/null 2>&1
assert_exit 1 $? "--adopt aborts when --id disagrees with vault.json"
assert_no_file "${OTHER}/_templates/daily-note.md" "aborted adopt (id mismatch) writes nothing"

"${INIT}" --path "${OTHER}" --id personal --adopt >/dev/null 2>&1
assert_exit 0 $? "--adopt proceeds once --id matches"
assert_file "${OTHER}/_templates/daily-note.md" "matching adopt scaffolds normally"

REMOTED="${SANDBOX}/remoted"
mkdir -p "${REMOTED}"
git -C "${REMOTED}" init -q
git -C "${REMOTED}" remote add origin "git@example.com:me/actual.git"
cat > "${REMOTED}/vault.json" <<'EOF'
{
  "id": "work",
  "remote": "git@example.com:me/claimed.git",
  "schema_version": 1
}
EOF
"${INIT}" --path "${REMOTED}" --id work --adopt >/dev/null 2>&1
assert_exit 1 $? "--adopt aborts on a remote mismatch"
assert_no_file "${REMOTED}/_templates/daily-note.md" "aborted adopt (remote mismatch) writes nothing"

FRESH="${SANDBOX}/fresh"
"${INIT}" --path "${FRESH}" --id anything >/dev/null 2>&1
assert_exit 0 $? "a fresh vault (no vault.json yet) is unaffected by the identity check"

# --- pre-commit hook: actually blocks a hand-run git commit ------------------
# The point of the hook is that it works with no agent and no explicit guard
# invocation involved — just plain `git commit`.
HOOKED="${SANDBOX}/hooked"
"${INIT}" --path "${HOOKED}" --id hooked >/dev/null 2>&1
git -C "${HOOKED}" add -A >/dev/null 2>&1
SBW_EXPECTED_VAULT_ID=hooked git -C "${HOOKED}" -c user.email=t@t -c user.name=t commit -qm "init" >/dev/null 2>&1

mkdir -p "${HOOKED}/somewhere"
echo "stray" > "${HOOKED}/somewhere/file.md"
git -C "${HOOKED}" add -A >/dev/null 2>&1
SBW_EXPECTED_VAULT_ID=hooked git -C "${HOOKED}" -c user.email=t@t -c user.name=t commit -qm "bad" >/dev/null 2>&1
assert_exit 1 $? "hand-run git commit is blocked by the hook, no agent involved"
TESTS_RUN=$((TESTS_RUN + 1))
if grep -q "bad" <<< "$(git -C "${HOOKED}" log --oneline)"; then
  fail "the blocked commit did not actually land"
else
  pass "the blocked commit did not actually land"
fi

# --- pre-commit hook: idempotent across two init-vault.sh runs --------------
before_sum="$(shasum "${HOOKED}/.git/hooks/pre-commit" | awk '{print $1}')"
"${INIT}" --path "${HOOKED}" --id hooked --adopt >/dev/null 2>&1
after_sum="$(shasum "${HOOKED}/.git/hooks/pre-commit" | awk '{print $1}')"
TESTS_RUN=$((TESTS_RUN + 1))
if [ "${before_sum}" = "${after_sum}" ]; then
  pass "hook is byte-identical after a second init-vault.sh run"
else
  fail "hook is byte-identical after a second init-vault.sh run" "hook changed"
fi

# --- pre-commit hook: a foreign hook is preserved and reported --------------
FOREIGN="${SANDBOX}/foreign-hook"
mkdir -p "${FOREIGN}"
git -C "${FOREIGN}" init -q
printf '#!/bin/sh\necho "someone else was here"\n' > "${FOREIGN}/.git/hooks/pre-commit"
chmod +x "${FOREIGN}/.git/hooks/pre-commit"
out="$("${INIT}" --path "${FOREIGN}" --id foreign --adopt 2>&1)"
assert_contains "${FOREIGN}/.git/hooks/pre-commit" "someone else was here" \
  "a foreign pre-commit hook is left untouched"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"already exists and is not ours"*) pass "a foreign pre-commit hook is reported" ;;
  *) fail "a foreign pre-commit hook is reported" "${out}" ;;
esac

# --- --no-hook opts out -------------------------------------------------------
NOHOOK="${SANDBOX}/no-hook"
"${INIT}" --path "${NOHOOK}" --id nohook --no-hook >/dev/null 2>&1
assert_no_file "${NOHOOK}/.git/hooks/pre-commit" "--no-hook skips installing the hook"

# --- guardrails --------------------------------------------------------------
NE="${SANDBOX}/nonempty"
mkdir -p "${NE}"; echo x > "${NE}/thing.txt"
"${INIT}" --path "${NE}" --id other >/dev/null 2>&1
assert_exit 1 $? "refuses a non-empty directory without --adopt"

"${INIT}" --path "${SANDBOX}/bad" --id "Work Vault" >/dev/null 2>&1
assert_exit 2 $? "rejects an id that is not a slug"

# --- an unedited placeholder stops the run ----------------------------------
# The Quickstart's prose warning was correct and three lines below the block,
# and the block still got pasted unedited: YOUR_ACCOUNT looked unfinished and
# was replaced, `vault_id=personal` looked finished and was kept. So the value
# is a placeholder now, and the script refuses it rather than producing a vault
# whose id is wrong and has to be undone.
for bad_id in VAULT_ID vault_id YOUR_ACCOUNT VAULT_NAME; do
  out="$("${INIT}" --path "${SANDBOX}/ph-${bad_id}" --id "${bad_id}" --no-hook 2>&1)"
  rc=0
  "${INIT}" --path "${SANDBOX}/ph2-${bad_id}" --id "${bad_id}" --no-hook >/dev/null 2>&1 || rc=$?
  assert_exit 2 "${rc}" "refuses the unedited placeholder --id ${bad_id}"
  assert_no_file "${SANDBOX}/ph-${bad_id}/vault.json" "and creates nothing for ${bad_id}"
  TESTS_RUN=$((TESTS_RUN + 1))
  case "${out}" in
    *"two-line block in the Quickstart"*"vault_id=VAULT_ID"*)
      pass "and names the block to edit for ${bad_id}" ;;
    *) fail "and names the block to edit for ${bad_id}" "${out}" ;;
  esac
done

rc=0
"${INIT}" --path "${SANDBOX}/empty-id" --id "" --no-hook >/dev/null 2>&1 || rc=$?
assert_exit 2 "${rc}" "refuses an empty --id"

rc=0
"${INIT}" --path "${SANDBOX}/ph-path" --id work --no-hook >/dev/null 2>&1 || rc=$?
assert_exit 0 "${rc}" "a real id is unaffected"

rc=0
"${INIT}" --path "${SANDBOX}/vaults/VAULT_NAME" --id work --no-hook >/dev/null 2>&1 || rc=$?
assert_exit 2 "${rc}" "refuses a --path still holding a placeholder"

# `--id --no-hook` used to take the next flag as the value, and "--no-hook"
# passes the slug rule — lowercase letters and hyphens — so it created a vault
# genuinely called that.
rc=0
"${INIT}" --path "${SANDBOX}/flagid" --id --no-hook >/dev/null 2>&1 || rc=$?
assert_exit 2 "${rc}" "refuses an --id that is actually the next flag"
assert_no_file "${SANDBOX}/flagid/vault.json" "and creates no vault named after a flag"

"${INIT}" --path "${SANDBOX}/noid" >/dev/null 2>&1
assert_exit 2 $? "requires --id"

# --- a remote another vault already claims ----------------------------------
# Following the Quickstart on a machine that already had a work vault created a
# second vault pointing at the first one's remote, silently. Two vaults, one
# remote, is how one vault's notes end up pushed over another's.
CLAIM="${SANDBOX}/claim"
mkdir -p "${CLAIM}"
CFG="${CLAIM}/config"
FIRST="${CLAIM}/work-brain"
SBW_CONFIG_FILE="${CFG}" "${INIT}" --path "${FIRST}" --id work \
  --remote "https://github.com/ORG/work-brain.git" --no-hook >/dev/null 2>&1
assert_contains "${CFG}" "SBW_VAULT=${FIRST}" "the first vault is what the machine config points at"

out="$(SBW_CONFIG_FILE="${CFG}" "${INIT}" --path "${CLAIM}/second-brain" --id personal \
       --remote "https://github.com/ORG/work-brain" --no-hook 2>&1)"
rc=0
SBW_CONFIG_FILE="${CFG}" "${INIT}" --path "${CLAIM}/second-brain2" --id personal \
  --remote "https://github.com/ORG/work-brain" --no-hook >/dev/null 2>&1 || rc=$?
assert_exit 1 "${rc}" "refuses a --remote the configured vault already claims"
assert_no_file "${CLAIM}/second-brain/vault.json" "and creates nothing when it refuses"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"already claimed by the vault 'work' at ${FIRST}"*)
    pass "and names the conflicting vault and where it is" ;;
  *) fail "and names the conflicting vault and where it is" "${out}" ;;
esac

# The two spellings that produced the real case differ only by ".git", so a
# string comparison would have missed it. So would the ssh form of the same
# repository.
rc=0
SBW_CONFIG_FILE="${CFG}" "${INIT}" --path "${CLAIM}/ssh-form" --id personal \
  --remote "git@github.com:ORG/work-brain.git" --no-hook >/dev/null 2>&1 || rc=$?
assert_exit 1 "${rc}" "and catches the same repository written as an ssh remote"

# A genuinely different remote is not a conflict, and says nothing.
out="$(SBW_CONFIG_FILE="${CFG}" "${INIT}" --path "${CLAIM}/personal-brain" --id personal \
       --remote "https://github.com/ORG/personal-brain.git" --no-hook 2>&1)"
assert_file "${CLAIM}/personal-brain/vault.json" "a different remote creates normally"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"already claimed"*) fail "and says nothing about claims" "${out}" ;;
  *) pass "and says nothing about claims" ;;
esac

# --adopt against the vault that records the remote is the correct path, not a
# conflict — refusing it would break the case this is meant to steer people to.
rc=0
SBW_CONFIG_FILE="${CFG}" "${INIT}" --path "${FIRST}" --id work \
  --remote "https://github.com/ORG/work-brain.git" --adopt --no-hook >/dev/null 2>&1 || rc=$?
assert_exit 0 "${rc}" "--adopt against the claiming vault itself is not a conflict"

# --- id that contradicts the remote's name ----------------------------------
# A warning, not a refusal: "brain" or "notes" are legitimate names for a vault
# called anything. But `vault_id=personal` kept from the Quickstart next to a
# work remote is the mistake this catches.
out="$(SBW_CONFIG_FILE="${CFG}" "${INIT}" --path "${CLAIM}/mismatch" --id personal \
       --remote "https://github.com/ORG/team-notes.git" --no-hook 2>&1)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"warning"*"'personal' does not appear in the remote's name 'team-notes'"*)
    pass "warns when the id does not appear in the remote's name" ;;
  *) fail "warns when the id does not appear in the remote's name" "${out}" ;;
esac
assert_file "${CLAIM}/mismatch/vault.json" "but still creates the vault — it is a warning"

# --- the recorded remote has one form --------------------------------------
# Two manifests recording the same repository as ".../work-brain" and
# ".../work-brain.git" is what made the duplicate above invisible to anything
# comparing strings. What is passed varies; what is written down should not.
CANON="${SANDBOX}/canon"
mkdir -p "${CANON}"
SBW_CONFIG_FILE="${CANON}/cfg" "${INIT}" --path "${CANON}/a" --id a \
  --remote "https://github.com/ORG/a.git" --no-hook --no-config >/dev/null 2>&1
SBW_CONFIG_FILE="${CANON}/cfg" "${INIT}" --path "${CANON}/b" --id b \
  --remote "https://github.com/ORG/b/" --no-hook --no-config >/dev/null 2>&1
assert_contains "${CANON}/a/vault.json" '"remote": "https://github.com/ORG/a"' \
  "a trailing .git is not recorded"
assert_contains "${CANON}/b/vault.json" '"remote": "https://github.com/ORG/b"' \
  "nor is a trailing slash"

# Transport is left exactly as given: it is still a clone URL, and the
# comparison no longer cares which spelling it is.
SBW_CONFIG_FILE="${CANON}/cfg" "${INIT}" --path "${CANON}/c" --id c \
  --remote "git@github.com:ORG/c.git" --no-hook --no-config >/dev/null 2>&1
assert_contains "${CANON}/c/vault.json" '"remote": "git@github.com:ORG/c"' \
  "the ssh form stays the ssh form"

# The recorded form and the origin it sets must agree, or the vault fails its
# own identity check on the first commit — the reason this could not ship
# before the comparison normalised.
TESTS_RUN=$((TESTS_RUN + 1))
if [ "$(git -C "${CANON}/c" remote get-url origin)" = "git@github.com:ORG/c" ]; then
  pass "and origin is set to the same string that was recorded"
else
  fail "and origin is set to the same string that was recorded" \
    "$(git -C "${CANON}/c" remote get-url origin)"
fi

# The case the recording change actually depends on, and the one it would have
# broken on its own: a vault cloned first, so origin already exists and keeps
# the ".git" git put there, then adopted. vault.json records the stripped form
# against an origin that doesn't — which only passes because the comparison
# stopped being literal.
# shellcheck source=scripts/lib/vault-identity.sh
. "${ENGINE}/scripts/lib/vault-identity.sh"
CLONED="${CANON}/cloned"
mkdir -p "${CLONED}"
git -C "${CLONED}" init -q
git -C "${CLONED}" remote add origin "https://github.com/ORG/cloned.git"
SBW_CONFIG_FILE="${CANON}/cfg" "${INIT}" --path "${CLONED}" --id cloned \
  --remote "https://github.com/ORG/cloned.git" --adopt --no-hook --no-config >/dev/null 2>&1
assert_contains "${CLONED}/vault.json" '"remote": "https://github.com/ORG/cloned"' \
  "an adopted clone records the canonical form"
rc=0
vault_identity_check "${CLONED}" "cloned" || rc=$?
assert_exit 0 "${rc}" "and still passes its own identity check against the origin git wrote"

finish
