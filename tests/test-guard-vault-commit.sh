#!/usr/bin/env bash
# guard-vault-commit.sh: the checks that stop a vault write going to the wrong
# place, or carrying something it shouldn't.
# shellcheck source=tests/lib.sh
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
setup_sandbox

GUARD="${ENGINE}/scripts/guard-vault-commit.sh"
INIT="${ENGINE}/scripts/init-vault.sh"
VAULT="${SANDBOX}/vault"

# --no-hook: this file tests guard-vault-commit.sh directly via explicit
# invocations below. The hook itself (installed by default) is covered in
# test-init-vault.sh and test-doctor.sh — without --no-hook here, the raw
# `git commit` calls in this file's own fixture setup would themselves be
# intercepted by the hook and fail closed, for a reason unrelated to whatever
# each test below is actually checking.
"${INIT}" --path "${VAULT}" --id work --remote "git@example.com:me/work-brain.git" --no-hook >/dev/null 2>&1
git -C "${VAULT}" add -A >/dev/null 2>&1
git -C "${VAULT}" -c user.email=t@t -c user.name=t commit -qm "init" >/dev/null 2>&1

echo "guard-vault-commit.sh"

# --- nothing staged ---------------------------------------------------------
"${GUARD}" --vault "${VAULT}" >/dev/null 2>&1
assert_exit 0 $? "passes with nothing staged"

# The message has to name which half was skipped. "nothing to check" was
# accurate about the diff and wrong about the commit, and reading it is what
# made `git commit --allow-empty` past the author check look like correct
# behaviour rather than the bypass it was.
out="$("${GUARD}" --vault "${VAULT}" 2>&1)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"no diff to check, but the commit author was"*)
    pass "and says what was still checked, rather than \"nothing to check\"" ;;
  *) fail "and says what was still checked, rather than \"nothing to check\"" "${out}" ;;
esac

# --- a normal note edit -----------------------------------------------------
cat > "${VAULT}/practices/backend/a-practice.md" <<'EOF'
---
domain: backend
applies-to: ""
maturity: idea
last-reviewed: 2026-08-02
repos: ["fixture"]
tags: [x]
---

# A practice

**Rule:** Something reusable.
EOF
printf '# 2026-08-02\n\n## Built\n- work\n' > "${VAULT}/2026-08-02.md"
git -C "${VAULT}" add -A >/dev/null 2>&1
"${GUARD}" --vault "${VAULT}" --expect-id work >/dev/null 2>&1
assert_exit 0 $? "passes a normal note + daily note"

# --- vault identity ---------------------------------------------------------
"${GUARD}" --vault "${VAULT}" --expect-id work >/dev/null 2>&1
assert_exit 0 $? "passes when the expected id matches"

"${GUARD}" --vault "${VAULT}" --expect-id personal >/dev/null 2>&1
assert_exit 1 $? "blocks a write aimed at a different vault id"

git -C "${VAULT}" remote set-url origin "git@example.com:me/personal-brain.git"
"${GUARD}" --vault "${VAULT}" --expect-id work >/dev/null 2>&1
assert_exit 1 $? "blocks a repointed remote"
git -C "${VAULT}" remote set-url origin "git@example.com:me/work-brain.git"
"${GUARD}" --vault "${VAULT}" --expect-id work >/dev/null 2>&1
assert_exit 0 $? "passes again once the remote matches"

# --- SBW_EXPECTED_VAULT_ID: machine config as the source of the expectation -
# The expected id must come from the machine, not from vault.json itself —
# otherwise a repointed or freshly cloned vault would bring its own "correct"
# answer along with it. Precedence: --expect-id flag > env > config file.
SBW_EXPECTED_VAULT_ID=work "${GUARD}" --vault "${VAULT}" >/dev/null 2>&1
assert_exit 0 $? "SBW_EXPECTED_VAULT_ID alone (no flag) resolves the expectation"

