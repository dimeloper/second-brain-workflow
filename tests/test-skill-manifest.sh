#!/usr/bin/env bash
# The bring-your-own-skills path: manifest validation, resolution, fetching,
# linking, and the drifts doctor reports.
#
# Every fetch here clones over file:// from a fixture repo built inside the
# sandbox. Nothing in this file reaches the network — a suite that did would fail
# on a plane, and worse, would pass or fail depending on someone else's repo.
# shellcheck source=tests/lib.sh
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
setup_sandbox

MANIFEST_PY="${ENGINE}/scripts/lib/skill_manifest.py"
SYNC="${ENGINE}/scripts/sync-skills.sh"

# String equality with a message that names both sides. lib.sh has assert_exit
# for the same shape, but its failure text says "want exit N" — accurate for a
# status and misleading for a sha or a classification.
assert_str() {
  local want="$1" got="$2" name="$3"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ "${want}" = "${got}" ]; then
    pass "${name}"
  else
    fail "${name}" "want '${want}', got '${got}'"
  fi
}

# Sorted directory entry names, without ls — shellcheck is right that parsing ls
# is fragile, and these are fixture paths a test controls, so there is no reason
# to be clever.
entry_names() {
  find "$1" -mindepth 1 -maxdepth 1 -exec basename {} \; 2>/dev/null | sort
}

A="${SANDBOX}/skills-a"
export SKILLS_DIRS="${A}"

echo "skill manifest"

# --- fixtures ---------------------------------------------------------------
# A source repo with three skills, one of which collides with a local workflow
# skill so the shadowing rule has something to shadow.
SRC="${SANDBOX}/source-repo"
for name in animate review-animations update-second-brain; do
  mkdir -p "${SRC}/skills/${name}"
  printf -- '---\nname: %s\ndescription: fixture\n---\n\nbody\n' "${name}" \
    > "${SRC}/skills/${name}/SKILL.md"
done
git -C "${SRC}" init -q
git -C "${SRC}" add -A
git -C "${SRC}" -c user.email=fixture@example.com -c user.name=Fixture commit -qm one
SHA1="$(git -C "${SRC}" rev-parse HEAD)"

# A second commit, so pin drift is a real state rather than a simulated one.
printf -- '\nmore\n' >> "${SRC}/skills/animate/SKILL.md"
git -C "${SRC}" add -A
git -C "${SRC}" -c user.email=fixture@example.com -c user.name=Fixture commit -qm two
SHA2="$(git -C "${SRC}" rev-parse HEAD)"

# Write a manifest. Usage: write_manifest <file> <json>
write_manifest() { printf '%s\n' "$2" > "$1"; }

good="${SANDBOX}/good.json"
write_manifest "${good}" "{\"sources\":[{\"name\":\"fix\",\"repo\":\"file://${SRC}\",\"ref\":\"${SHA1}\",\"allow\":[\"animate\",\"review-animations\"]}]}"

# --- validation: every one of these is a hard error -------------------------
# A manifest is a plain mapping, so a misspelled key is not an error anywhere
# unless something makes it one. These assert that something does.
bad_case() {
  local json="$1" want="$2" name="$3" file out rc
  file="${SANDBOX}/bad-$$.json"
  write_manifest "${file}" "${json}"
  out="$(SBW_SKILLS_MANIFEST="${file}" python3 "${MANIFEST_PY}" validate 2>&1)"
  rc=$?
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ "${rc}" != "2" ]; then
    fail "${name}" "want exit 2, got ${rc}: ${out}"
  elif ! printf '%s' "${out}" | grep -q -- "${want}"; then
    fail "${name}" "message did not mention '${want}': ${out}"
  else
    pass "${name}"
  fi
  rm -f "${file}"
}

bad_case '{"sources":[],"extra":1}' "unknown key 'extra'" \
  "an unknown top-level key is an error"
bad_case "{\"sources\":[{\"name\":\"f\",\"repo\":\"r\",\"ref\":\"${SHA1}\",\"alow\":[]}]}" \
  "did you mean 'allow'" "a misspelled source key names the key it meant"
bad_case "{\"sources\":[{\"name\":\"f\",\"repo\":\"r\",\"ref\":\"${SHA1}\"}]}" \
  "missing required key 'allow'" "a source with no allow list is an error"
bad_case '{"sources":[{"name":"f","repo":"r","allow":[]}]}' \
  "'ref' is required" "an unpinned source is refused"
bad_case "{\"sources\":[{\"name\":\"a\",\"repo\":\"r\",\"ref\":\"${SHA1}\",\"allow\":[]},{\"name\":\"a\",\"repo\":\"r2\",\"ref\":\"${SHA2}\",\"allow\":[]}]}" \
  "duplicate source name" "two sources cannot share a name"
bad_case "{\"sources\":[{\"name\":\"a\",\"repo\":\"r\",\"ref\":\"${SHA1}\",\"allow\":[\"x\"]},{\"name\":\"b\",\"repo\":\"r2\",\"ref\":\"${SHA2}\",\"allow\":[\"x\"]}]}" \
  "sources 'a' and 'b' both allow skill 'x'" "two sources cannot offer the same skill name"
bad_case "{\"sources\":[{\"name\":\"../escape\",\"repo\":\"r\",\"ref\":\"${SHA1}\",\"allow\":[]}]}" \
  "single safe path segment" "a source name that escapes its directory is refused"
bad_case '{"sources":{}}' "'sources' must be an array" \
  "sources must be an array"
bad_case '{}' "no 'sources' key" "an empty object is not an empty roster"
bad_case 'not json' "not valid JSON" "unparseable JSON is an error"

# A short ref is legal but warns: it is a real pin today and may stop being one.
short="${SANDBOX}/short.json"
write_manifest "${short}" "{\"sources\":[{\"name\":\"f\",\"repo\":\"file://${SRC}\",\"ref\":\"${SHA1:0:8}\",\"allow\":[]}]}"
out="$(SBW_SKILLS_MANIFEST="${short}" python3 "${MANIFEST_PY}" validate 2>&1)"
assert_exit 0 $? "an abbreviated ref is accepted"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"not a full 40-character sha"*) pass "an abbreviated ref warns" ;;
  *) fail "an abbreviated ref warns" "${out}" ;;
esac

# --- no manifest configured is a supported state, not an error --------------
out="$(env -u SBW_SKILLS_MANIFEST python3 "${MANIFEST_PY}" resolve)"
assert_exit 0 $? "no manifest configured exits 0"
assert_str "" "${out}" "no manifest configured resolves nothing"

# An explicitly empty value is a deliberate "none", the same reading every other
# config key gets — not a request for some default roster.
out="$(SBW_SKILLS_MANIFEST="" python3 "${MANIFEST_PY}" resolve)"
assert_exit 0 $? "an empty SBW_SKILLS_MANIFEST is 'none', not a default"

# A manifest that is configured but absent is an error: it names a roster that
# should be there, and silently running without it is how a machine ends up
# missing skills nobody notices are missing.
out="$(SBW_SKILLS_MANIFEST="${SANDBOX}/nope.json" python3 "${MANIFEST_PY}" resolve 2>&1)"
assert_exit 2 $? "a configured manifest that does not exist is an error"

# --- resolution reports the three states --------------------------------------
rows="$(SBW_SKILLS_MANIFEST="${good}" python3 "${MANIFEST_PY}" resolve --engine "${SANDBOX}/fake-engine")"
TESTS_RUN=$((TESTS_RUN + 1))
case "${rows}" in
  *"missing-source"*) pass "an unfetched source resolves as missing-source" ;;
  *) fail "an unfetched source resolves as missing-source" "${rows}" ;;
esac

# --- fetching ---------------------------------------------------------------
# The engine directory is copied per-case so a fetch never writes into the real
# checkout's vendor/external — the suite must not leave clones behind.
ENG="${SANDBOX}/engine"
mkdir -p "${ENG}"
cp -R "${ENGINE}/scripts" "${ENG}/scripts"
cp -R "${ENGINE}/skills" "${ENG}/skills"

fetch() { SBW_SKILLS_MANIFEST="${good}" "${ENG}/scripts/fetch-skill-sources.sh" "$@"; }

out="$(fetch 2>&1)"
assert_exit 0 $? "fetch preview exits 0"
assert_no_file "${ENG}/vendor/external/fix" "preview clones nothing"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"would: git clone"*) pass "preview names the clone it would run" ;;
  *) fail "preview names the clone it would run" "${out}" ;;
esac

out="$(fetch --yes 2>&1)"
assert_exit 0 $? "fetch --yes exits 0"
assert_file "${ENG}/vendor/external/fix/skills/animate/SKILL.md" "clones the source"
got="$(git -C "${ENG}/vendor/external/fix" rev-parse HEAD)"
assert_str "${SHA1}" "${got}" "checks out the pinned sha"

