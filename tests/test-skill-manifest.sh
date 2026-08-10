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
  "also allowed by source 'a'" "two sources cannot offer the same skill name"
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
  *"no third-party skill sources declared"*)
    pass "doctor says so plainly when no roster is configured" ;;
  *) fail "doctor says so plainly when no roster is configured" "${out}" ;;
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