SBW_EXPECTED_VAULT_ID=personal "${GUARD}" --vault "${VAULT}" >/dev/null 2>&1
assert_exit 1 $? "blocks when SBW_EXPECTED_VAULT_ID disagrees with vault.json"

SBW_EXPECTED_VAULT_ID=personal "${GUARD}" --vault "${VAULT}" --expect-id work >/dev/null 2>&1
assert_exit 0 $? "--expect-id flag takes precedence over SBW_EXPECTED_VAULT_ID"

# --- fails closed with no configuration at all ------------------------------
# The circularity this closes: without this, an unconfigured machine's guard
# only checked that vault.json HAD an id, never that it was the RIGHT one —
# so a wrong vault.json would pass simply by being internally consistent.
#
# init-vault.sh now writes a machine config when none exists, and this suite
# creates its vault with it — so the config it wrote has to go before
# "unconfigured" means anything here. Deleting it is the point of the case: the
# state under test is a machine with no expected id at all, which is still
# reachable (--no-config, a deleted config, a bare CI runner).
rm -f "${SBW_CONFIG_FILE}"
unset SBW_EXPECTED_VAULT_ID
out="$("${GUARD}" --vault "${VAULT}" 2>&1)"
rc=$?
assert_exit 1 "${rc}" "fails closed when no expect-id is configured at all"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"no expected vault id configured"*) pass "names the missing configuration" ;;
  *) fail "names the missing configuration" "${out}" ;;
esac

# --- path allowlist ---------------------------------------------------------
mkdir -p "${VAULT}/somewhere"
echo "stray" > "${VAULT}/somewhere/file.md"
git -C "${VAULT}" add -A >/dev/null 2>&1
"${GUARD}" --vault "${VAULT}" >/dev/null 2>&1
assert_exit 1 $? "blocks a staged path outside the allowed set"
git -C "${VAULT}" rm -q --cached "somewhere/file.md" >/dev/null 2>&1
rm -rf "${VAULT}/somewhere"

# --- projects/*: allowed (per-initiative context docs) ---------------------
# The one artefact most worth carrying across sessions was the one the guard
# refused to carry: a project doc at projects/<initiative>.md stayed permanently
# untracked, invisible to every other machine. Left staged for the same reason
# the workflow file below is.
mkdir -p "${VAULT}/projects"
printf -- '---\nkind: project\nstatus: active\n---\n\n# An initiative\n\n## TL;DR\n- where it is now\n' \
  > "${VAULT}/projects/an-initiative.md"
git -C "${VAULT}" add -A >/dev/null 2>&1
"${GUARD}" --vault "${VAULT}" --expect-id work >/dev/null 2>&1
assert_exit 0 $? "allows a projects/ context document"

# Revised in place, not append-only. The daily-note check must not reach it: a
# project doc exists precisely so a superseded sentence can be corrected rather
# than appended to, and holding it append-only would refuse its normal use.
git -C "${VAULT}" -c user.email=t@t -c user.name=t commit -qm "projects" \
  -- projects >/dev/null 2>&1
printf -- '---\nkind: project\nstatus: active\n---\n\n# An initiative\n\n## TL;DR\n- somewhere else entirely\n' \
  > "${VAULT}/projects/an-initiative.md"
git -C "${VAULT}" add projects >/dev/null 2>&1
"${GUARD}" --vault "${VAULT}" --expect-id work >/dev/null 2>&1
assert_exit 0 $? "a project doc may lose a line — it is revised, not appended to"
git -C "${VAULT}" -c user.email=t@t -c user.name=t commit -qm "revise" \
  -- projects >/dev/null 2>&1

# A project is a directory, so the allowlist has to admit both levels below it.
# `*` in a case pattern spans `/`, which is what makes one pattern enough — and
# is exactly the kind of thing a later tightening to `projects/[!/]*` would
# break silently, making every feature file uncommittable.
mkdir -p "${VAULT}/projects/an-initiative/features"
printf -- '---\nkind: project\nstatus: active\n---\n\n# An initiative\n\n## TL;DR\n- the stable half\n' \
  > "${VAULT}/projects/an-initiative/_project.md"