# Detached, not on a branch: a branch would move under the pin.
TESTS_RUN=$((TESTS_RUN + 1))
if git -C "${ENG}/vendor/external/fix" symbolic-ref -q HEAD >/dev/null; then
  fail "the checkout is detached" "HEAD is on a branch"
else
  pass "the checkout is detached"
fi

out="$(fetch 2>&1)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"already at ${SHA1}"*) pass "a second run reports it is up to date" ;;
  *) fail "a second run reports it is up to date" "${out}" ;;
esac

# Re-pinning to a different sha is a fetch, not a manual fix.
drift="${SANDBOX}/drift.json"
write_manifest "${drift}" "{\"sources\":[{\"name\":\"fix\",\"repo\":\"file://${SRC}\",\"ref\":\"${SHA2}\",\"allow\":[\"animate\"]}]}"
SBW_SKILLS_MANIFEST="${drift}" "${ENG}/scripts/fetch-skill-sources.sh" --yes >/dev/null 2>&1
got="$(git -C "${ENG}/vendor/external/fix" rev-parse HEAD)"
assert_str "${SHA2}" "${got}" "re-pinning moves the checkout to the new sha"
SBW_SKILLS_MANIFEST="${good}" "${ENG}/scripts/fetch-skill-sources.sh" --yes >/dev/null 2>&1

# A directory that is not a git checkout is someone else's; this script does not
# get to decide what happens to it.
mkdir -p "${ENG}/vendor/external/stranger"
printf 'mine\n' > "${ENG}/vendor/external/stranger/README"
strange="${SANDBOX}/stranger.json"
write_manifest "${strange}" "{\"sources\":[{\"name\":\"stranger\",\"repo\":\"file://${SRC}\",\"ref\":\"${SHA1}\",\"allow\":[]}]}"
out="$(SBW_SKILLS_MANIFEST="${strange}" "${ENG}/scripts/fetch-skill-sources.sh" --yes 2>&1)"
assert_exit 1 $? "a non-checkout directory makes fetch exit 1"
assert_file "${ENG}/vendor/external/stranger/README" "a non-checkout directory is left untouched"

# An undeclared leftover is reported, never removed: the cost of keeping one is
# disk, and the cost of a wrong rm -rf on a config-derived path is not.
out="$(fetch 2>&1)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"stranger: checked out but no longer declared"*) pass "an undeclared checkout is reported" ;;
  *) fail "an undeclared checkout is reported" "${out}" ;;
esac
assert_file "${ENG}/vendor/external/stranger/README" "an undeclared checkout is not deleted"
rm -rf "${ENG}/vendor/external/stranger"

# --- linking ----------------------------------------------------------------
sync_eng() { SBW_SKILLS_MANIFEST="${1}" "${ENG}/scripts/sync-skills.sh" "${@:2}"; }

sync_eng "${good}" >/dev/null 2>&1
assert_exit 0 $? "sync with a fetched manifest exits 0"
assert_symlink "${A}/animate" "links a manifest skill"
assert_symlink "${A}/review-animations" "links every allowed manifest skill"
assert_symlink "${A}/update-second-brain" "still links the workflow skills"

# The local skill wins. The source carries its own update-second-brain, and a
# roster adopted from someone else must never displace this repo's own.
target="$(readlink "${A}/update-second-brain")"
TESTS_RUN=$((TESTS_RUN + 1))
case "${target}" in
  *"/skills/workflow/update-second-brain") pass "a local skill shadows a same-named manifest skill" ;;
  *) fail "a local skill shadows a same-named manifest skill" "${target}" ;;
esac

# Dropping a skill from `allow` prunes its link — the source still exists, so
# only the desired-set comparison can catch this, not a dangling-link sweep.
dropped="${SANDBOX}/dropped.json"
write_manifest "${dropped}" "{\"sources\":[{\"name\":\"fix\",\"repo\":\"file://${SRC}\",\"ref\":\"${SHA1}\",\"allow\":[\"animate\"]}]}"
sync_eng "${dropped}" >/dev/null 2>&1
assert_no_file "${A}/review-animations" "dropping a skill from allow prunes its link"
assert_symlink "${A}/animate" "the still-allowed skill survives the prune"

# --- the failure states sync reports ----------------------------------------
missing="${SANDBOX}/missing.json"
write_manifest "${missing}" "{\"sources\":[{\"name\":\"nothere\",\"repo\":\"file://${SRC}\",\"ref\":\"${SHA1}\",\"allow\":[\"animate\"]}]}"
err_out="$(sync_eng "${missing}" 2>&1 >/dev/null)"
assert_exit 1 $? "an unfetched source makes sync exit 1"
TESTS_RUN=$((TESTS_RUN + 1))
case "${err_out}" in
  *"not fetched"*"fetch-skill-sources.sh --yes"*) pass "sync names the fetch command by its script form" ;;
  *) fail "sync names the fetch command by its script form" "${err_out}" ;;
esac

# The make form, because a reader who typed `make sync-skills` cannot use the
# script form without translating it — and translating needs what they came for.
err_out="$(MAKELEVEL=1 sync_eng "${missing}" 2>&1 >/dev/null)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${err_out}" in
  *"make fetch-skills YES=1"*) pass "invoked via make, sync names the make form" ;;
  *) fail "invoked via make, sync names the make form" "${err_out}" ;;
esac

typo="${SANDBOX}/typo.json"
write_manifest "${typo}" "{\"sources\":[{\"name\":\"f\",\"repo\":\"r\",\"ref\":\"${SHA1}\",\"alow\":[]}]}"
B="${SANDBOX}/skills-b"
out="$(SKILLS_DIRS="${B}" sync_eng "${typo}" 2>&1)"
assert_exit 2 $? "an unusable manifest makes sync exit 2"
assert_no_file "${B}/update-second-brain" "an unusable manifest installs nothing at all"

# A skill named in `allow` that the source does not carry: a rename upstream, or
# a typo. Distinct from an unfetched source, and the fix is different.
typo_skill="${SANDBOX}/typo-skill.json"
write_manifest "${typo_skill}" "{\"sources\":[{\"name\":\"fix\",\"repo\":\"file://${SRC}\",\"ref\":\"${SHA1}\",\"allow\":[\"animte\"]}]}"
err_out="$(sync_eng "${typo_skill}" 2>&1 >/dev/null)"
assert_exit 1 $? "a skill missing from a fetched source makes sync exit 1"
TESTS_RUN=$((TESTS_RUN + 1))
case "${err_out}" in
  *"not in source 'fix'"*) pass "a missing skill is reported against its source" ;;
  *) fail "a missing skill is reported against its source" "${err_out}" ;;
esac

# --- VENDOR_SKILLS keeps working, unchanged ---------------------------------
# The whole release rests on this: no machine and no onboarded repo has to act,
# so the submodule allowlist must behave exactly as it did before the manifest
# existed. Compared as a set of links, which is what actually matters.
C="${SANDBOX}/skills-c"
env -u SBW_SKILLS_MANIFEST SKILLS_DIRS="${C}" "${SYNC}" >/dev/null 2>&1
assert_exit 0 $? "sync with no manifest still exits 0"
assert_symlink "${C}/obsidian-bases" "the submodule allowlist still installs"
assert_no_file "${C}/animate" "no manifest means no third-party skills"
before="$(entry_names "${C}")"
env -u SBW_SKILLS_MANIFEST SKILLS_DIRS="${C}" "${SYNC}" >/dev/null 2>&1
after="$(entry_names "${C}")"
assert_str "${before}" "${after}" "the no-manifest install set is stable across runs"

# --- the dangling-link classifier -------------------------------------------
# The bug this replaced: skill_link_engine_layout knew two layouts and a fetched
# source matched neither, so once its checkout was gone the link classified as
# someone else's problem and uninstall.sh would never remove it.
# shellcheck source=scripts/lib/skill-links.sh
. "${ENGINE}/scripts/lib/skill-links.sh"

# The dangling case is by definition a target *outside* the checkout doing the
# classifying: a link written by an engine checkout that has since been deleted
# or moved. Judging it against its own path would take the "resolves inside this
# checkout" branch and never reach the layout heuristic at all.
classify() { skill_link_class "$1" "${SANDBOX}/current-engine"; }

got="$(classify "${SANDBOX}/gone-engine/vendor/external/fix/skills/animate")"
assert_str "ours-dangling" "${got}" "a dangling fetched-source link is ours"

got="$(classify "${SANDBOX}/gone-engine/vendor/external/fix/agents/animate")"
assert_str "ours-dangling" "${got}" "a custom skills_subdir still classifies as ours"

got="$(classify "${SANDBOX}/gone-engine/vendor/obsidian-skills/skills/obsidian-bases")"
assert_str "ours-dangling" "${got}" "the submodule layout still classifies as ours"

got="$(classify "${SANDBOX}/gone-engine/skills/workflow/update-second-brain")"
assert_str "ours-dangling" "${got}" "the local layout still classifies as ours"

