#!/usr/bin/env bash
# sync-skills.sh: multi-directory install, idempotency, pruning, and the
# refusals that protect files this script did not create.
#
# SKILLS_DIRS is redirected into the sandbox throughout — a test that touched
# ~/.cursor/skills or ~/.claude/skills would be destroying real configuration.
# shellcheck source=tests/lib.sh
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
setup_sandbox

SYNC="${ENGINE}/scripts/sync-skills.sh"
A="${SANDBOX}/skills-a"
B="${SANDBOX}/skills-b"
export SKILLS_DIRS="${A}:${B}"

echo "sync-skills.sh"

"${SYNC}" >/dev/null 2>&1
assert_exit 0 $? "installs cleanly into two directories"
assert_symlink "${A}/update-second-brain" "installs into the first directory"
assert_symlink "${B}/update-second-brain" "installs into the second directory"
assert_symlink "${A}/obsidian-knowledge-base" "installs every local skill"

# Vendored upstream skills, by allowlist.
assert_symlink "${A}/obsidian-bases" "installs allowlisted vendor skill"
assert_no_file "${A}/json-canvas"    "does not install unlisted vendor skill"

VENDOR_SKILLS="" "${SYNC}" >/dev/null 2>&1
assert_no_file "${A}/obsidian-bases" "empty allowlist installs no vendor skills"
"${SYNC}" >/dev/null 2>&1
assert_symlink "${A}/obsidian-bases" "vendor skill restored"

# --- idempotency ------------------------------------------------------------
"${SYNC}" >/dev/null 2>&1
assert_exit 0 $? "re-run is safe"

# --- dry run ----------------------------------------------------------------
C="${SANDBOX}/skills-c"
SKILLS_DIRS="${C}" "${SYNC}" --dry-run >/dev/null 2>&1
assert_no_file "${C}/update-second-brain" "--dry-run writes nothing"

# --- refuses to destroy what it did not create ------------------------------
# A real directory is a hand-maintained divergent copy. The old script rm -rf'd
# these; losing one is how a whole skill's edits disappear.
rm -f "${A}/update-second-brain"
mkdir -p "${A}/update-second-brain"
echo "mine" > "${A}/update-second-brain/SKILL.md"
"${SYNC}" >/dev/null 2>&1
assert_exit 1 $? "exits 1 when a real directory is in the way"
assert_contains "${A}/update-second-brain/SKILL.md" "mine" "real directory left untouched"
rm -rf "${A}/update-second-brain"

# A symlink owned by another tool is not ours to repoint.
ln -sfn "${SANDBOX}/elsewhere" "${A}/foreign-skill"
"${SYNC}" >/dev/null 2>&1
TESTS_RUN=$((TESTS_RUN + 1))
target="$(readlink "${A}/foreign-skill")"
if [ "${target}" = "${SANDBOX}/elsewhere" ]; then
  pass "foreign symlink left untouched"
else
  fail "foreign symlink left untouched" "now points at ${target}"
fi

# --- pruning ----------------------------------------------------------------
# Only links back into this repo that no longer resolve to a skill.
ln -sfn "${ENGINE}/skills/workflow/removed-skill" "${A}/removed-skill"
"${SYNC}" >/dev/null 2>&1
assert_no_file "${A}/removed-skill" "prunes our own dangling link"
assert_symlink "${A}/foreign-skill" "never prunes a foreign link"
rm -f "${A}/foreign-skill"

# --- config -----------------------------------------------------------------
D="${SANDBOX}/skills-d"
printf 'SKILLS_DIRS=%s\n' "${D}" > "${SANDBOX}/config"
env -u SKILLS_DIRS SBW_CONFIG_FILE="${SANDBOX}/config" "${SYNC}" >/dev/null 2>&1
assert_symlink "${D}/update-second-brain" "config file sets SKILLS_DIRS"

# What it prints next to `->` must be the link's real target. Printing a path
# shortened to be relative to the checkout read as a *relative link*, and that
# misreading is what sent a cleanup tool looking for a substring absolute links
# never contain. Asserted against readlink so the two cannot diverge again.
name="check-follow-ups"
if [ -L "${A}/${name}" ]; then
  printed="$("${SYNC}" 2>/dev/null | sed -n "s|^  ${name} -> ||p" | head -1)"
  actual="$(readlink "${A}/${name}")"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ -n "${printed}" ] && [ "${printed}" = "${actual}" ]; then
    pass "the printed target is the link's real target, as readlink reports it"
  else
    fail "the printed target is the link's real target, as readlink reports it" \
      "printed [${printed}] but the link points at [${actual}]"
  fi
fi

finish