printf -- '---\nkind: feature\nstatus: active\n---\n\n# A slice\n\n## State\n- in progress\n' \
  > "${VAULT}/projects/an-initiative/features/a-slice.md"
git -C "${VAULT}" add -A >/dev/null 2>&1
"${GUARD}" --vault "${VAULT}" --expect-id work >/dev/null 2>&1
assert_exit 0 $? "allows projects/<project>/_project.md and features/<feature>.md"
git -C "${VAULT}" -c user.email=t@t -c user.name=t commit -qm "project dir" \
  -- projects >/dev/null 2>&1

# A feature file is revised in place too — it is the living half of the pair, so
# the daily-note append-only check must not reach it either.
printf -- '---\nkind: feature\nstatus: closed\noutcome: done\n---\n\n# A slice\n\n## State\n- shipped\n' \
  > "${VAULT}/projects/an-initiative/features/a-slice.md"
git -C "${VAULT}" add projects >/dev/null 2>&1
"${GUARD}" --vault "${VAULT}" --expect-id work >/dev/null 2>&1
assert_exit 0 $? "a feature file may lose a line — it is revised, not appended to"
git -C "${VAULT}" -c user.email=t@t -c user.name=t commit -qm "close the slice" \
  -- projects >/dev/null 2>&1

# --- .github/workflows/*.yml: allowed (docs/vault-ci templates) ------------
# Left staged, not committed here — the next block's "notes" commit already
# finalizes whatever's staged at that point, and committing early would eat
# the still-staged note/daily-note content the size-cap tests below depend
# on being present.
mkdir -p "${VAULT}/.github/workflows"
printf 'on: push\njobs: {}\n' > "${VAULT}/.github/workflows/guard.yml"
git -C "${VAULT}" add -A >/dev/null 2>&1
"${GUARD}" --vault "${VAULT}" --expect-id work >/dev/null 2>&1
assert_exit 0 $? "allows a .github/workflows/*.yml file"

# --- size caps --------------------------------------------------------------
# Every invocation from here down passes --expect-id. Without it the guard exits
# 1 at the identity check, several steps before any of these rules run — so each
# `assert_exit 1` below was satisfied by the wrong refusal, and the size caps,
# the credential scan, the conflict-marker scan and the enforced-note rule were
# all untested. That is how a credential scan that failed open survived: nothing
# here ever reached it.
ID=(--expect-id work)

GUARD_MAX_LINES=2 "${GUARD}" --vault "${VAULT}" "${ID[@]}" >/dev/null 2>&1
assert_exit 1 $? "blocks an oversized diff by line count"
GUARD_MAX_FILES=1 "${GUARD}" --vault "${VAULT}" "${ID[@]}" >/dev/null 2>&1
assert_exit 1 $? "blocks an oversized diff by file count"

# --- credentials and conflict markers ---------------------------------------
git -C "${VAULT}" -c user.email=t@t -c user.name=t commit -qm "notes" >/dev/null 2>&1
printf 'token: ghp_%s\n' "0123456789abcdefghij0123456789abcdef" >> "${VAULT}/2026-08-02.md"
git -C "${VAULT}" add -A >/dev/null 2>&1
"${GUARD}" --vault "${VAULT}" "${ID[@]}" >/dev/null 2>&1
assert_exit 1 $? "blocks a staged credential"
git -C "${VAULT}" checkout -- "2026-08-02.md" 2>/dev/null || git -C "${VAULT}" reset -q --hard HEAD