got="$(classify "${SANDBOX}/somewhere/else/use-railway")"
assert_str "foreign-dangling" "${got}" "an unrelated dangling link is still foreign"

# --- doctor reports each drift ----------------------------------------------
# Doctor is read-only, so each of these is proved by breaking the state and
# reading what it says. A check only ever seen to say "ok" is untested.
doctor_out() {
  SBW_SKILLS_MANIFEST="${1}" SKILLS_DIRS="${2}" \
    "${ENG}/scripts/doctor.sh" --vault "${SANDBOX}/no-vault" 2>&1
}

D="${SANDBOX}/skills-d"
mkdir -p "${D}"
sync_eng "${good}" >/dev/null 2>&1   # into $A, which SKILLS_DIRS still names
out="$(doctor_out "${good}" "${A}")"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"every declared third-party skill is fetched at its pin and linked"*)
    pass "doctor is clean when the roster is fully installed" ;;
  *) fail "doctor is clean when the roster is fully installed" "${out}" ;;
esac

out="$(doctor_out "${good}" "${D}")"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"not linked into any configured skills dir"*)
    pass "doctor reports a declared skill that is not linked" ;;
  *) fail "doctor reports a declared skill that is not linked" "${out}" ;;
esac

out="$(doctor_out "${missing}" "${A}")"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"declared but not fetched"*) pass "doctor reports an unfetched source" ;;
  *) fail "doctor reports an unfetched source" "${out}" ;;
esac

# Pin drift: the checkout works perfectly and is the wrong commit, which is
# precisely why nothing else can see it.
git -C "${ENG}/vendor/external/fix" checkout -q --detach "${SHA2}"
out="$(doctor_out "${good}" "${A}")"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"but the manifest pins ${SHA1}"*) pass "doctor reports pin drift" ;;
  *) fail "doctor reports pin drift" "${out}" ;;
esac
git -C "${ENG}/vendor/external/fix" checkout -q --detach "${SHA1}"

# A link whose skill left the allow list, with the source still present.
sync_eng "${good}" >/dev/null 2>&1
out="$(doctor_out "${dropped}" "${A}")"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"review-animations"*"no manifest source declares it"*)
    pass "doctor reports a link no source declares" ;;
  *) fail "doctor reports a link no source declares" "${out}" ;;
esac

out="$(doctor_out "${typo}" "${A}")"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"skill manifest unusable"*) pass "doctor reports an unusable manifest as misconfiguration" ;;
  *) fail "doctor reports an unusable manifest as misconfiguration" "${out}" ;;
esac

out="$(env -u SBW_SKILLS_MANIFEST SKILLS_DIRS="${A}" \
  "${ENG}/scripts/doctor.sh" --vault "${SANDBOX}/no-vault" 2>&1)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"no skills manifest configured — roster checks skipped"*"SBW_SKILLS_MANIFEST"*)
    pass "doctor names the key when no roster is configured" ;;
  *) fail "doctor names the key when no roster is configured" "${out}" ;;
esac

# The pair that has to stay distinguishable. Unconfigured is a supported state
# and says so at `ok`; configured-and-unreadable is a fault and says so at ERROR.
# Collapsing them is how a machine ends up missing skills nobody notices are
# missing — the manifest names a roster that should be there.
out="$(SBW_SKILLS_MANIFEST="${SANDBOX}/absent.json" SKILLS_DIRS="${A}" \
  "${ENG}/scripts/doctor.sh" --vault "${SANDBOX}/no-vault" 2>&1)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"roster checks skipped"*)
    fail "a configured-but-missing manifest is an error, not the skipped line" "${out}" ;;
  *"skill manifest unusable"*)
    pass "a configured-but-missing manifest is an error, not the skipped line" ;;
  *) fail "a configured-but-missing manifest is an error, not the skipped line" "${out}" ;;
esac

# Which roster answered, on clean runs too. Every finding above is a finding
# *from this manifest*, and two machines with different rosters print the same
# headings — so the report is only readable once it names the one it read.
sync_eng "${good}" >/dev/null 2>&1
out="$(doctor_out "${good}" "${A}")"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"roster: ${good}"*"environment variable"*)
    pass "doctor names the manifest it read, and where the setting came from" ;;
  *) fail "doctor names the manifest it read, and where the setting came from" "${out}" ;;
esac

# doctor's --help is a hardcoded line range over its own header, and adding a
# check to the header without widening the range silently truncates the help.
# That range has now rotted three times, so this check belongs with the change
# that would rot it rather than only in the test that first caught it.
out="$("${ENG}/scripts/doctor.sh" --help 2>&1)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"is fetched, at its pinned"*) pass "--help lists the roster check" ;;
  *) fail "--help lists the roster check" "${out}" ;;
esac
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"isn't finished yet\" (1) is what a reader mid-setup needed."*)
    pass "--help still reaches the last line of the header" ;;
  *) fail "--help still reaches the last line of the header" "${out}" ;;
esac

# --- the drift checks do not care what shape an allow entry has --------------
# Every one of these compares names against what it believes is a list of
# strings. An object entry is exactly the change that would make each of them
# silently stop matching, so each is re-run against one.
good_obj="${SANDBOX}/good-object.json"
write_manifest "${good_obj}" "{\"sources\":[{\"name\":\"fix\",\"repo\":\"file://${SRC}\",\"ref\":\"${SHA1}\",\"license\":\"MIT\",\"allow\":[{\"name\":\"animate\"},{\"name\":\"review-animations\"}]}]}"

sync_eng "${good_obj}" >/dev/null 2>&1
out="$(doctor_out "${good_obj}" "${A}")"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"every declared third-party skill is fetched at its pin and linked"*)
    pass "doctor is clean against object allow entries" ;;
  *) fail "doctor is clean against object allow entries" "${out}" ;;
esac

out="$(doctor_out "${good_obj}" "${D}")"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"not linked into any configured skills dir"*)
    pass "declared-not-linked still fires on an object entry" ;;
  *) fail "declared-not-linked still fires on an object entry" "${out}" ;;
esac

git -C "${ENG}/vendor/external/fix" checkout -q --detach "${SHA2}"
out="$(doctor_out "${good_obj}" "${A}")"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"but the manifest pins ${SHA1}"*) pass "wrong-sha still fires on an object entry" ;;
  *) fail "wrong-sha still fires on an object entry" "${out}" ;;
esac
git -C "${ENG}/vendor/external/fix" checkout -q --detach "${SHA1}"

dropped_obj="${SANDBOX}/dropped-object.json"
write_manifest "${dropped_obj}" "{\"sources\":[{\"name\":\"fix\",\"repo\":\"file://${SRC}\",\"ref\":\"${SHA1}\",\"license\":\"MIT\",\"allow\":[{\"name\":\"animate\"}]}]}"
sync_eng "${good_obj}" >/dev/null 2>&1
out="$(doctor_out "${dropped_obj}" "${A}")"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"review-animations"*"no manifest source declares it"*)
    pass "linked-with-no-source still fires on an object entry" ;;
  *) fail "linked-with-no-source still fires on an object entry" "${out}" ;;
esac

# Linking reads the same list, and a link is the thing an operator actually gets.
assert_symlink "${A}/animate" "an object allow entry links its skill"
sync_eng "${good}" >/dev/null 2>&1

# --- guarantees older than the object form of an allow entry -----------------
# Three of them, each written when `allow` held nothing but strings, each
# claiming to cover a level that did not exist yet. None was asserted against an
# object entry, so each was a claim about a shape the code had never been shown.

# Strict unknown keys, one level further in. This is the exact failure the rule
# frontmatter check exists for: a manifest is a plain mapping, so `applies_too`
# is not an error anywhere — the entry parses, the scope silently falls back to
# the source's, and the report is confident and wrong.
bad_case "{\"sources\":[{\"name\":\"f\",\"repo\":\"r\",\"ref\":\"${SHA1}\",\"license\":\"MIT\",\"allow\":[{\"name\":\"x\",\"applies_too\":[\"**/*.tsx\"]}]}]}" \
  "did you mean 'applies_to'" "a misspelled key inside an allow entry names the key it meant"

# "// is a comment at every level" now covers a level younger than the claim.
# And an entry is where a note is most wanted: why this one is scoped and its
# eleven siblings are not is the reasoning that decays fastest.
cmt="${SANDBOX}/entry-comment.json"
write_manifest "${cmt}" "{\"sources\":[{\"name\":\"f\",\"repo\":\"file://${SRC}\",\"ref\":\"${SHA1}\",\"license\":\"MIT\",\"allow\":[{\"// why scoped\":\"Next only\",\"name\":\"animate\",\"applies_to\":[\"**/next.config.*\"]}]}]}"
out="$(SBW_SKILLS_MANIFEST="${cmt}" python3 "${MANIFEST_PY}" validate 2>&1)"
assert_exit 0 $? "a // key inside an allow entry is a comment, not an unknown key"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"1 skill(s) allowed"*) pass "a commented allow entry is still one skill, not two" ;;
  *) fail "a commented allow entry is still one skill, not two" "${out}" ;;
