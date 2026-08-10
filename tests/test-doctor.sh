#!/usr/bin/env bash
# doctor.sh: reports gaps that nothing else surfaces on its own. Item 2 covers
# only the pre-commit-hook check; Item 6 extends this same script with
# check_skills().
# shellcheck source=tests/lib.sh
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
setup_sandbox
# doctor reports our links found outside SKILLS_DIRS, and resolves that set
# from the built-in default — which without this is the developer's own.
isolate_home

INIT="${ENGINE}/scripts/init-vault.sh"
DOCTOR="${ENGINE}/scripts/doctor.sh"

# check_skills() reads SKILLS_DIRS, which — like every other config key —
# falls back to the real ~/.cursor/skills:~/.claude/skills when unset. Every
# call below must set it explicitly, or this file would silently scan the
# real machine instead of fixtures. Two always-empty sandbox dirs by
# default; tests that actually exercise check_skills() override this.
EMPTY1="${SANDBOX}/skills-empty-1"
EMPTY2="${SANDBOX}/skills-empty-2"
mkdir -p "${EMPTY1}" "${EMPTY2}"
export SKILLS_DIRS="${EMPTY1}:${EMPTY2}"

echo "doctor.sh"

# --- a freshly init'd vault: hook present, all clear ------------------------
V="${SANDBOX}/v"
"${INIT}" --path "${V}" --id work --remote "git@example.com:me/wb.git" >/dev/null 2>&1
out="$("${DOCTOR}" --vault "${V}" 2>&1)"
assert_exit 0 $? "exits 0 when the hook is installed"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"commit guard installed as a pre-commit hook"*) pass "reports the hook as installed" ;;
  *) fail "reports the hook as installed" "${out}" ;;
esac

# --- a vault with no hook at all --------------------------------------------
rm -f "${V}/.git/hooks/pre-commit"
out="$("${DOCTOR}" --vault "${V}" 2>&1)"
rc=$?
assert_exit 1 "${rc}" "exits 1 when the hook is missing"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"no pre-commit hook"*) pass "names the missing hook" ;;
  *) fail "names the missing hook" "${out}" ;;
esac

# The remediation names the vault's own id, not the literal "VAULT_ID" it used
# to print. That was always a copy-paste hazard; since init-vault.sh started
# refusing unedited placeholders it is a command that fails by design.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"--id VAULT_ID"*) fail "the fix command names the real id, not a placeholder" "${out}" ;;
  *"--id work --adopt"*) pass "the fix command names the real id, not a placeholder" ;;
  *) fail "the fix command names the real id, not a placeholder" "${out}" ;;
esac

# And it runs. Asserting the string alone would have passed just as happily on
# the placeholder version, which is what let it sit there.
fix_cmd="$(printf '%s\n' "${out}" | sed -n 's/.*— run: \(\.\/scripts\/init-vault\.sh .*\)$/\1/p' | head -1)"
TESTS_RUN=$((TESTS_RUN + 1))
if [ -n "${fix_cmd}" ] && ( cd "${ENGINE}" && eval "${fix_cmd}" ) >/dev/null 2>&1; then
  pass "and the printed fix command actually runs"
else
  fail "and the printed fix command actually runs" "${fix_cmd:-no command found in: ${out}}"
fi
assert_file "${V}/.git/hooks/pre-commit" "and installs the hook it was supposed to"

# --- a vault with a foreign hook ---------------------------------------------
printf '#!/bin/sh\necho foreign\n' > "${V}/.git/hooks/pre-commit"
chmod +x "${V}/.git/hooks/pre-commit"
out="$("${DOCTOR}" --vault "${V}" 2>&1)"
rc=$?
assert_exit 1 "${rc}" "exits 1 when the hook is not ours"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"is not ours"*) pass "names the foreign hook" ;;
  *) fail "names the foreign hook" "${out}" ;;
esac

# --- not a git repo at all yet ----------------------------------------------
NOGIT="${SANDBOX}/nogit"
mkdir -p "${NOGIT}"
out="$("${DOCTOR}" --vault "${NOGIT}" 2>&1)"
rc=$?
assert_exit 1 "${rc}" "exits 1 when the vault isn't a git repo yet"