# The same credential, but *early* in a *large* diff — the case that failed
# open. `printf "$body" | grep -q` exits grep on the first match, SIGPIPEs the
# printf still writing the rest, and `pipefail` turns that into 141: a match
# reported as a miss, so the commit was allowed. The test above never caught it
# because appending one line to a small file puts the match at the very end,
# where the producer has already finished. Caps are raised for this one call so
# the guard is exercised on the credential check rather than blocking earlier on
# size, which would pass this assertion for the wrong reason.
{
  printf 'token: ghp_%s\n' "0123456789abcdefghij0123456789abcdef"
  i=0
  while [ "${i}" -lt 60000 ]; do
    printf 'filler line %s to push the diff well past any pipe buffer\n' "${i}"
    i=$((i + 1))
  done
} >> "${VAULT}/2026-08-02.md"
git -C "${VAULT}" add -A >/dev/null 2>&1
big_out="$(GUARD_MAX_LINES=100000 GUARD_MAX_FILES=50 "${GUARD}" --vault "${VAULT}" "${ID[@]}" 2>&1)"
big_rc=$?
assert_exit 1 "${big_rc}" "blocks a credential early in a large diff — the fail-open case"
# On the message, not just the exit code: a size cap or any other rule would
# also exit 1, and an assertion that cannot tell those apart would have passed
# against the buggy guard too. It did, which is how this line came to exist.
TESTS_RUN=$((TESTS_RUN + 1))
case "${big_out}" in
  *credential*) pass "and blocks it *as* a credential, not for some other reason" ;;
  *) fail "and blocks it *as* a credential, not for some other reason" "${big_out}" ;;
esac
git -C "${VAULT}" reset -q --hard HEAD

printf '<<<<<<< HEAD\nmine\n=======\ntheirs\n>>>>>>> other\n' >> "${VAULT}/2026-08-02.md"
git -C "${VAULT}" add -A >/dev/null 2>&1
"${GUARD}" --vault "${VAULT}" "${ID[@]}" >/dev/null 2>&1
assert_exit 1 $? "blocks conflict markers"
git -C "${VAULT}" reset -q --hard HEAD

# --- deleting an enforced note ----------------------------------------------
cat > "${VAULT}/practices/backend/enforced-note.md" <<'EOF'
---
domain: backend
applies-to: "**/*.ts"
maturity: enforced
last-reviewed: 2026-08-02
repos: ["a", "b", "c"]
tags: [x]
---

# An enforced note

**Rule:** Load-bearing.
EOF
git -C "${VAULT}" add -A >/dev/null 2>&1
git -C "${VAULT}" -c user.email=t@t -c user.name=t commit -qm "enforced" >/dev/null 2>&1
git -C "${VAULT}" rm -q "practices/backend/enforced-note.md" >/dev/null 2>&1
"${GUARD}" --vault "${VAULT}" >/dev/null 2>&1
assert_exit 1 $? "blocks deleting an enforced note"
git -C "${VAULT}" reset -q --hard HEAD

# --- a daily note only ever grows -------------------------------------------
# The lost-update case. Two sessions wrapping up at once both read today's
# note, both write the whole file back, and the second write drops the first
# one's block — with a clean tree afterwards and nothing else to notice it by.
# Real, twice in one evening, on 2026-08-24.
DAILY="${VAULT}/2026-08-24.md"
cat > "${DAILY}" <<'EOF'
# 2026-08-24

## Built (echo-city-hotel: Open Graph share card)
- Shipped `dede9b0`.
- og:image is absolute now.

## Follow-ups
- [ ] Scrape the Facebook debugger #repo/echo-city-hotel
EOF
git -C "${VAULT}" add -A >/dev/null 2>&1
git -C "${VAULT}" -c user.email=t@t -c user.name=t commit -qm "daily" >/dev/null 2>&1

cat >> "${DAILY}" <<'EOF'

## Drift / gaps
- A 200 on the asset is not proof the share URL is crawlable.
EOF
git -C "${VAULT}" add -A >/dev/null 2>&1
"${GUARD}" --vault "${VAULT}" --expect-id work >/dev/null 2>&1
assert_exit 0 $? "appending to a daily note passes"
git -C "${VAULT}" reset -q --hard HEAD