esac

# The third guarantee — that the candidate/allow refusal still fires when the
# entry is an object — is asserted with the rest of the per-entry behaviour
# further down, where it was added alongside the object form itself.

# --- applies_to and candidates: the onboarding report ------------------------
# The gap this fills is the one the agent host cannot: it routes to installed
# skills and can say nothing about one that exists and is not.
REPO="${SANDBOX}/target-repo"
mkdir -p "${REPO}/app" "${REPO}/scripts"
: > "${REPO}/app.config.ts"
: > "${REPO}/app/screen.tsx"
: > "${REPO}/scripts/build.sh"

rel="${SANDBOX}/relevant.json"
write_manifest "${rel}" "{\"//note\":\"a comment key at top level\",\"sources\":[{\"name\":\"fix\",\"repo\":\"file://${SRC}\",\"ref\":\"${SHA1}\",\"applies_to\":[\"**/*.tsx\"],\"allow\":[\"animate\"]},{\"name\":\"broad\",\"repo\":\"file://${SRC}\",\"ref\":\"${SHA1}\",\"allow\":[\"review-animations\"]}],\"candidates\":[{\"name\":\"linter\",\"repo\":\"https://example.invalid/linter\",\"when\":\"design-heavy frontend; writes a hook\",\"install\":\"npx linter install --scope=project\",\"applies_to\":[\"**/*.css\"]},{\"name\":\"shots\",\"repo\":\"https://example.invalid/shots\",\"when\":\"store listings\",\"applies_to\":[\"app.config.*\"]}]}"

out_rel="$(SBW_SKILLS_MANIFEST="${rel}" python3 "${MANIFEST_PY}" relevant --repo "${REPO}" 2>&1)"
assert_exit 0 $? "relevant mode exits 0"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_rel}" in
  *"Adopted and scoped to this repo: 1"*) pass "a scoped adopted skill matches on a real file" ;;
  *) fail "a scoped adopted skill matches on a real file" "${out_rel}" ;;
esac
# An unscoped skill is neither a match nor a miss — it was never claimed to be
# repo-specific, so reporting it as "does not apply" asserts something nobody said.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_rel}" in
  *"declare no applies_to, so they apply everywhere: review-animations"*)
    pass "an unscoped adopted skill is named separately, not dropped" ;;
  *) fail "an unscoped adopted skill is named separately, not dropped" "${out_rel}" ;;
esac
# `shots` matches app.config.ts; `linter` wants *.css, and this repo has none.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_rel}" in
  *"Not adopted, worth considering here: 1"*) pass "only candidates whose globs match are suggested" ;;
  *) fail "only candidates whose globs match are suggested" "${out_rel}" ;;
esac
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_rel}" in
  *"shots — store listings"*) pass "the matching candidate is named with its reason" ;;
  *) fail "the matching candidate is named with its reason" "${out_rel}" ;;
esac
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_rel}" in
  *"npx linter install"*) fail "a non-matching candidate is not suggested" "${out_rel}" ;;
  *) pass "a non-matching candidate is not suggested" ;;
esac
# No install command means adoption is a manifest edit, and the report says so
# rather than leaving the reader with a name and no next step.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_rel}" in
  *"add it to skills.json sources"*) pass "a candidate with no install command still says how" ;;
  *) fail "a candidate with no install command still says how" "${out_rel}" ;;
esac

# Which roster answered. onboard-repo reads this report out loud, and every
# count in it is a count from one particular manifest.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_rel}" in
  *"roster: ${rel}"*"environment variable"*)
    pass "the relevance report names the manifest it read and its origin" ;;
  *) fail "the relevance report names the manifest it read and its origin" "${out_rel}" ;;
esac

# Nothing configured is not the same fact as nothing relevant, and step 2b of
# onboard-repo used to see them as one silence. Exit 0 either way — an
# unconfigured roster is supported — but the reader is told which one it is.
out_none="$(env -u SBW_SKILLS_MANIFEST python3 "${MANIFEST_PY}" relevant --repo "${REPO}" 2>&1)"
assert_exit 0 $? "relevant mode with no manifest configured exits 0"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_none}" in
  *"no skills manifest configured"*"SBW_SKILLS_MANIFEST"*)
    pass "relevant mode names the skipped roster instead of printing nothing" ;;
  *) fail "relevant mode names the skipped roster instead of printing nothing" "${out_none}" ;;
esac
# ...and only in the modes a person reads. `resolve` and `sources` are parsed by
# sync-skills.sh and fetch-skill-sources.sh, where a courtesy line on stdout is
# read as a row — which is exactly how a source named "no" would get fetched.
out_none="$(env -u SBW_SKILLS_MANIFEST python3 "${MANIFEST_PY}" resolve 2>/dev/null)"
assert_str "" "${out_none}" "machine-readable modes stay silent with no manifest"
out_none="$(env -u SBW_SKILLS_MANIFEST python3 "${MANIFEST_PY}" sources 2>/dev/null)"
assert_str "" "${out_none}" "sources mode stays silent with no manifest"

# A repo the globs do not touch reports nothing rather than everything.
BARE="${SANDBOX}/bare-repo"
mkdir -p "${BARE}"
: > "${BARE}/Makefile"
out_bare="$(SBW_SKILLS_MANIFEST="${rel}" python3 "${MANIFEST_PY}" relevant --repo "${BARE}" 2>&1)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_bare}" in
  *"Adopted and scoped to this repo: 0"*"Not adopted, worth considering here: 0"*)
    pass "a repo the globs do not match reports nothing" ;;
  *) fail "a repo the globs do not match reports nothing" "${out_bare}" ;;
esac

# Only the status matters for these two, so the output is discarded rather than
# captured into a variable nothing reads.
SBW_SKILLS_MANIFEST="${rel}" python3 "${MANIFEST_PY}" relevant >/dev/null 2>&1
assert_exit 2 $? "relevant mode without --repo is an error"
SBW_SKILLS_MANIFEST="${rel}" python3 "${MANIFEST_PY}" relevant --repo "${SANDBOX}/nope" >/dev/null 2>&1
assert_exit 2 $? "relevant mode on a missing repo is an error"

# `**/x` must match the repo root too. fnmatch alone demands a literal slash, so
# a file at the top level — the single most likely place to look — would be missed.
ROOTED="${SANDBOX}/rooted-repo"
mkdir -p "${ROOTED}"
: > "${ROOTED}/main.tsx"
out_rooted="$(SBW_SKILLS_MANIFEST="${rel}" python3 "${MANIFEST_PY}" relevant --repo "${ROOTED}" 2>&1)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_rooted}" in
  *"Adopted and scoped to this repo: 1"*) pass "'**/*.tsx' matches a file at the repo root" ;;
  *) fail "'**/*.tsx' matches a file at the repo root" "${out_rooted}" ;;
esac

# --- candidate status: a decision, recorded but not pitched ------------------
# A decided candidate stays in the list rather than being deleted, because the
# value of a rejected option is the reason it was rejected — delete it and the
# next session re-evaluates from scratch and may reach a different answer for no
# new reason. `adopted` exists because a skill installed the vendor's own way is
# genuinely adopted while appearing in no source's allow list.
st="${SANDBOX}/status.json"
write_manifest "${st}" '{"sources":[],"candidates":[{"name":"pitch-me","repo":"r","when":"undecided","applies_to":["**/*.tsx"]},{"name":"took-it","repo":"r","status":"adopted","when":"installed the vendor way","applies_to":["**/*.tsx"]},{"name":"passed-on-it","repo":"r","status":"declined","when":"needs a second runtime","applies_to":["**/*.tsx"]}]}'
out_st="$(SBW_SKILLS_MANIFEST="${st}" python3 "${MANIFEST_PY}" relevant --repo "${ROOTED}" 2>&1)"
assert_exit 0 $? "a manifest with candidate statuses validates"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_st}" in
  *"Not adopted, worth considering here: 1"*) pass "only an undecided candidate is pitched" ;;
  *) fail "only an undecided candidate is pitched" "${out_st}" ;;
esac
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_st}" in
  *"Already decided, not pitched: 2"*) pass "decided candidates are counted separately" ;;
  *) fail "decided candidates are counted separately" "${out_st}" ;;
esac
# Visible, not filtered out: a roster that silently omitted what was rejected
# would invite re-litigating it, which the reason exists to prevent.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_st}" in
  *"took-it [adopted]"*"passed-on-it [declined]"*)
    pass "each decision is named with its standing" ;;
  *) fail "each decision is named with its standing" "${out_st}" ;;
esac
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_st}" in
  *"needs a second runtime"*) fail "a decided candidate is not re-pitched with its full case" "${out_st}" ;;
  *) pass "a decided candidate is not re-pitched with its full case" ;;
