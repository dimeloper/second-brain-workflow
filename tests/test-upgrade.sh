#!/usr/bin/env bash
# upgrade.sh: preview by default, the changelog's required-action entries before
# anything is proposed, a refusal on anything a checkout switch would take with
# it, and a fail-closed report of which onboarded repos are behind.
#
# Everything runs against a throwaway engine checkout in the sandbox — its own
# git repo, its own fabricated tags, its own CHANGELOG — because the script
# switches the checkout it lives in, and doing that to the developer's own would
# be the one thing this suite must never do. --no-fetch throughout: a test has
# no remote, and none of what is being tested needs one.
# shellcheck source=tests/lib.sh
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
setup_sandbox

export XDG_CONFIG_HOME="${SANDBOX}/config-home"
SKILLS_A="${SANDBOX}/skills-a"
SKILLS_B="${SANDBOX}/skills-b"
mkdir -p "${SKILLS_A}" "${SKILLS_B}"
export SKILLS_DIRS="${SKILLS_A}:${SKILLS_B}"

OUT="${SANDBOX}/out"
out_has() {
  TESTS_RUN=$((TESTS_RUN + 1))
  if grep -qF -- "$1" "${OUT}"; then pass "$2"; else fail "$2" "$(cat "${OUT}")"; fi
}
out_lacks() {
  TESTS_RUN=$((TESTS_RUN + 1))
  if grep -qF -- "$1" "${OUT}"; then fail "$2" "$(cat "${OUT}")"; else pass "$2"; fi
}