# A ticked box is the same item, not a lost one.
sed 's/- \[ \] Scrape/- [x] Scrape/' "${DAILY}" > "${DAILY}.tmp" && mv "${DAILY}.tmp" "${DAILY}"
git -C "${VAULT}" add -A >/dev/null 2>&1
"${GUARD}" --vault "${VAULT}" --expect-id work >/dev/null 2>&1
assert_exit 0 $? "ticking a follow-up's checkbox passes"
git -C "${VAULT}" reset -q --hard HEAD

# An edited line keeps its opening clause. Matching on literal characters
# failed exactly this case — the difference is at the full stop, 19 in.
cat > "${DAILY}" <<'EOF'
# 2026-08-24

## Built (echo-city-hotel: Open Graph share card)
- Shipped `dede9b0` to production.
- og:image is absolute now.

## Follow-ups
- [ ] Scrape the Facebook debugger #repo/echo-city-hotel
EOF
git -C "${VAULT}" add -A >/dev/null 2>&1
"${GUARD}" --vault "${VAULT}" --expect-id work >/dev/null 2>&1
assert_exit 0 $? "rewording a bullet passes"
git -C "${VAULT}" reset -q --hard HEAD

# The whole-file write from a stale read: one session's block replaced by
# another's.
cat > "${DAILY}" <<'EOF'
# 2026-08-24

## Built (housemaster-ingestion: Places cost)
- PR #41 caps a run at 150 requests.
EOF
git -C "${VAULT}" add -A >/dev/null 2>&1
out="$("${GUARD}" --vault "${VAULT}" --expect-id work 2>&1)"
rc=$?
assert_exit 1 "${rc}" "blocks a daily note whose earlier block was overwritten"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"vanished from 2026-08-24.md"*"Scrape the Facebook debugger"*)
    pass "and names the lines that vanished" ;;
  *) fail "and names the lines that vanished" "${out}" ;;
esac

# Both doors out, for the one deliberate case: moving work into the note for
# the day it actually happened.
"${GUARD}" --vault "${VAULT}" --expect-id work --allow-daily-rewrite >/dev/null 2>&1
assert_exit 0 $? "--allow-daily-rewrite permits it"
GUARD_ALLOW_DAILY_REWRITE=1 "${GUARD}" --vault "${VAULT}" --expect-id work >/dev/null 2>&1
assert_exit 0 $? "GUARD_ALLOW_DAILY_REWRITE=1 permits it too"

# A practice note is edited in place constantly — frontmatter bumps, a
# rewritten Rule, an applications entry. Holding those to append-only would
# make this the check everyone routes around.
git -C "${VAULT}" reset -q --hard HEAD
sed 's/^maturity: idea/maturity: trialing/' "${VAULT}/practices/backend/a-practice.md" \
  > "${VAULT}/practices/backend/a-practice.md.tmp" \
  && mv "${VAULT}/practices/backend/a-practice.md.tmp" "${VAULT}/practices/backend/a-practice.md"
git -C "${VAULT}" add -A >/dev/null 2>&1
"${GUARD}" --vault "${VAULT}" --expect-id work >/dev/null 2>&1
assert_exit 0 $? "rewriting a line in a practice note is not held to append-only"
git -C "${VAULT}" reset -q --hard HEAD

# --- missing vault.json warns but does not block ----------------------------
rm -f "${VAULT}/vault.json"
git -C "${VAULT}" add -A >/dev/null 2>&1
printf '\n- another bullet\n' >> "${VAULT}/2026-08-02.md"
git -C "${VAULT}" add -A >/dev/null 2>&1
out="$("${GUARD}" --vault "${VAULT}" 2>&1)"
rc=$?
assert_exit 0 "${rc}" "missing vault.json does not block"
TESTS_RUN=$((TESTS_RUN + 1))
if grep -q "identity unchecked" <<< "${out}"; then
  pass "missing vault.json is reported"