esac
bad_case '{"sources":[],"candidates":[{"name":"x","repo":"r","when":"w","status":"maybe"}]}' \
  "'status' must be one of" "an unknown status is an error, not a silent default"

# --- a candidate that is also allowed: three outcomes, not one ---------------
# One rule keyed on presence was right while every candidate was a pitch.
# `status` made the same overlap mean three different things, and only one of
# them is the contradiction the original message describes.
overlap() {
  printf '{"sources":[{"name":"src","repo":"r","ref":"%s","license":"MIT","allow":["dup"]}],"candidates":[{"name":"dup","repo":"r","when":"w"%s}]}\n' \
    "${SHA1}" "$1" > "${SANDBOX}/overlap.json"
  SBW_SKILLS_MANIFEST="${SANDBOX}/overlap.json" python3 "${MANIFEST_PY}" validate 2>&1
}

suggested_msg="$(overlap '')"; rc=$?
assert_exit 2 "${rc}" "suggested and allowed is still refused"
TESTS_RUN=$((TESTS_RUN + 1))
case "${suggested_msg}" in
  *"cannot be both adopted and merely suggested"*)
    pass "the suggested refusal keeps the message it has always had" ;;
  *) fail "the suggested refusal keeps the message it has always had" "${suggested_msg}" ;;
esac

# Harmless duplication today; tomorrow the allow entry is dropped and the
# candidate still claims adopted with nothing reconciling the two. So it warns,
# and the warning has to say which of the two records linking actually reads.
out="$(overlap ',"status":"adopted"')"; rc=$?
assert_exit 0 "${rc}" "adopted and allowed exits exactly as a clean run does"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"warning:"*"recorded twice"*"source 'src' allows it"*"calls it adopted"*)
    pass "adopted and allowed warns, naming both records" ;;
  *) fail "adopted and allowed warns, naming both records" "${out}" ;;
esac
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"allow entry is what linking reads"*)
    pass "the warning says which record is load-bearing" ;;
  *) fail "the warning says which record is load-bearing" "${out}" ;;
esac

declined_msg="$(overlap ',"status":"declined"')"; rc=$?
assert_exit 2 "${rc}" "declined and allowed is refused"
TESTS_RUN=$((TESTS_RUN + 1))
case "${declined_msg}" in
  *"linked into every session anyway"*) pass "the declined refusal names its own fault" ;;
  *) fail "the declined refusal names its own fault" "${declined_msg}" ;;
esac
# Asserted as *different*, not merely as present. Declined-yet-linked and
# pitched-yet-linked have different fixes — one decline was never carried out,
# the other roster contradicts itself — and one message reused for both would
# pass a check that only asked whether each errored.
TESTS_RUN=$((TESTS_RUN + 1))
if [ "${suggested_msg}" = "${declined_msg}" ]; then
  fail "the two refusals do not share a message" "both said: ${declined_msg}"
else
  pass "the two refusals do not share a message"
fi

# The decision lives in the parser, so it reaches every mode. Asserted through a
# second one because v0.17.0's skipped line is already scoped to two of four,
# and a later split that dropped this warning would look like nothing at all.
printf '{"sources":[{"name":"src","repo":"r","ref":"%s","license":"MIT","allow":["dup"]}],"candidates":[{"name":"dup","repo":"r","when":"w","status":"adopted"}]}\n' \
  "${SHA1}" > "${SANDBOX}/overlap.json"
out="$(SBW_SKILLS_MANIFEST="${SANDBOX}/overlap.json" python3 "${MANIFEST_PY}" \
  relevant --repo "${ROOTED}" 2>&1)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"recorded twice"*) pass "the double-bookkeeping warning is not scoped to one mode" ;;
  *) fail "the double-bookkeeping warning is not scoped to one mode" "${out}" ;;
esac

# --- license: a warning, not a gate -----------------------------------------
# "What am I allowed to do with this" gets asked once at adoption and then never
# again, which is exactly the kind of question that wants a mechanical prompt.
# Not fatal, because the answer is a judgement this script cannot make.
nolic="${SANDBOX}/nolicense.json"
write_manifest "${nolic}" "{\"sources\":[{\"name\":\"fix\",\"repo\":\"file://${SRC}\",\"ref\":\"${SHA1}\",\"allow\":[]}]}"
out_nolic="$(SBW_SKILLS_MANIFEST="${nolic}" python3 "${MANIFEST_PY}" validate 2>&1)"
assert_exit 0 $? "a source with no license still validates"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_nolic}" in
  *"no 'license' recorded for 'fix'"*"all-rights-reserved by default"*)
    pass "a source with no license warns, naming the repo and the default" ;;
  *) fail "a source with no license warns, naming the repo and the default" "${out_nolic}" ;;
esac

haslic="${SANDBOX}/haslicense.json"
write_manifest "${haslic}" "{\"sources\":[{\"name\":\"fix\",\"repo\":\"file://${SRC}\",\"ref\":\"${SHA1}\",\"license\":\"MIT\",\"allow\":[]}]}"
out_haslic="$(SBW_SKILLS_MANIFEST="${haslic}" python3 "${MANIFEST_PY}" validate 2>&1)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_haslic}" in
  *"no 'license' recorded"*) fail "a recorded license silences the warning" "${out_haslic}" ;;
  *) pass "a recorded license silences the warning" ;;
esac

# Blank is an error rather than a silent pass: it looks answered and is not, which
# is worse than omitting the key, whose warning at least says what is missing.
bad_case "{\"sources\":[{\"name\":\"f\",\"repo\":\"r\",\"ref\":\"${SHA1}\",\"license\":\"\",\"allow\":[]}]}" \
  "'license' must be a non-empty string" "a blank license is an error, not a warning"

# A candidate's license is shown at the moment of decision, and free text is
# allowed so "there isn't one" can be recorded as the finding it is.
lic_rel="${SANDBOX}/lic-relevant.json"
write_manifest "${lic_rel}" "{\"sources\":[],\"candidates\":[{\"name\":\"unl\",\"repo\":\"https://example.invalid/unl\",\"license\":\"none upstream, all rights reserved\",\"when\":\"blocked\",\"applies_to\":[\"**/*.tsx\"]}]}"
out_lic="$(SBW_SKILLS_MANIFEST="${lic_rel}" python3 "${MANIFEST_PY}" relevant --repo "${ROOTED}" 2>&1)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_lic}" in
  *"[none upstream, all rights reserved]"*) pass "a candidate's license is shown in the report" ;;
  *) fail "a candidate's license is shown in the report" "${out_lic}" ;;
esac

nolic_rel="${SANDBOX}/lic-none.json"
write_manifest "${nolic_rel}" "{\"sources\":[],\"candidates\":[{\"name\":\"unk\",\"repo\":\"https://example.invalid/unk\",\"when\":\"unknown terms\",\"applies_to\":[\"**/*.tsx\"]}]}"
out_unk="$(SBW_SKILLS_MANIFEST="${nolic_rel}" python3 "${MANIFEST_PY}" relevant --repo "${ROOTED}" 2>&1)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_unk}" in
  *"[license not recorded]"*) pass "a candidate with no license says so rather than staying quiet" ;;
  *) fail "a candidate with no license says so rather than staying quiet" "${out_unk}" ;;
esac

# --- per-entry applies_to and license ----------------------------------------
# `ref`, `applies_to` and `license` attach to a source; what gets allowlisted and
# reasoned about is a skill. A twelve-skill repo of which three are Next-only
# could declare that scope for all twelve or for none, and both are honest
# readings of a declaration that cannot say the true thing.
NEXTREPO="${SANDBOX}/next-repo"
mkdir -p "${NEXTREPO}/app"
: > "${NEXTREPO}/next.config.js"
: > "${NEXTREPO}/app/page.tsx"
PYREPO="${SANDBOX}/py-repo"
mkdir -p "${PYREPO}"
: > "${PYREPO}/main.py"

# A bare string and {"name": ...} are the same declaration written two ways, and
# the coercion is the one `source:` and `repos:` already do on the note side.
# Asserted on the report rather than on parse success: parsing both is not the
# claim, meaning the same thing is.
bare="${SANDBOX}/entry-bare.json"
objd="${SANDBOX}/entry-object.json"
write_manifest "${bare}" "{\"sources\":[{\"name\":\"s\",\"repo\":\"r\",\"ref\":\"${SHA1}\",\"license\":\"MIT\",\"applies_to\":[\"**/*.tsx\"],\"allow\":[\"animate\"]}]}"
write_manifest "${objd}" "{\"sources\":[{\"name\":\"s\",\"repo\":\"r\",\"ref\":\"${SHA1}\",\"license\":\"MIT\",\"applies_to\":[\"**/*.tsx\"],\"allow\":[{\"name\":\"animate\"}]}]}"
out_bare="$(SBW_SKILLS_MANIFEST="${bare}" python3 "${MANIFEST_PY}" relevant --repo "${NEXTREPO}" 2>&1 | grep -v '^roster:')"
out_objd="$(SBW_SKILLS_MANIFEST="${objd}" python3 "${MANIFEST_PY}" relevant --repo "${NEXTREPO}" 2>&1 | grep -v '^roster:')"
assert_str "${out_bare}" "${out_objd}" "an object entry naming only 'name' reports identically to the bare string"

