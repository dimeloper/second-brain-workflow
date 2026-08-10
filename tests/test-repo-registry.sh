#!/usr/bin/env bash
# The registry of repos this machine has rendered into: render.py records them,
# doctor reports on them, and neither guesses.
#
# XDG_CONFIG_HOME is pointed inside the sandbox, so nothing here can reach the
# developer's real ${XDG_CONFIG_HOME:-~/.config}/second-brain-workflow/repos —
# a test that appended to that file would quietly enrol the machine's own repos
# in whatever it was asserting.
# shellcheck source=tests/lib.sh
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
setup_sandbox

export XDG_CONFIG_HOME="${SANDBOX}/config-home"
REGISTRY="${XDG_CONFIG_HOME}/second-brain-workflow/repos"

# Same isolation from ${ENGINE}/rules as test-render.sh: those may be personal
# content, or absent in the public engine repo.
RULES_FIXTURES="${FIXTURES}/rules"
render() { "${ENGINE}/scripts/render.py" --rules-dir "${RULES_FIXTURES}" "$@"; }
DOCTOR="${ENGINE}/scripts/doctor.sh"

# A doctor run needs a vault path; these cases are about the registry, so it's a
# plain directory (reported as "not a repo yet", a warning) rather than a real
# vault the fixture would then have to maintain.
VAULT="${SANDBOX}/vault"
mkdir -p "${VAULT}"

OUT="${SANDBOX}/out"
out_has() {
  TESTS_RUN=$((TESTS_RUN + 1))
  if grep -qF -- "$1" "${OUT}"; then pass "$2"; else fail "$2" "$(cat "${OUT}")"; fi
}
out_lacks() {
  TESTS_RUN=$((TESTS_RUN + 1))
  if grep -qF -- "$1" "${OUT}"; then fail "$2" "$(cat "${OUT}")"; else pass "$2"; fi
}
# What render.py will have stored: realpath, so on macOS the sandbox's
# /var/folders/... becomes /private/var/folders/... — comparing against the
# unresolved path is the failure tests/lib.sh's TMPDIR note describes.
real() { (cd "$1" && pwd -P); }
entries() { grep -cve '^[[:space:]]*$' -e '^[[:space:]]*#' "${REGISTRY}" 2>/dev/null || true; }
assert_entries() {
  local want="$1" got
  got="$(entries)"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ "${got}" = "${want}" ]; then
    pass "$2"
  else
    fail "$2" "want ${want} path(s), got ${got}: $(tr '\n' ' ' < "${REGISTRY}")"
  fi
}

echo "repo registry"

# --- neither --check nor --dry-run records anything --------------------------
# Same contract .sbw-version already has, asserted before any write so an
# existing registry can't make this pass by accident.
REPO="${SANDBOX}/repo"
make_target_repo "${REPO}"
render "${REPO}" --check >/dev/null 2>&1
assert_no_file "${REGISTRY}" "--check records nothing"
render "${REPO}" --dry-run >/dev/null 2>&1
assert_no_file "${REGISTRY}" "--dry-run records nothing"

# --- a successful render records the target ----------------------------------
render "${REPO}" >/dev/null 2>&1
assert_exit 0 $? "render succeeds"
assert_file "${REGISTRY}" "a successful render creates the registry"
assert_contains "${REGISTRY}" "^$(real "${REPO}")\$" "registry holds the target's realpath"

# --- idempotent -------------------------------------------------------------
render "${REPO}" >/dev/null 2>&1
render "${REPO}" >/dev/null 2>&1
assert_entries 1 "rendering the same repo three times leaves one line"

# --- a second repo, sorted --------------------------------------------------
REPO_A="${SANDBOX}/aaa-repo"
make_target_repo "${REPO_A}"
render "${REPO_A}" >/dev/null 2>&1
assert_entries 2 "a second target adds a second line"
TESTS_RUN=$((TESTS_RUN + 1))
if [ "$(cat "${REGISTRY}")" = "$(sort "${REGISTRY}")" ]; then
  pass "the registry is sorted, whatever order repos were rendered in"
else
  fail "the registry is sorted, whatever order repos were rendered in" "$(cat "${REGISTRY}")"
fi