# --- resolves vault from config file -----------------------------------------
# Clear the foreign hook from the previous case so --adopt has something
# absent to install — this is checking config resolution, not hook state.
rm -f "${V}/.git/hooks/pre-commit"
"${INIT}" --path "${V}" --id work --adopt >/dev/null 2>&1
printf 'SBW_VAULT=%s\nSKILLS_DIRS=%s:%s\n' "${V}" "${EMPTY1}" "${EMPTY2}" > "${SANDBOX}/config"
SBW_CONFIG_FILE="${SANDBOX}/config" "${DOCTOR}" >/dev/null 2>&1
assert_exit 0 $? "resolves vault from config file"

# --- check_skills(): only one skills dir configured -------------------------
out="$(SKILLS_DIRS="${EMPTY1}" "${DOCTOR}" --vault "${V}" 2>&1)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"only one skills directory configured"*) pass "a single configured skills dir is a no-op, not a false gap" ;;
  *) fail "a single configured skills dir is a no-op, not a false gap" "${out}" ;;
esac

# --- check_skills(): nothing installed anywhere -----------------------------
out="$("${DOCTOR}" --vault "${V}" 2>&1)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"no skills installed anywhere yet"*) pass "no skills installed anywhere is reported plainly" ;;
  *) fail "no skills installed anywhere is reported plainly" "${out}" ;;
esac

# --- check_skills(): consistent skill in both dirs --------------------------
mkdir -p "${EMPTY1}/consistent-skill" "${EMPTY2}/consistent-skill"
out="$("${DOCTOR}" --vault "${V}" 2>&1)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"consistent-skill"*) fail "a skill present in every dir produces no finding" "unexpectedly listed" ;;
  *"every installed skill is present in all configured skills directories"*) pass "a skill present in every dir produces no finding" ;;
  *) fail "a skill present in every dir produces no finding" "${out}" ;;
esac
rm -rf "${EMPTY1}/consistent-skill" "${EMPTY2}/consistent-skill"

# --- check_skills(): a foreign install missing from one dir -----------------
# Simulates Railway's use-railway: a real directory (someone else's install),
# not one of ours, present in only one configured skills dir.
mkdir -p "${EMPTY1}/foreign-tool"
echo "not ours" > "${EMPTY1}/foreign-tool/SKILL.md"
out="$("${DOCTOR}" --vault "${V}" 2>&1)"
rc=$?
assert_exit 1 "${rc}" "exits 1 when a foreign skill is missing from one dir"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"foreign-tool: in ${EMPTY1} but not ${EMPTY2} — fix: ln -s ${EMPTY1}/foreign-tool ${EMPTY2}/foreign-tool"*)
    pass "prints the exact ln -s fix for a foreign skill" ;;
  *) fail "prints the exact ln -s fix for a foreign skill" "${out}" ;;
esac
rm -rf "${EMPTY1}/foreign-tool"

# --- a finding in one check never ends the run -------------------------------
# check_skills' last command was a bare test, so a run with something to report
# returned 1 from it — and under `set -e` that ended the script there: no
# orphaned-skill check, no submodule check, no summary line, and an ERROR raised
# earlier reported as exit 1 (warnings only) instead of 2 (misconfiguration).
# Pairing a skills finding with a path that points nowhere pins both halves.
mkdir -p "${EMPTY1}/foreign-tool"
echo "not ours" > "${EMPTY1}/foreign-tool/SKILL.md"
out="$("${DOCTOR}" --vault "${SANDBOX}/no-such-vault" 2>&1)"
rc=$?
assert_exit 2 "${rc}" "an error alongside a warning still exits 2, not 1"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"no skills of ours are installed outside SKILLS_DIRS"*)
    pass "checks after the one with a finding still run" ;;
  *) fail "checks after the one with a finding still run" "${out}" ;;
esac
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"of them misconfiguration"*) pass "and the summary line is still printed" ;;
  *) fail "and the summary line is still printed" "${out}" ;;
esac
rm -rf "${EMPTY1}/foreign-tool"

# --- check_skills(): one of ours, missing from one dir ----------------------
# A symlink into this engine's own skills/ tree — the fix is sync-skills.sh,
# not a manual ln -s, since that command alone would propagate it everywhere.
OURS="${ENGINE}/skills/workflow/mcp-per-project"
ln -s "${OURS}" "${EMPTY1}/mcp-per-project"
out="$("${DOCTOR}" --vault "${V}" 2>&1)"
rc=$?
assert_exit 1 "${rc}" "exits 1 when one of our own skills is missing from one dir"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"mcp-per-project: not installed in every configured skills dir — run ./scripts/sync-skills.sh"*)
    pass "recommends sync-skills.sh for one of our own skills, not a manual ln -s" ;;
  *) fail "recommends sync-skills.sh for one of our own skills, not a manual ln -s" "${out}" ;;