# Replace, not merge. The case this exists for is narrowing, and a merge can only
# widen — which is what omitting the key already does. So a repo the *source's*
# globs match is a miss for an entry that narrowed away from them.
narrow="${SANDBOX}/entry-narrow.json"
write_manifest "${narrow}" "{\"sources\":[{\"name\":\"s\",\"repo\":\"r\",\"ref\":\"${SHA1}\",\"license\":\"MIT\",\"applies_to\":[\"**/*.py\"],\"allow\":[\"a11y-audit\",{\"//\":\"scaffolds a Next app\",\"name\":\"screenshot\",\"applies_to\":[\"**/next.config.*\"]}]}]}"
out_narrow="$(SBW_SKILLS_MANIFEST="${narrow}" python3 "${MANIFEST_PY}" relevant --repo "${PYREPO}" 2>&1)"
assert_exit 0 $? "a per-entry override validates, and a // key inside it is a comment"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_narrow}" in
  *"screenshot"*)
    fail "an entry's applies_to replaces the source's rather than merging" "${out_narrow}" ;;
  *"Adopted and scoped to this repo: 1"*)
    pass "an entry's applies_to replaces the source's rather than merging" ;;
  *) fail "an entry's applies_to replaces the source's rather than merging" "${out_narrow}" ;;
esac

# ...and the narrowed entry still matches where it said it did.
out_next="$(SBW_SKILLS_MANIFEST="${narrow}" python3 "${MANIFEST_PY}" relevant --repo "${NEXTREPO}" 2>&1)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_next}" in
  *"screenshot  (matched next.config.js"*)
    pass "a narrowed entry matches the repo it was narrowed to" ;;
  *) fail "a narrowed entry matches the repo it was narrowed to" "${out_next}" ;;
esac

# The origin of a resolved scope, not only the scope. A wrong glob inherited from
# the source reads identically in the report to one declared on the entry, and
# the two have different fixes.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_next}" in
  *"screenshot"*"scope from this entry"*)
    pass "the report says a scope came from the entry" ;;
  *) fail "the report says a scope came from the entry" "${out_next}" ;;
esac
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_narrow}" in
  *"a11y-audit"*"scope inherited from source 's'"*)
    pass "the report says an inherited scope came from its source, and names it" ;;
  *) fail "the report says an inherited scope came from its source, and names it" "${out_narrow}" ;;
esac

# The validator's key-set check has to walk the level that did not exist when it
# was written, or a misspelling here is a key nobody reads — the whole reason
# unknown keys are fatal anywhere in this file.
bad_case "{\"sources\":[{\"name\":\"s\",\"repo\":\"r\",\"ref\":\"${SHA1}\",\"allow\":[{\"name\":\"x\",\"aplies_to\":[\"*\"]}]}]}" \
  "did you mean 'applies_to'" "a misspelled key inside an allow entry names the key it meant"
bad_case "{\"sources\":[{\"name\":\"s\",\"repo\":\"r\",\"ref\":\"${SHA1}\",\"allow\":[{\"applies_to\":[\"*\"]}]}]}" \
  "source 's'" "an allow entry with no name is an error naming its source"
bad_case "{\"sources\":[{\"name\":\"s\",\"repo\":\"r\",\"ref\":\"${SHA1}\",\"allow\":[[\"x\"]]}]}" \
  "must be a skill name or an object" "an allow entry that is neither a string nor an object is an error"

# Blank and empty look answered and are not. The error names both of the things
# the writer might have meant, because an omitted key here has a real meaning.
bad_case "{\"sources\":[{\"name\":\"s\",\"repo\":\"r\",\"ref\":\"${SHA1}\",\"allow\":[{\"name\":\"x\",\"applies_to\":[]}]}]}" \
  "Omit the key to inherit the source's scope, or list the globs" \
  "an empty applies_to on an entry is an error naming both alternatives"
bad_case "{\"sources\":[{\"name\":\"s\",\"repo\":\"r\",\"ref\":\"${SHA1}\",\"allow\":[{\"name\":\"x\",\"license\":\"\"}]}]}" \
  "'license' must be a non-empty string" "a blank license on an entry is an error"

# Inheritance is silent. A source that recorded a licence answered the question
# for every skill under it, and re-asking per skill is noise.
inherit="${SANDBOX}/entry-inherit.json"
write_manifest "${inherit}" "{\"sources\":[{\"name\":\"s\",\"repo\":\"r\",\"ref\":\"${SHA1}\",\"license\":\"MIT\",\"allow\":[{\"name\":\"x\"},{\"name\":\"y\"}]}]}"
out_inh="$(SBW_SKILLS_MANIFEST="${inherit}" python3 "${MANIFEST_PY}" validate 2>&1)"
assert_exit 0 $? "an entry inheriting its source's license validates"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_inh}" in
  *"no 'license' recorded"*) fail "inheriting a license warns about nothing" "${out_inh}" ;;
  *) pass "inheriting a license warns about nothing" ;;
esac

# One warning per source, never one per skill. Twelve unlicensed skills under one
# unlicensed source are one unanswered question, and turning that into twelve
# lines is a regression in noise for no new information.
twelve="${SANDBOX}/entry-twelve.json"
allow_twelve=""
for n in 1 2 3 4 5 6 7 8 9 10 11 12; do
  allow_twelve="${allow_twelve}${allow_twelve:+,}\"skill${n}\""
done
write_manifest "${twelve}" "{\"sources\":[{\"name\":\"s\",\"repo\":\"r\",\"ref\":\"${SHA1}\",\"allow\":[${allow_twelve}]}]}"
out_twelve="$(SBW_SKILLS_MANIFEST="${twelve}" python3 "${MANIFEST_PY}" validate 2>&1 >/dev/null)"
lic_warnings="$(printf '%s\n' "${out_twelve}" | grep -c "no 'license' recorded")"
assert_str "1" "${lic_warnings}" "a twelve-skill unlicensed source warns exactly once"

# ...and says how much of itself is unanswered. One line is right; one line that
# reads identically at nine of twelve and at twelve of twelve is not, and after
# per-entry licences those are different numbers behind the same words. Every
# other report here states the scope of its own claim.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_twelve}" in
  *"12 of the 12 skills allowed here have no license of their own"*)
    pass "the license warning counts the entries that inherit it" ;;
  *) fail "the license warning counts the entries that inherit it" "${out_twelve}" ;;
esac

# Printed at twelve of twelve as well as at nine, because a count that appears
# only when it is partial is one nobody learns to read — the same argument as
# printing the decided-candidates section at zero.
three_over="${SANDBOX}/entry-three-override.json"
allow_mixed=""
for n in 1 2 3; do
  allow_mixed="${allow_mixed}${allow_mixed:+,}{\"name\":\"skill${n}\",\"license\":\"MIT\"}"
done
for n in 4 5 6 7 8 9 10 11 12; do
  allow_mixed="${allow_mixed},\"skill${n}\""
done
write_manifest "${three_over}" "{\"sources\":[{\"name\":\"s\",\"repo\":\"r\",\"ref\":\"${SHA1}\",\"allow\":[${allow_mixed}]}]}"
out_three="$(SBW_SKILLS_MANIFEST="${three_over}" python3 "${MANIFEST_PY}" validate 2>&1 >/dev/null)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_three}" in
  *"9 of the 12 skills allowed here have no license of their own"*)
    pass "entries that record their own license are subtracted from the count" ;;
  *) fail "entries that record their own license are subtracted from the count" "${out_three}" ;;
esac
lic_warnings="$(printf '%s\n' "${out_three}" | grep -c "no 'license' recorded")"
assert_str "1" "${lic_warnings}" "a partly-answered source still warns exactly once"

# A declared source with nothing adopted from it yet. "0 of 0" is not a
# sentence, and the question is still open — the source is in the roster.
empty_allow="${SANDBOX}/entry-empty-allow.json"
write_manifest "${empty_allow}" "{\"sources\":[{\"name\":\"s\",\"repo\":\"r\",\"ref\":\"${SHA1}\",\"allow\":[]}]}"
out_empty="$(SBW_SKILLS_MANIFEST="${empty_allow}" python3 "${MANIFEST_PY}" validate 2>&1 >/dev/null)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_empty}" in
  *"nothing is allowed from it yet"*)
    pass "a source with an empty allow list warns without counting to zero" ;;
  *) fail "a source with an empty allow list warns without counting to zero" "${out_empty}" ;;
esac