else
  fail "missing vault.json is reported" "${out}"
fi

# --- --range/--rev: same checks, no staging area ----------------------------
# A separate, fresh vault: the tests above interleave staged/committed state
# in ways that don't map cleanly onto "diff this commit against that one," so
# this fixture builds its own linear commit history instead.
RVAULT="${SANDBOX}/range-vault"
"${INIT}" --path "${RVAULT}" --id work --remote "git@example.com:me/work-brain.git" --no-hook >/dev/null 2>&1
git -C "${RVAULT}" add -A >/dev/null 2>&1
git -C "${RVAULT}" -c user.email=t@t -c user.name=t commit -qm "init" >/dev/null 2>&1
C0="$(git -C "${RVAULT}" rev-parse HEAD)"

commit_in() {
  git -C "${RVAULT}" add -A >/dev/null 2>&1
  git -C "${RVAULT}" -c user.email=t@t -c user.name=t commit -qm "$1" >/dev/null 2>&1
  git -C "${RVAULT}" rev-parse HEAD
}

# A normal, allowed note — should pass both --range and --rev.
cat > "${RVAULT}/practices/backend/a-practice.md" <<'EOF'
---
domain: backend
applies-to: ""
maturity: idea
last-reviewed: 2026-08-02
repos: ["fixture"]
tags: [x]
---

# A practice

**Rule:** Something reusable.
EOF
C1="$(commit_in "a note")"

"${GUARD}" --vault "${RVAULT}" --expect-id work --range "${C0}..${C1}" >/dev/null 2>&1
assert_exit 0 $? "--range passes a normal note commit"
"${GUARD}" --vault "${RVAULT}" --expect-id work --rev "${C1}" >/dev/null 2>&1
assert_exit 0 $? "--rev passes a normal note commit"

# A commit with a path outside the allowlist.
mkdir -p "${RVAULT}/somewhere"
echo "stray" > "${RVAULT}/somewhere/file.md"
C2="$(commit_in "stray file")"

out="$("${GUARD}" --vault "${RVAULT}" --expect-id work --range "${C1}..${C2}" 2>&1)"
rc=$?
assert_exit 1 "${rc}" "--range blocks a path outside the allowed set"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"path outside the vault's allowed set"*"somewhere/file.md"*) pass "--range names the offending path" ;;
  *) fail "--range names the offending path" "${out}" ;;
esac
"${GUARD}" --vault "${RVAULT}" --expect-id work --rev "${C2}" >/dev/null 2>&1
assert_exit 1 $? "--rev blocks the same commit checked on its own"

# Undo the stray file so later range/rev tests aren't tripped by it.
git -C "${RVAULT}" rm -rq "somewhere" >/dev/null 2>&1
commit_in "remove stray file" >/dev/null

# Deleting an enforced note, checked as a range and as a single rev — PRE_REF
# must resolve to the commit *before* the deletion (the range's BASE / the
# rev's parent), not to the tip, or the note's own last content would never
# be seen as "was enforced."
cat > "${RVAULT}/practices/backend/enforced-note.md" <<'EOF'
---
domain: backend
applies-to: "**/*.ts"
maturity: enforced
last-reviewed: 2026-08-02
repos: ["a", "b", "c"]
tags: [x]
---

# An enforced note

**Rule:** Load-bearing.
EOF
C3="$(commit_in "add enforced note")"
git -C "${RVAULT}" rm -q "practices/backend/enforced-note.md" >/dev/null 2>&1
C4="$(commit_in "delete enforced note")"

out="$("${GUARD}" --vault "${RVAULT}" --expect-id work --range "${C3}..${C4}" 2>&1)"
rc=$?
assert_exit 1 "${rc}" "--range blocks deleting an enforced note"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"deleting an enforced practice note"*) pass "--range names the deleted enforced note" ;;
  *) fail "--range names the deleted enforced note" "${out}" ;;