# --- a symlinked parent is the same repo ------------------------------------
# The path someone types is not the path the repo lives at, and a registry that
# recorded both would report one repo as two — then have half of them go stale
# the moment the symlink moved.
mkdir -p "${SANDBOX}/link-parent"
ln -s "${REPO}" "${SANDBOX}/link-parent/repo-by-link"
before="$(entries)"
render "${SANDBOX}/link-parent/repo-by-link" >/dev/null 2>&1
assert_entries "${before}" "a target reached through a symlink adds no second line"
assert_not_contains "${REGISTRY}" "link-parent" "and is stored as the real path, not the link"

# --- an unwritable config dir does not fail the render ----------------------
# Rendering is the job. But it says so on stderr: silence here is what produces
# an undetermined set later with nothing left to explain it.
if [ "$(id -u)" = "0" ]; then
  echo "  skip  unwritable config dir — running as root, where the mode is ignored"
else
  RO_HOME="${SANDBOX}/ro-config-home"
  mkdir -p "${RO_HOME}"
  chmod 500 "${RO_HOME}"
  REPO_RO="${SANDBOX}/repo-ro"
  make_target_repo "${REPO_RO}"
  XDG_CONFIG_HOME="${RO_HOME}" render "${REPO_RO}" >"${OUT}" 2>&1
  rc=$?
  assert_exit 0 "${rc}" "an unwritable config dir still exits 0"
  out_has "${RO_HOME}/second-brain-workflow/repos" "and names the registry it could not write"
  out_has "Permission denied" "and names the reason"
  assert_no_file "${RO_HOME}/second-brain-workflow/repos" "and wrote no registry"
  chmod 700 "${RO_HOME}"
fi

# --- the marker doctor looks for is the one render.py writes -----------------
# scripts/lib/registry.sh keeps its own copy of render.py's MARKER, so a repo
# that has stopped carrying rendered output can be told from one that never
# did. Two copies of a string is how a check silently stops matching anything.
TESTS_RUN=$((TESTS_RUN + 1))
py_marker="$(sed -n 's/^MARKER = "\(.*\)"$/\1/p' "${ENGINE}/scripts/render.py")"
sh_marker="$(sed -n 's/^SBW_RENDER_MARKER="\(.*\)"$/\1/p' "${ENGINE}/scripts/lib/registry.sh")"
if [ -n "${py_marker}" ] && [ "${py_marker}" = "${sh_marker}" ]; then
  pass "registry.sh's provenance marker matches render.py's"
else
  fail "registry.sh's provenance marker matches render.py's" \
    "render.py='${py_marker}' registry.sh='${sh_marker}'"
fi

# --- doctor: a registered repo that is no longer there ----------------------
GONE="${SANDBOX}/deleted-repo"
make_target_repo "${GONE}"
render "${GONE}" >/dev/null 2>&1
rm -rf "${GONE}"
cp "${REGISTRY}" "${SANDBOX}/registry.before"
"${DOCTOR}" --vault "${VAULT}" >"${OUT}" 2>&1
rc=$?
out_has "$(real "${SANDBOX}")/deleted-repo" "doctor names a registered repo that has gone missing"
out_has "warn  registered repo is not there" "and reports it as a warning"
TESTS_RUN=$((TESTS_RUN + 1))
if [ "${rc}" -ne 0 ]; then
  pass "and the run stays non-zero"
else
  fail "and the run stays non-zero" "$(cat "${OUT}")"
fi

# --- doctor prunes nothing --------------------------------------------------
# A repo on an unmounted volume is not a deleted repo, and deleting the only
# record of it is not a repair.
TESTS_RUN=$((TESTS_RUN + 1))
if cmp -s "${SANDBOX}/registry.before" "${REGISTRY}"; then
  pass "doctor leaves the registry byte-identical"
else
  fail "doctor leaves the registry byte-identical" "$(diff "${SANDBOX}/registry.before" "${REGISTRY}" || true)"
fi

# --- doctor: registered, present, but no longer rendered --------------------
STRIPPED="${SANDBOX}/stripped-repo"
make_target_repo "${STRIPPED}"
render "${STRIPPED}" >/dev/null 2>&1
rm -f "${STRIPPED}/.sbw-version" "${STRIPPED}/AGENTS.md" "${STRIPPED}/CLAUDE.md"
"${DOCTOR}" --vault "${VAULT}" >"${OUT}" 2>&1 || true
out_has "carries no rendered output any more" "doctor reports a repo whose rendered output is gone"
out_has "$(real "${SANDBOX}")/stripped-repo" "and names it"