# A source every one of whose entries answers the question is fully answered.
allover="${SANDBOX}/entry-all-override.json"
write_manifest "${allover}" "{\"sources\":[{\"name\":\"s\",\"repo\":\"r\",\"ref\":\"${SHA1}\",\"allow\":[{\"name\":\"x\",\"license\":\"MIT\"},{\"name\":\"y\",\"license\":\"none upstream\"}]}]}"
out_all="$(SBW_SKILLS_MANIFEST="${allover}" python3 "${MANIFEST_PY}" validate 2>&1)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_all}" in
  *"no 'license' recorded"*) fail "a source whose every entry records a license does not warn" "${out_all}" ;;
  *) pass "a source whose every entry records a license does not warn" ;;
esac

# ...and one that only partly answers it still asks. The unanswered skill is the
# reason the question is open.
partial="${SANDBOX}/entry-partial.json"
write_manifest "${partial}" "{\"sources\":[{\"name\":\"s\",\"repo\":\"r\",\"ref\":\"${SHA1}\",\"allow\":[{\"name\":\"x\",\"license\":\"MIT\"},{\"name\":\"y\"}]}]}"
out_part="$(SBW_SKILLS_MANIFEST="${partial}" python3 "${MANIFEST_PY}" validate 2>&1)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_part}" in
  *"no 'license' recorded"*) pass "a source only some of whose entries record a license still warns" ;;
  *) fail "a source only some of whose entries record a license still warns" "${out_part}" ;;
esac

# The adopted-and-suggested refusal compares names against what is now a list of
# mappings, which is exactly the shape change that would make it stop firing.
bad_case "{\"sources\":[{\"name\":\"s\",\"repo\":\"r\",\"ref\":\"${SHA1}\",\"license\":\"MIT\",\"allow\":[{\"name\":\"animate\"}]}],\"candidates\":[{\"name\":\"animate\",\"repo\":\"r\",\"when\":\"w\"}]}" \
  "cannot be both adopted and merely suggested" \
  "an object allow entry still collides with a candidate of the same name"

# Two sources offering one skill name have no resolution order, whatever shape
# either one is written in.
bad_case "{\"sources\":[{\"name\":\"a\",\"repo\":\"r\",\"ref\":\"${SHA1}\",\"license\":\"MIT\",\"allow\":[\"x\"]},{\"name\":\"b\",\"repo\":\"r2\",\"ref\":\"${SHA2}\",\"license\":\"MIT\",\"allow\":[{\"name\":\"x\"}]}]}" \
  "sources 'a' and 'b' both allow skill 'x'" "a duplicate skill name is caught across both entry shapes"

# --- a source whose skills sit at the repo root ------------------------------
# Undocumented until now, and worth pinning: several suites put skill directories
# at the top level rather than under skills/.
ROOTSRC="${SANDBOX}/engine-root"
mkdir -p "${ROOTSRC}/scripts" "${ROOTSRC}/vendor/external/flat/design-review"
cp -R "${ENGINE}/scripts/lib" "${ROOTSRC}/scripts/lib"
printf -- '---\nname: design-review\ndescription: fixture\n---\nbody\n' \
  > "${ROOTSRC}/vendor/external/flat/design-review/SKILL.md"
flat="${SANDBOX}/flat.json"
write_manifest "${flat}" "{\"sources\":[{\"name\":\"flat\",\"repo\":\"file://${SRC}\",\"ref\":\"${SHA1}\",\"license\":\"MIT\",\"skills_subdir\":\".\",\"allow\":[\"design-review\"]}]}"
out_flat="$(SBW_SKILLS_MANIFEST="${flat}" python3 "${MANIFEST_PY}" resolve --engine "${ROOTSRC}" 2>&1)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_flat}" in
  ok*design-review*) pass "skills_subdir '.' resolves a source whose skills are at its root" ;;
  *) fail "skills_subdir '.' resolves a source whose skills are at its root" "${out_flat}" ;;
esac

# --- one skill name, one slot ------------------------------------------------
# A flat install directory holds one link per name. By the time linking runs both
# candidate targets resolve inside the checkout, so both classify as ours and
# neither of sync's refusals applies: ln -sfn repoints and the last source
# iterated wins. Nothing downstream would say so — the declared-but-not-linked
# check resolves by name, finds a link, and reports clean.
collide="${SANDBOX}/collide.json"
write_manifest "${collide}" "{\"sources\":[{\"name\":\"one\",\"repo\":\"file://${SRC}\",\"ref\":\"${SHA1}\",\"license\":\"MIT\",\"allow\":[\"animate\"]},{\"name\":\"two\",\"repo\":\"file://${SRC}\",\"ref\":\"${SHA1}\",\"license\":\"MIT\",\"allow\":[\"animate\"]}]}"

# Raised at parse, before anything touches disk, which is what makes it every
# caller's refusal rather than one script's. Asserted through each of the four
# separately: a behaviour that exists in one path and not another is exactly the
# shape doctor's roster check and v0.17.0's mode split both turned out to have.
E="${SANDBOX}/skills-e"
SBW_SKILLS_MANIFEST="${collide}" python3 "${MANIFEST_PY}" relevant --repo "${ROOTED}" >/dev/null 2>&1
assert_exit 2 $? "skills-for refuses a name two sources both allow"
out="$(SKILLS_DIRS="${E}" sync_eng "${collide}" 2>&1)"
assert_exit 2 $? "sync refuses a name two sources both allow"
assert_no_file "${E}/animate" "the refused manifest links nothing at all"
out="$(SBW_SKILLS_MANIFEST="${collide}" "${ENG}/scripts/fetch-skill-sources.sh" 2>&1)"
assert_exit 2 $? "fetch refuses a name two sources both allow"
assert_no_file "${ENG}/vendor/external/two" "the refused manifest clones nothing"
out="$(doctor_out "${collide}" "${A}")"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"skill manifest unusable"*) pass "doctor reports the collision as misconfiguration" ;;
  *) fail "doctor reports the collision as misconfiguration" "${out}" ;;
esac

# The same name twice inside one source is a different mistake with a different
# fix, so it gets its own message rather than one that names that source as
# though it were two. An error, not a silent dedup: the two entries can differ in
# applies_to or license, only one of them can be honoured, and nothing in the
# file says which.
bad_case "{\"sources\":[{\"name\":\"solo\",\"repo\":\"r\",\"ref\":\"${SHA1}\",\"license\":\"MIT\",\"allow\":[\"x\",{\"name\":\"x\",\"applies_to\":[\"**/*.py\"]}]}]}" \
  "source 'solo' allows 'x' twice" "one source cannot allow the same skill twice"

# The scope of that refusal, pinned by a test rather than by a comment: the one
# name collision this system is built around still resolves the way it always
# has. A local skill of your own shadows a vendored one — asserted above on the
# install itself, and asserted here as the case the refusal must not reach.
shadow="${SANDBOX}/shadow.json"
write_manifest "${shadow}" "{\"sources\":[{\"name\":\"fix\",\"repo\":\"file://${SRC}\",\"ref\":\"${SHA1}\",\"license\":\"MIT\",\"allow\":[\"update-second-brain\"]}]}"
SBW_SKILLS_MANIFEST="${shadow}" python3 "${MANIFEST_PY}" validate >/dev/null 2>&1
assert_exit 0 $? "a manifest skill named like a local one is not a collision"

# --- a source name is declared, and it is what keeps two checkouts apart ------
# `name` becomes the directory under vendor/external/, so two entries sharing one
# would put a single clone behind two declared refs: fetch leaves it detached at
# whichever ran last, and the drift check then answers about fetch order rather
# than about the manifest. It is declared rather than derived from `repo`, which
# is what makes one repo at two refs expressible at all.
bad_case "{\"sources\":[{\"name\":\"same\",\"repo\":\"file://${SRC}\",\"ref\":\"${SHA1}\",\"license\":\"MIT\",\"allow\":[\"animate\"]},{\"name\":\"same\",\"repo\":\"file://${SRC}\",\"ref\":\"${SHA2}\",\"license\":\"MIT\",\"allow\":[\"review-animations\"]}]}" \
  "duplicate source name 'same'" "two entries cannot share a checkout directory"

# One repo, two refs, two names, disjoint allow lists. Each checkout is drift-
# checked against its own ref — and the whole point is that the answer does not
# depend on which entry came first, so every assertion below runs twice with the
# order reversed.
apart_fixture() {
  printf '{"sources":[%s,%s]}\n' "$1" "$2" > "${SANDBOX}/apart.json"
}
APART_NEW="{\"name\":\"pair-new\",\"repo\":\"file://${SRC}\",\"ref\":\"${SHA2}\",\"license\":\"MIT\",\"allow\":[\"animate\"]}"
APART_OLD="{\"name\":\"pair-old\",\"repo\":\"file://${SRC}\",\"ref\":\"${SHA1}\",\"license\":\"MIT\",\"allow\":[\"review-animations\"]}"