esac
rm -f "${EMPTY1}/mcp-per-project"

# --- check_submodules(): drift after a tag switch ---------------------------
# STANDARDS_DIR is derived from doctor.sh's own script path, so exercising
# this against a real `git submodule status` (not a mock) means building a
# throwaway "engine" — its own git repo, its own real submodule — and
# copying doctor.sh + its one lib dependency into it, rather than mutating
# the real second-brain-workflow checkout's own vendor/obsidian-skills.
SUBMOD_UPSTREAM="${SANDBOX}/submod-upstream"
mkdir -p "${SUBMOD_UPSTREAM}"
git -C "${SUBMOD_UPSTREAM}" init -q
printf 'v1\n' > "${SUBMOD_UPSTREAM}/file.txt"
git -C "${SUBMOD_UPSTREAM}" add file.txt
git -c user.email=t@t.com -c user.name=t -C "${SUBMOD_UPSTREAM}" commit -q -m v1
SUBMOD_V1="$(git -C "${SUBMOD_UPSTREAM}" rev-parse HEAD)"
printf 'v2\n' > "${SUBMOD_UPSTREAM}/file.txt"
git -C "${SUBMOD_UPSTREAM}" add file.txt
git -c user.email=t@t.com -c user.name=t -C "${SUBMOD_UPSTREAM}" commit -q -m v2

FAKE_ENGINE="${SANDBOX}/fake-engine"
mkdir -p "${FAKE_ENGINE}/scripts/lib"
cp "${ENGINE}/scripts/doctor.sh" "${FAKE_ENGINE}/scripts/doctor.sh"
# The whole lib directory, not a hand-listed subset: doctor.sh gains a
# dependency now and then, and a list that has to be remembered is one that
# silently goes stale — this fixture failed exactly that way once.
cp "${ENGINE}"/scripts/lib/*.sh "${FAKE_ENGINE}/scripts/lib/"
git -C "${FAKE_ENGINE}" init -q
git -c protocol.file.allow=always -C "${FAKE_ENGINE}" \
  submodule add -q "file://${SUBMOD_UPSTREAM}" vendor/thing >/dev/null 2>&1
git -c user.email=t@t.com -c user.name=t -C "${FAKE_ENGINE}" commit -q -m init

FAKE_DOCTOR="${FAKE_ENGINE}/scripts/doctor.sh"
FAKE_VAULT="${SANDBOX}/fake-vault-for-submodule-test"
mkdir -p "${FAKE_VAULT}"
fake_doctor() { SKILLS_DIRS="${EMPTY1}:${EMPTY2}" "${FAKE_DOCTOR}" --vault "${FAKE_VAULT}" 2>&1; }

out="$(fake_doctor)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"vendored submodule(s) match the commit this checkout pins"*)
    pass "submodule at the pinned commit: reported clean" ;;
  *) fail "submodule at the pinned commit: reported clean" "${out}" ;;
esac

# Move the submodule's checked-out commit without touching the superproject's
# index — exactly what a plain `git checkout v<VERSION>` in the engine
# leaves vendor/obsidian-skills in (see REVIEW-ROUND-2 item 3).
git -C "${FAKE_ENGINE}/vendor/thing" checkout -q "${SUBMOD_V1}"
out="$(fake_doctor)"
rc=$?
assert_exit 1 "${rc}" "exits 1 when the submodule is out of sync with the pinned commit"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"submodule out of sync with the pinned commit"*"vendor/thing"*)
    pass "names the drifted submodule and its path" ;;
  *) fail "names the drifted submodule and its path" "${out}" ;;
esac

# --- check_submodules(): never initialized ----------------------------------
git -C "${FAKE_ENGINE}" submodule deinit -f vendor/thing >/dev/null 2>&1
out="$(fake_doctor)"
rc=$?
assert_exit 1 "${rc}" "exits 1 when the submodule was never initialized"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"submodule not initialized"*"vendor/thing"*)
    pass "names the uninitialized submodule" ;;
  *) fail "names the uninitialized submodule" "${out}" ;;
esac

finish