# --- doctor: all present ----------------------------------------------------
CLEAN_HOME="${SANDBOX}/clean-config-home"
CLEAN_REPO="${SANDBOX}/clean-repo"
make_target_repo "${CLEAN_REPO}"
XDG_CONFIG_HOME="${CLEAN_HOME}" render "${CLEAN_REPO}" >/dev/null 2>&1
XDG_CONFIG_HOME="${CLEAN_HOME}" "${DOCTOR}" --vault "${VAULT}" >"${OUT}" 2>&1 || true
out_has "1 onboarded repo(s) registered, all still rendered" \
  "doctor reports a registry whose entries are all present"

# --- doctor: no registry, and nothing found either --------------------------
# With the registry as the only source this would be undetermined: an empty
# registry cannot be told from one never written. The scan is a second source, so
# it is a determined result instead — stated with the boundary it holds within,
# which is what separates it from a confident zero.
# tests/test-registry-scan.sh owns the scan's own cases.
EMPTY_HOME="${SANDBOX}/empty-config-home"
EMPTY_SCAN="${SANDBOX}/nothing-rendered-here"
mkdir -p "${EMPTY_SCAN}"
XDG_CONFIG_HOME="${EMPTY_HOME}" SBW_SCAN_ROOTS="${EMPTY_SCAN}" \
  "${DOCTOR}" --vault "${VAULT}" >"${OUT}" 2>&1
doctor_rc=$?
out_has "no repos carry rendered output here, and the registry names none" \
  "no registry and an empty scan: a determined result, not an unknown"
out_lacks "undetermined" "so the word undetermined does not appear"
out_lacks "0 onboarded repo" "and still never a count of zero"
out_has "scanned scope: roots=${EMPTY_SCAN}" "with the scope that result holds within"
assert_no_file "${EMPTY_HOME}/second-brain-workflow/repos" "and doctor creates no registry of its own"

# --- doctor: no registry, but repos are there -------------------------------
# The pre-registry machine. What used to be a printed find command for the
# reader to run is now the check itself, so the repos are named rather than
# described — including the decoy under a pruned directory that must not be.
SEED_HOME="${SANDBOX}/seed-home"
mkdir -p "${SEED_HOME}/onboarded" "${SEED_HOME}/node_modules/decoy"
render "${SEED_HOME}/onboarded" >/dev/null 2>&1
cp "${SEED_HOME}/onboarded/AGENTS.md" "${SEED_HOME}/node_modules/decoy/AGENTS.md"
XDG_CONFIG_HOME="${EMPTY_HOME}" SBW_SCAN_ROOTS="${SEED_HOME}" \
  "${DOCTOR}" --vault "${VAULT}" >"${OUT}" 2>&1
doctor_rc=$?
out_has "rendered but not registered: $(real "${SEED_HOME}")/onboarded" \
  "a repo onboarded before the registry existed is named"
out_has "./scripts/render.py $(real "${SEED_HOME}")/onboarded" \
  "with the command that registers it"
out_lacks "node_modules" "and the decoy under a pruned directory is not reported"
TESTS_RUN=$((TESTS_RUN + 1))
if [ "${doctor_rc}" -ne 0 ]; then
  pass "and the run stays non-zero while it is unregistered"
else
  fail "and the run stays non-zero while it is unregistered" "$(cat "${OUT}")"
fi

# --- doctor: a registry that exists but lists nothing -----------------------
# Comments and blank lines are ignored on read, so a file holding only those is
# the same state as no file at all — which is now answerable rather than unknown.
ANNOTATED="${SANDBOX}/annotated-config-home"
mkdir -p "${ANNOTATED}/second-brain-workflow"
printf '# nothing yet\n\n   \n' > "${ANNOTATED}/second-brain-workflow/repos"
XDG_CONFIG_HOME="${ANNOTATED}" SBW_SCAN_ROOTS="${EMPTY_SCAN}" \
  "${DOCTOR}" --vault "${VAULT}" >"${OUT}" 2>&1 || true
out_has "no repos carry rendered output here" \
  "a registry of only comments reads the same as no registry"
out_lacks "undetermined" "and is equally not undetermined"

# --- comments and blank lines are ignored, not counted ----------------------
printf '# machine registry\n\n%s\n' "$(real "${CLEAN_REPO}")" \
  > "${ANNOTATED}/second-brain-workflow/repos"
XDG_CONFIG_HOME="${ANNOTATED}" "${DOCTOR}" --vault "${VAULT}" >"${OUT}" 2>&1 || true
out_has "1 onboarded repo(s) registered" "a hand-annotated registry counts only its paths"

finish