for order in "forward" "reversed"; do
  rm -rf "${ENG}/vendor/external/pair-new" "${ENG}/vendor/external/pair-old"
  if [ "${order}" = "forward" ]; then
    apart_fixture "${APART_NEW}" "${APART_OLD}"
  else
    apart_fixture "${APART_OLD}" "${APART_NEW}"
  fi
  apart="${SANDBOX}/apart.json"

  SBW_SKILLS_MANIFEST="${apart}" "${ENG}/scripts/fetch-skill-sources.sh" --yes >/dev/null 2>&1
  got="$(git -C "${ENG}/vendor/external/pair-new" rev-parse HEAD 2>/dev/null)"
  assert_str "${SHA2}" "${got}" "one repo at two refs: the newer checkout is at its own ref (${order})"
  got="$(git -C "${ENG}/vendor/external/pair-old" rev-parse HEAD 2>/dev/null)"
  assert_str "${SHA1}" "${got}" "one repo at two refs: the older checkout is at its own ref (${order})"

  sync_eng "${apart}" >/dev/null 2>&1
  out="$(doctor_out "${apart}" "${A}")"
  TESTS_RUN=$((TESTS_RUN + 1))
  case "${out}" in
    *"but the manifest pins"*)
      fail "a pinned-apart pair reports no drift (${order})" "${out}" ;;
    *) pass "a pinned-apart pair reports no drift (${order})" ;;
  esac

  # Move only the older one. The finding has to name that entry and its ref, not
  # the pair's repo — which the two share and which therefore identifies neither.
  git -C "${ENG}/vendor/external/pair-old" checkout -q --detach "${SHA2}"
  out="$(doctor_out "${apart}" "${A}")"
  TESTS_RUN=$((TESTS_RUN + 1))
  case "${out}" in
    *"source 'pair-old' is checked out at ${SHA2}"*"manifest pins ${SHA1}"*)
      pass "drift is reported against the entry that drifted (${order})" ;;
    *) fail "drift is reported against the entry that drifted (${order})" "${out}" ;;
  esac
  TESTS_RUN=$((TESTS_RUN + 1))
  case "${out}" in
    *"source 'pair-new'"*) fail "the entry that did not drift is not reported (${order})" "${out}" ;;
    *) pass "the entry that did not drift is not reported (${order})" ;;
  esac
  git -C "${ENG}/vendor/external/pair-old" checkout -q --detach "${SHA1}"
done

# Dropping one half of the pair leaves one leftover, named. The leftover report
# keys on the set of declared names, so the surviving entry — same repo, same
# clone contents, different name — must not absorb the other's checkout.
solo="${SANDBOX}/apart-solo.json"
printf '{"sources":[%s]}\n' "${APART_NEW}" > "${solo}"
out="$(SBW_SKILLS_MANIFEST="${solo}" "${ENG}/scripts/fetch-skill-sources.sh" 2>&1)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"pair-old: checked out but no longer declared"*)
    pass "dropping one entry of a pinned-apart pair reports its checkout as leftover" ;;
  *) fail "dropping one entry of a pinned-apart pair reports its checkout as leftover" "${out}" ;;
esac
leftovers="$(printf '%s\n' "${out}" | grep "no longer declared" | grep -c "pair-")"
assert_str "1" "${leftovers}" "the surviving half of the pair is not reported as leftover"
rm -rf "${ENG}/vendor/external/pair-new" "${ENG}/vendor/external/pair-old"
sync_eng "${good}" >/dev/null 2>&1

# --- candidate validation ---------------------------------------------------
bad_case "{\"sources\":[{\"name\":\"f\",\"repo\":\"r\",\"ref\":\"${SHA1}\",\"allow\":[\"animate\"]}],\"candidates\":[{\"name\":\"animate\",\"repo\":\"r\",\"when\":\"w\"}]}" \
  "cannot be both adopted and merely suggested" \
  "a skill cannot be adopted and a candidate at once"
bad_case '{"sources":[],"candidates":[{"name":"x","repo":"r"}]}' \
  "missing required key 'when'" "a candidate must say when it is worth it"
bad_case '{"sources":[],"candidates":[{"name":"x","repo":"r","when":"w","whn":"typo"}]}' \
  "unknown key 'whn'" "an unknown candidate key is an error"
bad_case '{"sources":[],"candidates":[{"name":"x","repo":"r","when":"w"},{"name":"x","repo":"r2","when":"w2"}]}' \
  "duplicate candidate" "two candidates cannot share a name"
bad_case '{"sources":[],"candidates":{}}' "'candidates' must be an array" \
  "candidates must be an array"
bad_case "{\"sources\":[{\"name\":\"f\",\"repo\":\"r\",\"ref\":\"${SHA1}\",\"allow\":[],\"applies_to\":\"*.tsx\"}]}" \
  "'applies_to' must be an array" "applies_to must be an array"
bad_case "{\"sources\":[{\"name\":\"f\",\"repo\":\"r\",\"ref\":\"${SHA1}\",\"allow\":[],\"applies_to\":[\"\"]}]}" \
  "blank or non-string glob" "a blank glob is an error"

# A comment key is ignored wherever it appears; a near-miss of a real key is not.
comment_ok="${SANDBOX}/comments.json"
write_manifest "${comment_ok}" "{\"//\":\"top\",\"//more\":[\"multi\",\"line\"],\"sources\":[{\"//why\":\"per-source note\",\"name\":\"f\",\"repo\":\"file://${SRC}\",\"ref\":\"${SHA1}\",\"allow\":[]}],\"candidates\":[{\"//\":\"per-candidate note\",\"name\":\"c\",\"repo\":\"r\",\"when\":\"w\"}]}"
SBW_SKILLS_MANIFEST="${comment_ok}" python3 "${MANIFEST_PY}" validate >/dev/null 2>&1
assert_exit 0 $? "a //-prefixed key is a comment at every level"

# The shipped example must be a valid manifest apart from its placeholder refs —
# it is written to be copied and edited in place, not stripped first.
out_example="$(SBW_SKILLS_MANIFEST="${ENGINE}/skills.json.example" python3 "${MANIFEST_PY}" validate 2>&1)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_example}" in
  *"still the placeholder"*) pass "the example fails only on its unedited placeholder ref" ;;
  *) fail "the example fails only on its unedited placeholder ref" "${out_example}" ;;
esac

# ...and the rest of it is a valid manifest, which the assertion above cannot
# say: the placeholder is refused at the first source, so everything after it —
# including every field the example exists to demonstrate — was never parsed.
edited="${SANDBOX}/example-edited.json"
sed "s/0000000000000000000000000000000000000000/${SHA1}/g" \
  "${ENGINE}/skills.json.example" > "${edited}"
out_example="$(SBW_SKILLS_MANIFEST="${edited}" python3 "${MANIFEST_PY}" validate 2>&1)"
rc=$?
assert_exit 0 "${rc}" "the example validates once its refs are filled in"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_example}" in
  *"warning:"*) fail "the edited example is warning-free" "${out_example}" ;;
  *) pass "the edited example is warning-free" ;;
esac

# --- the two config implementations know the same keys ----------------------
# There was no test tying these together, and the shell side is what the scripts
# read while the Python side decides what counts as an unknown key in a config
# file. A key in one and not the other means one of them warns about a setting
# the other honours.
shell_keys="$(
  # shellcheck source=scripts/lib/config.sh
  . "${ENGINE}/scripts/lib/config.sh"
  printf '%s\n' "${SBW_CONFIG_KEYS}" | tr ' ' '\n' | sort
)"
python_keys="$(python3 -c "
import sys
sys.path.insert(0, '${ENGINE}/scripts')
from lib.config import DEFAULTS
print('\n'.join(sorted(DEFAULTS)))
")"
TESTS_RUN=$((TESTS_RUN + 1))
if [ "${shell_keys}" = "${python_keys}" ]; then
  pass "config.sh and config.py define the same key set"
else
  fail "config.sh and config.py define the same key set" \
    "$(diff <(printf '%s\n' "${shell_keys}") <(printf '%s\n' "${python_keys}") | tr '\n' ' ')"
fi

TESTS_RUN=$((TESTS_RUN + 1))
case "${shell_keys}" in
  *SBW_SKILLS_MANIFEST*) pass "SBW_SKILLS_MANIFEST is a recognised config key" ;;
  *) fail "SBW_SKILLS_MANIFEST is a recognised config key" "${shell_keys}" ;;
esac

# Read from the config file, not only the environment — the roster lives beside
# rules/ in a private content repo, and it is the config file that points there.
cfg="${SANDBOX}/config-with-manifest"
printf 'SBW_SKILLS_MANIFEST=%s\nSKILLS_DIRS=%s\n' "${good}" "${SANDBOX}/skills-e" > "${cfg}"
env -u SBW_SKILLS_MANIFEST -u SKILLS_DIRS SBW_CONFIG_FILE="${cfg}" \
  "${ENG}/scripts/sync-skills.sh" >/dev/null 2>&1
assert_symlink "${SANDBOX}/skills-e/animate" "the config file can point at the manifest"

finish