esac
"${GUARD}" --vault "${RVAULT}" --expect-id work --rev "${C4}" >/dev/null 2>&1
assert_exit 1 $? "--rev blocks the same single-commit deletion"

# --- --range/--rev: a daily note whose content vanished ---------------------
# The tier that a --no-verify past the local hook leaves to catch. CI has no
# command line to pass --allow-daily-rewrite on, so the deliberate case is
# expressed as a commit trailer instead — and a change meaning to use it needs
# both, or the local run allows what CI then refuses.
cat > "${RVAULT}/2026-08-24.md" <<'EOF'
# 2026-08-24

## Built (echo-city-hotel: Open Graph share card)
- Shipped `dede9b0`.
- og:image is absolute now.
EOF
C5="$(commit_in "daily note")"
cat > "${RVAULT}/2026-08-24.md" <<'EOF'
# 2026-08-24

## Built (housemaster-ingestion: Places cost)
- PR #41 caps a run at 150 requests.
EOF
C6="$(commit_in "clobber the daily note")"

"${GUARD}" --vault "${RVAULT}" --expect-id work --range "${C5}..${C6}" >/dev/null 2>&1
assert_exit 1 $? "--range blocks a clobbered daily note"
"${GUARD}" --vault "${RVAULT}" --expect-id work --rev "${C6}" >/dev/null 2>&1
assert_exit 1 $? "--rev blocks the same single commit"

git -C "${RVAULT}" add -A >/dev/null 2>&1
git -C "${RVAULT}" -c user.email=t@t -c user.name=t commit -q --allow-empty \
  -m "docs: move a block to the day it happened

Daily-rewrite: the echo block belonged on 2026-08-23" >/dev/null 2>&1
C7="$(git -C "${RVAULT}" rev-parse HEAD)"
"${GUARD}" --vault "${RVAULT}" --expect-id work --range "${C5}..${C7}" >/dev/null 2>&1
assert_exit 0 $? "a Daily-rewrite: trailer in the range permits it"

# --- --range/--rev: argument handling ---------------------------------------
"${GUARD}" --vault "${RVAULT}" --range "${C0}" --rev "${C1}" >/dev/null 2>&1
assert_exit 1 $? "--range and --rev together is rejected"

out="$("${GUARD}" --vault "${RVAULT}" --range "not-a-range" 2>&1)"
rc=$?
assert_exit 1 "${rc}" "a --range with no '..' is rejected"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"--range needs BASE..HEAD"*) pass "names the malformed --range value" ;;
  *) fail "names the malformed --range value" "${out}" ;;
esac

out="$("${GUARD}" --vault "${RVAULT}" --range "${C0}..not-a-real-rev" 2>&1)"
rc=$?
assert_exit 1 "${rc}" "a --range with an unresolvable rev is rejected"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"not a commit or tree in"*"not-a-real-rev"*) pass "names the unresolvable rev" ;;
  *) fail "names the unresolvable rev" "${out}" ;;
esac

# The empty tree as BASE — a vault repo's first push, where there is no
# prior commit at all (see docs/vault-ci/guard.yml's handling of
# github.event.before == the all-zero SHA).
EMPTY_TREE="$(git -C "${RVAULT}" hash-object -t tree /dev/null)"
"${GUARD}" --vault "${RVAULT}" --expect-id work --range "${EMPTY_TREE}..${C1}" >/dev/null 2>&1
assert_exit 0 $? "the empty tree works as BASE for a first-push range"

out="$("${GUARD}" --vault "${RVAULT}" --expect-id work --range "${C0}..${C0}" 2>&1)"
rc=$?
assert_exit 0 "${rc}" "--range with no actual changes exits 0"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"no changes in"*) pass "names it as no changes in range, not nothing staged" ;;
  *) fail "names it as no changes in range, not nothing staged" "${out}" ;;
esac

finish