# --- the fixture checkout ----------------------------------------------------
FIX="${SANDBOX}/engine"
mkdir -p "${FIX}"
# Copied entry by entry rather than with `git archive`: the script under test is
# not necessarily committed yet, and a fixture built from HEAD would test the
# previous version of it. vendor/ and .gitmodules are left out so
# `git submodule update` in the fixture is a no-op instead of a network clone.
for entry in "${ENGINE}"/* "${ENGINE}"/.[!.]*; do
  case "$(basename "${entry}")" in
    .git|vendor|.gitmodules) continue ;;
  esac
  cp -R "${entry}" "${FIX}/"
done
rm -rf "${FIX}/scripts/__pycache__" "${FIX}/scripts/lib/__pycache__"
# The public engine ships an empty rules/, so the fixture would render nothing
# and every drift assertion below would pass vacuously.
cp "${FIXTURES}/rules/"*.md "${FIX}/rules/"
cp "${FIXTURES}/AGENTS.md" "${FIX}/AGENTS.md"

UPGRADE="${FIX}/scripts/upgrade.sh"
git -C "${FIX}" init -q
git -C "${FIX}" config user.email "t@example.com"
git -C "${FIX}" config user.name "t"

# A synthetic changelog, so the assertions name strings that exist for the sake
# of being asserted on rather than release notes that will be rewritten.
#
# Sections are strings, not functions: release() would have to invoke them by
# name, and a function only ever invoked indirectly reads as unreachable to the
# linter — under a code that differs between its versions (SC2329 on 0.11,
# SC2317 on what CI installs), so silencing it here silenced nothing in CI. A
# variable has no such problem.
#
# (A line of prose must not begin with a "# shellcheck" the linter will try to
# parse as a directive, which is its own small lesson from the same run.)
CL_HEAD="$(cat <<'EOF'
# Changelog

## [Unreleased]

### Major
- MAJOR-UNRELEASED — carries no version, so it can never be inside a range.
EOF
)"
CL_095_DRAFT="$(cat <<'EOF'
## [0.9.5] - drafted, not tagged

### Major
- MAJOR-095-AHEAD — drafted above every target these tests use.
EOF
)"
CL_0100="$(cat <<'EOF'
## [0.10.0] - 2026-09-01

### Major
- MAJOR-0100 — two minor versions up.
EOF
)"
CL_092="$(cat <<'EOF'
## [0.9.2] - 2026-08-20

### Added
- ADDED-092 — this release has no Major entry at all.

### Fixed
- FIXED-092
EOF
)"
CL_091="$(cat <<'EOF'
## [0.9.1] - 2026-08-15

### Major
- MAJOR-091 first line.
  MAJOR-091 second line, indented under the first.

### Added
- ADDED-091
EOF
)"
CL_090="$(cat <<'EOF'
## [0.9.0] - 2026-08-10

### Major
- MAJOR-090 — below the range whenever 0.9.0 is the current version.
EOF
)"
CL_LINKS="$(cat <<'EOF'
[Unreleased]: https://example.com/compare/v0.10.0...HEAD
[0.10.0]: https://example.com/compare/v0.9.2...v0.10.0
EOF
)"

# Newest section first, as the real file is. The blank line between sections is
# added here rather than carried in the strings: command substitution strips
# trailing newlines, so a section cannot hold its own separator.
release() {
  local v="$1" section
  shift
  echo "${v}" > "${FIX}/VERSION"
  {
    printf '%s\n\n' "${CL_HEAD}"
    for section in "$@"; do printf '%s\n\n' "${section}"; done
    printf '%s\n' "${CL_LINKS}"
  } > "${FIX}/CHANGELOG.md"
  git -C "${FIX}" add -A
  git -C "${FIX}" commit -q -m "release ${v}"
  git -C "${FIX}" tag "v${v}"
}

release 0.9.0 "${CL_090}"
# The 0.9.1 release also grows upgrade.sh, so the --yes case below is switching
# the checkout out from under the very file bash is executing. That is the
# hazard the script wraps its body in a function for; without a version where
# the byte offsets move, the test would never exercise it.
awk 'NR==1 {print; for (i = 0; i < 60; i++) print "# fixture padding, to move every byte offset in this file"; next} {print}' \
  "${UPGRADE}" > "${FIX}/scripts/upgrade.next" && mv "${FIX}/scripts/upgrade.next" "${UPGRADE}"
chmod +x "${UPGRADE}"
release 0.9.1 "${CL_095_DRAFT}" "${CL_091}" "${CL_090}"
release 0.9.2 "${CL_095_DRAFT}" "${CL_092}" "${CL_091}" "${CL_090}"
release 0.10.0 "${CL_0100}" "${CL_095_DRAFT}" "${CL_092}" "${CL_091}" "${CL_090}"

at_version() { git -C "${FIX}" checkout -q "v$1"; }
head_sha() { git -C "${FIX}" rev-parse HEAD; }
at_version 0.9.0

# SCAN_ROOTS defaults to the sandbox HOME, where nothing is rendered, so a case
# that says nothing about the scan behaves as it did before there was one.
upgrade() {
  SBW_SCAN_ROOTS="${SCAN_ROOTS:-${HOME}}" \
    "${UPGRADE}" --no-fetch --vault "${VAULT}" "$@" >"${OUT}" 2>&1
}

# The registry stores realpaths, and on macOS $TMPDIR resolves /var -> /private/var
# — so an assertion naming an unresolved sandbox path compares two spellings of
# the same directory. Same trap tests/lib.sh documents for mktemp.
real() { (cd "$1" && pwd -P); }

# Byte-identity of a directory tree, for the "it never touches this" claims.
# cksum, not shasum/sha1sum: the first is POSIX and the other two are not the
# same command name on macOS and Linux.
fingerprint() {
  (cd "$1" && find . -path ./.git -prune -o -type f -print | LC_ALL=C sort | xargs cksum)
}

# --- a vault and one onboarded repo, both healthy ----------------------------
VAULT="${SANDBOX}/vault"
"${FIX}/scripts/init-vault.sh" --path "${VAULT}" --id work \
  --remote "git@example.com:me/wb.git" >/dev/null 2>&1
REPO_OK="${SANDBOX}/repo-ok"
make_target_repo "${REPO_OK}"
"${FIX}/scripts/render.py" "${REPO_OK}" >/dev/null 2>&1

echo "upgrade.sh"

# --- preview is the default -------------------------------------------------
sha_before="$(head_sha)"
upgrade --ref v0.9.1
rc=$?
assert_exit 0 "${rc}" "a clean machine previews and exits 0"
out_has "current 0.9.0 → target v0.9.1" "prints current → target"
out_has "preview only" "and says it is a preview"
TESTS_RUN=$((TESTS_RUN + 1))
if [ "$(head_sha)" = "${sha_before}" ]; then
  pass "the preview does not switch the checkout"
else
  fail "the preview does not switch the checkout"
fi
assert_no_file "${SKILLS_A}/mcp-per-project" "the preview installs no skills"
out_has "would run, in this order" "and names the commands it would run instead"

# The line a reader scans for permission to stop reading. In preview it is true
# when printed and false the instant --yes runs, so it has to say so itself
# rather than lean on the caveat in the section header above it.
out_has "all 1 repo(s) match the current checkout — expect all 1 to need" \
  "a clean preview qualifies its own summary line"
out_has "re-rendering after switching to v0.9.1" "naming the ref that will invalidate it"
out_lacks "all 1 checkable repo(s) are up to date" \
  "and never states it unqualified while a switch is still pending"
out_has "Re-run with --yes" "and names the flag, since this run was not via make"

# --- the Major entries, before anything is proposed -------------------------
out_has "MAJOR-091 first line." "prints the Major section in range"
out_has "  MAJOR-091 second line, indented under the first." "verbatim, indentation and all"
out_lacks "MAJOR-090" "not a Major section below the range"
out_lacks "MAJOR-095-AHEAD" "not a drafted section above the target"
out_lacks "MAJOR-UNRELEASED" "and never [Unreleased], which carries no version"
out_has "1 non-Major section(s) in this range not shown" "counts what it skipped"
# Order: the required action is printed before the checkout is even inspected.
TESTS_RUN=$((TESTS_RUN + 1))
if [ "$(grep -n 'MAJOR-091 first' "${OUT}" | head -1 | cut -d: -f1)" -lt \
     "$(grep -n 'Checkout state' "${OUT}" | head -1 | cut -d: -f1)" ]; then
  pass "and before anything else is proposed"
else
  fail "and before anything else is proposed" "$(cat "${OUT}")"
fi

# --- a range with no Major entry says so ------------------------------------
at_version 0.9.1
upgrade --ref v0.9.2
out_has "No Major entry between 0.9.1 and 0.9.2" "a range with no Major entry says so explicitly"
out_has "2 non-Major section(s)" "and still counts the sections it skipped"
at_version 0.9.0

# --- a vault ENGINE_REF behind the target -----------------------------------
mkdir -p "${VAULT}/.github/workflows"
printf 'env:\n  ENGINE_REF: v0.8.0\n' > "${VAULT}/.github/workflows/guard.yml"
vault_before="$(fingerprint "${VAULT}")"
upgrade --ref v0.9.1
rc=$?
out_has "guard.yml pins v0.8.0, behind the target v0.9.1" "reports a vault workflow pinned behind the target"
out_has "never writes to a vault" "and says who has to fix it"
assert_exit 1 "${rc}" "which is a finding, so the run exits 1"
TESTS_RUN=$((TESTS_RUN + 1))
if [ "$(fingerprint "${VAULT}")" = "${vault_before}" ]; then
  pass "and the vault is byte-identical afterwards"
else
  fail "and the vault is byte-identical afterwards"
fi

# A pin that tracks a branch is a different decision, not a version several
# releases behind — reading it as 0.0.0 would report it as the latter.
printf 'env:\n  ENGINE_REF: main\n' > "${VAULT}/.github/workflows/audit.yml"
upgrade --ref v0.9.1
out_has "audit.yml pins main, which is not a release tag" "a branch pin is reported as a branch pin"
out_lacks "audit.yml pins main, behind" "not as a version behind the target"
rm -rf "${VAULT}/.github"

# --- a target ref with no version in it is refused --------------------------
# The shape check has to come before the existence check, or the answer depends
# on whether `git init` here happened to name the initial branch `main` — which
# is a git default that varies by version and config, and did vary between this
# machine and CI. "main is not a release tag" is true either way, and is the
# more useful of the two answers.
upgrade --ref main
rc=$?
assert_exit 2 "${rc}" "a --ref that is not a release tag is refused"
out_has "must name a release tag" "and says what it wanted instead"
out_lacks "no such ref" "not that the ref does not exist, which is a different problem"

# --- a dirty checkout is refused --------------------------------------------
echo "a hand edit nobody committed" >> "${FIX}/README.md"
sha_before="$(head_sha)"
upgrade --ref v0.9.1
rc=$?
assert_exit 2 "${rc}" "a dirty checkout is refused"
out_has "the checkout is not clean" "and says so"
out_has "README.md" "naming the dirty path"
TESTS_RUN=$((TESTS_RUN + 1))
if [ "$(head_sha)" = "${sha_before}" ]; then
  pass "and nothing was switched"
else
  fail "and nothing was switched"
fi
out_has "MAJOR-091 first line." "and the required action was printed before the refusal"
git -C "${FIX}" checkout -q -- README.md

# --- local commits not in the target ----------------------------------------
git -C "${FIX}" checkout -q -b local-work v0.9.0
echo "local" > "${FIX}/LOCAL.md"
git -C "${FIX}" add LOCAL.md
git -C "${FIX}" commit -q -m "a local commit nobody pushed"
upgrade --ref v0.9.1
rc=$?
assert_exit 2 "${rc}" "a checkout with local commits is refused"
out_has "local commit(s) here are not in v0.9.1" "and says how many"
out_has "a local commit nobody pushed" "naming them"
git -C "${FIX}" checkout -q v0.9.0
git -C "${FIX}" branch -q -D local-work

# --- one clean repo and one drifted ----------------------------------------
REPO_DRIFT="${SANDBOX}/repo-drift"
make_target_repo "${REPO_DRIFT}"
"${FIX}/scripts/render.py" "${REPO_DRIFT}" >/dev/null 2>&1
echo "tampered by hand" >> "${REPO_DRIFT}/.claude/rules/frontend-angular.md"
upgrade --ref v0.9.1
rc=$?
out_has "up to date: $(real "${REPO_OK}")" "a clean registered repo is reported as up to date"
out_has "DRIFT $(real "${REPO_DRIFT}")" "and a drifted one is named"
out_has "fix: ./scripts/render.py $(real "${REPO_DRIFT}")" "with the exact command that fixes it"
out_has "at least 1 of 2 checkable repo(s) need re-rendering" \
  "the preview count is a lower bound, not a total"
out_has "expect all 2 to, once the switch has happened" \
  "because switching stamps a new version into every rendered file"
TESTS_RUN=$((TESTS_RUN + 1))
if [ "${rc}" -ne 0 ]; then
  pass "drift makes the run non-zero"
else
  fail "drift makes the run non-zero" "$(cat "${OUT}")"
fi

# --- no registry, and nothing found either -----------------------------------
# With the registry as the only source this would be undetermined. The scan is a
# second one, so an empty registry plus an empty scan is a determined result —
# stated inside the boundary it holds within, which is what separates it from the
# confident zero that reads as success.
EMPTY_SCAN="${SANDBOX}/nothing-rendered-here"
mkdir -p "${EMPTY_SCAN}"
( XDG_CONFIG_HOME="${SANDBOX}/no-registry" SBW_SCAN_ROOTS="${EMPTY_SCAN}" \
  "${UPGRADE}" --no-fetch --vault "${VAULT}" --ref v0.9.1 >"${OUT}" 2>&1 )
rc=$?
out_has "no repos carry rendered output here, and the registry names none" \
  "no registry and an empty scan is a determined result"
out_lacks "undetermined" "and is not called undetermined"
out_lacks "0 repo" "still never a count of zero repos"
out_lacks "0 of" "and never zero-of-anything either"
out_has "scanned scope: roots=${EMPTY_SCAN}" "with the boundary that result holds within"
TESTS_RUN=$((TESTS_RUN + 1))
if [ "${rc}" -ne 3 ]; then
  pass "and it does not exit 3, which now means something narrower"
else
  fail "and it does not exit 3, which now means something narrower" "$(cat "${OUT}")"
fi

# --- the scan cannot run: the one state still undetermined -------------------
( XDG_CONFIG_HOME="${SANDBOX}/no-registry" \
  SBW_SCAN_ROOTS="${SANDBOX}/no-such-root:${SANDBOX}/nor-this-one" \
  "${UPGRADE}" --no-fetch --vault "${VAULT}" --ref v0.9.1 >"${OUT}" 2>&1 )
rc=$?
assert_exit 3 "${rc}" "no readable scan root: the run exits 3"
out_has "onboarded repo set is undetermined" "and says the set is undetermined"
out_has "will not" "and that it will not claim otherwise"
out_lacks "0 repo" "with no count of zero repos"
out_lacks "0 of" "and no zero-of-anything either"
out_has "scan root skipped: ${SANDBOX}/no-such-root" "naming the root it could not read"
out_lacks "find \"\$HOME\"" "and printing no find command for the reader to run"

# --- registry empty, but the scan finds a repo -------------------------------
# The pre-registry machine. Nothing in the registry, a real onboarded repo on
# disk: reporting "nothing to do" here is the failure this pair of commits is
# about, and it is no longer reachable.
SCAN_ROOT="${SANDBOX}/scan-root"
UNREG="${SCAN_ROOT}/repo-unregistered"
mkdir -p "${SCAN_ROOT}"
make_target_repo "${UNREG}"
# Rendered with its registry pointed elsewhere, so this machine's registry never
# learns about it — which is exactly the state a pre-registry render leaves.
( XDG_CONFIG_HOME="${SANDBOX}/elsewhere" "${FIX}/scripts/render.py" "${UNREG}" >/dev/null 2>&1 )
( XDG_CONFIG_HOME="${SANDBOX}/no-registry" SBW_SCAN_ROOTS="${SCAN_ROOT}" \
  "${UPGRADE}" --no-fetch --vault "${VAULT}" --ref v0.9.1 >"${OUT}" 2>&1 )
rc=$?
out_has "$(real "${UNREG}") (not in the registry)" \
  "an empty registry does not hide a repo the scan found"
out_lacks "undetermined" "and that is a determined answer, not an unknown"
TESTS_RUN=$((TESTS_RUN + 1))
if [ "${rc}" -ne 3 ]; then
  pass "so the run does not exit 3"
else
  fail "so the run does not exit 3" "$(cat "${OUT}")"
fi

# --- a registry whose every entry has gone stale ----------------------------
# Still reported, no longer undetermined: the scan ran, so the set is known — it
# is the registry's contents that are wrong, and that is a finding.
STALE_HOME="${SANDBOX}/stale-registry"
mkdir -p "${STALE_HOME}/second-brain-workflow"
printf '%s\n%s\n' "${SANDBOX}/gone-one" "${SANDBOX}/gone-two" \
  > "${STALE_HOME}/second-brain-workflow/repos"
( XDG_CONFIG_HOME="${STALE_HOME}" SBW_SCAN_ROOTS="${EMPTY_SCAN}" \
  "${UPGRADE}" --no-fetch --vault "${VAULT}" --ref v0.9.1 >"${OUT}" 2>&1 )
rc=$?
out_has "registered, but not there: ${SANDBOX}/gone-one" "a stale entry is named"
out_lacks "undetermined" "and no longer makes the whole set undetermined"
out_lacks "0 repo" "still never a count of zero"
# The summary must not contradict the warnings directly above it. This state
# printed `ok  no repos carry rendered output here, and the registry names none`
# under two warnings naming two, and `ok` is the line a reader takes as the
# verdict. The three assertions above all passed with that line present.
out_lacks "the registry names none" \
  "and never says the registry names none while it names two"
out_has "all 2 registered path(s) are missing or no" \
  "saying instead that nothing could be checked, and why"
TESTS_RUN=$((TESTS_RUN + 1))
if [ "${rc}" = "1" ]; then
  pass "it is a finding, so the run exits 1"
else
  fail "it is a finding, so the run exits 1" "got ${rc}: $(cat "${OUT}")"
fi

# --- an unregistered repo is drift-checked like any other -------------------
echo "tampered by hand" >> "${UNREG}/.claude/rules/frontend-angular.md"
SCAN_ROOTS="${SCAN_ROOT}" upgrade --ref v0.9.1
rc=$?
out_has "DRIFT $(real "${UNREG}") (not in the registry)" \
  "a rendered-but-unregistered repo is drift-checked, and its drift reported"
out_has "fix: ./scripts/render.py $(real "${UNREG}") — re-renders it and registers it" \
  "with the one command that closes both gaps"
out_has "carr(ies) rendered output the registry does not name" \
  "and the unregistered count is called out on its own"
out_has "scanned scope: roots=${SCAN_ROOT}" "the scope line prints in preview"
TESTS_RUN=$((TESTS_RUN + 1))
if [ "${rc}" -ne 0 ]; then
  pass "an unregistered repo is a finding"
else
  fail "an unregistered repo is a finding" "$(cat "${OUT}")"
fi

# --- --yes acts, and still never renders ------------------------------------
drift_before="$(fingerprint "${REPO_DRIFT}")"
unreg_before="$(fingerprint "${UNREG}")"
vault_before="$(fingerprint "${VAULT}")"
SCAN_ROOTS="${SCAN_ROOT}" upgrade --ref v0.9.1 --yes
rc=$?
out_has "checked out v0.9.1" "--yes switches the checkout"
out_has "Summary" "and the run completes despite rewriting its own script mid-run"
TESTS_RUN=$((TESTS_RUN + 1))
if [ "$(git -C "${FIX}" describe --tags --exact-match 2>/dev/null)" = "v0.9.1" ]; then
  pass "leaving the checkout at the target"
else
  fail "leaving the checkout at the target" "$(git -C "${FIX}" describe --all)"
fi
assert_symlink "${SKILLS_A}/mcp-per-project" "and skills re-linked into every configured dir"
TESTS_RUN=$((TESTS_RUN + 1))
if [ "$(fingerprint "${REPO_DRIFT}")" = "${drift_before}" ]; then
  pass "--yes renders nothing: the drifted repo is byte-identical"
else
  fail "--yes renders nothing: the drifted repo is byte-identical" \
    "$(fingerprint "${REPO_DRIFT}")"
fi
TESTS_RUN=$((TESTS_RUN + 1))
if [ "$(fingerprint "${VAULT}")" = "${vault_before}" ]; then
  pass "and the vault is untouched"
else
  fail "and the vault is untouched"
fi
out_has "DRIFT $(real "${REPO_DRIFT}")" "and the drift is still reported, not fixed"
out_has "scanned scope: roots=${SCAN_ROOT}" "the scope line prints under --yes too"
TESTS_RUN=$((TESTS_RUN + 1))
if [ "$(fingerprint "${UNREG}")" = "${unreg_before}" ]; then
  pass "and the unregistered repo is byte-identical too — it is checked, not adopted"
else
  fail "and the unregistered repo is byte-identical too — it is checked, not adopted"
fi
TESTS_RUN=$((TESTS_RUN + 1))
if [ "${rc}" -ne 0 ]; then
  pass "and the run is non-zero while drift remains"
else
  fail "and the run is non-zero while drift remains" "$(cat "${OUT}")"
fi

# --- the printed fix command actually clears the drift ----------------------
# Asserting the string alone would pass just as happily on a command that does
# not run — the failure mode doctor's remediation had.
fix_cmd="$(sed -n "s|^        fix: |cd '${FIX}' \&\& |p" "${OUT}" | head -1)"
TESTS_RUN=$((TESTS_RUN + 1))
if [ -n "${fix_cmd}" ] && ( eval "${fix_cmd}" ) >/dev/null 2>&1; then
  pass "the printed fix command runs"
else
  fail "the printed fix command runs" "${fix_cmd:-no fix command in the output}"
fi
upgrade --ref v0.9.1
out_has "up to date: $(real "${REPO_DRIFT}")" "and clears the drift it was printed for"
# The checkout is at v0.9.1 by now, so this preview targets the version it is
# already on: no switch is pending, and the plain count is the true wording.
#
# repo-ok is the one drifting here, and that is the point made concretely — it
# was rendered at 0.9.0 and the switch stamped 0.9.1 into everything, which is
# exactly what the qualified wording above warns a reader to expect.
out_has "1 of 2 checkable repo(s) need re-rendering, with the commands above." \
  "with no switch pending, the count is stated plainly"
out_lacks "at least 1 of 2" "not hedged as a lower bound, which it no longer is"

# And the clean-plus-nothing-pending cell of the same matrix: every repo current,
# no switch to invalidate it, so the summary carries no qualification at all.
"${FIX}/scripts/render.py" "${REPO_OK}" >/dev/null 2>&1
upgrade --ref v0.9.1
out_has "all 2 checkable repo(s) are up to date" \
  "and a fully current machine says so without qualification"
out_lacks "expect all 2 to need" "having nothing pending to qualify"

# --- make upgrade -----------------------------------------------------------
# MAKELEVEL is what invocation.sh detects, and make exports it into every
# recipe, so these two cases also pin that the remediation names the make form.
at_version 0.9.0
make -C "${FIX}" upgrade VAULT="${VAULT}" REF=v0.9.1 NO_FETCH=1 >"${OUT}" 2>&1 || true
out_has "current 0.9.0 → target v0.9.1" "make upgrade reaches the script with VAULT and REF"
out_has "preview only" "and previews by default"
out_has "Re-run with YES=1 (make upgrade YES=1)" "naming the make form in its remediation"
TESTS_RUN=$((TESTS_RUN + 1))
if [ "$(git -C "${FIX}" describe --tags --exact-match 2>/dev/null)" = "v0.9.0" ]; then
  pass "and changes nothing without YES=1"
else
  fail "and changes nothing without YES=1"
fi

make -C "${FIX}" upgrade VAULT="${VAULT}" REF=v0.9.1 NO_FETCH=1 YES=1 >"${OUT}" 2>&1 || true
out_has "checked out v0.9.1" "make upgrade YES=1 maps to --yes"
TESTS_RUN=$((TESTS_RUN + 1))
if [ "$(git -C "${FIX}" describe --tags --exact-match 2>/dev/null)" = "v0.9.1" ]; then
  pass "and switches the checkout"
else
  fail "and switches the checkout"
fi

# --- the target resolves to the newest tag when none is named ---------------
at_version 0.9.0
upgrade
out_has "target v0.10.0 (newest tag in this checkout)" "with no --ref, the newest tag is the target"
out_has "MAJOR-0100" "and every Major entry up to it is in range"
out_has "MAJOR-091 first line." "including the ones in between"

# --- a failing step reports and the run still finishes ----------------------
# A hand-maintained skill directory makes sync-skills.sh exit 1. Under `set -e`
# and pipefail that would end the run inside the switch, skipping every check
# that would say what state the machine had been left in — the exact way doctor
# used to stop at its first finding.
at_version 0.9.0
rm -f "${SKILLS_A}/mcp-per-project"
mkdir -p "${SKILLS_A}/mcp-per-project"
upgrade --ref v0.9.1 --yes
out_has "sync-skills.sh exited 1" "a failing switch step is reported, not fatal"
out_has "real directory, not a link" "with the tool's own output kept"
out_has "Onboarded repos" "and the checks after it still run"
out_has "Summary" "and the run still summarises"
rmdir "${SKILLS_A}/mcp-per-project"

finish
