#!/usr/bin/env bash
# The rendered-repo scan, and doctor comparing it against the registry.
#
# The registry alone could only report one direction — registered but gone. One
# render on a machine with twelve pre-registry repos therefore read as complete
# coverage. The scan is the second source, and "rendered but not registered" is
# the direction that needed it.
#
# Every root here points inside the sandbox, and the last assertion in this file
# fails if any path outside it ever appears in scan output: a test that walked
# the developer's real home would be slow, machine-dependent, and would report
# their actual repos as findings.
# shellcheck source=tests/lib.sh
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
setup_sandbox

# shellcheck source=scripts/lib/registry.sh
. "${ENGINE}/scripts/lib/registry.sh"

DOCTOR="${ENGINE}/scripts/doctor.sh"
export XDG_CONFIG_HOME="${SANDBOX}/config-home"
REGISTRY="${XDG_CONFIG_HOME}/second-brain-workflow/repos"
mkdir -p "${XDG_CONFIG_HOME}/second-brain-workflow"

# Skill parity and orphan checks are machine-wide; two empty dirs keep them
# trivially clean so only the registry findings vary.
EMPTY1="${SANDBOX}/skills-1"
EMPTY2="${SANDBOX}/skills-2"
mkdir -p "${EMPTY1}" "${EMPTY2}"
export SKILLS_DIRS="${EMPTY1}:${EMPTY2}"

OUT="${SANDBOX}/out"
out_has() {
  TESTS_RUN=$((TESTS_RUN + 1))
  if grep -qF -- "$1" "${OUT}"; then pass "$2"; else fail "$2" "$(cat "${OUT}")"; fi
}
out_lacks() {
  TESTS_RUN=$((TESTS_RUN + 1))
  if grep -qF -- "$1" "${OUT}"; then fail "$2" "$(cat "${OUT}")"; else pass "$2"; fi
}

# Realpath from the start: the scan emits realpaths, and on macOS $TMPDIR
# resolves /var -> /private/var, so a fixture built under the unresolved path
# could never string-match what the scan prints.
BASE="$(cd "${SANDBOX}" && pwd -P)"
SCAN="${BASE}/scan-root"

scan() {
  SBW_SCAN_ROOTS="$1"
  SBW_SCAN_DEPTH="${2:-5}"
  sbw_scan_rendered_repos
}
doctor() {
  local roots="$1" depth="${2:-5}"
  SBW_SCAN_ROOTS="${roots}" SBW_SCAN_DEPTH="${depth}" \
    "${DOCTOR}" --vault "${VAULT}" >"${OUT}" 2>&1
}
found() { printf '%s\n' "$1" | grep -qxF "$2"; }

# --- fixtures ---------------------------------------------------------------
# One directory per way a repo can and cannot announce itself.
rendered_sbw()    { mkdir -p "$1" && echo "0.9.1" > "$1/.sbw-version"; }
rendered_agents() { mkdir -p "$1" && printf '<!-- %sabc123 from AGENTS.md -->\n\nbody\n' \
                      "${SBW_RENDER_MARKER}" > "$1/AGENTS.md"; }
rendered_claude() { mkdir -p "$1" && printf '<!-- %sabc123 from AGENTS.md -->\n\n@AGENTS.md\n' \
                      "${SBW_RENDER_MARKER}" > "$1/CLAUDE.md"; }
plain_agents()    { mkdir -p "$1" && printf '# Engineering Standards\n\nHand written.\n' > "$1/AGENTS.md"; }

rendered_sbw    "${SCAN}/repo-sbw-only"
rendered_agents "${SCAN}/repo-agents-marker"
rendered_claude "${SCAN}/repo-claude-marker"
plain_agents    "${SCAN}/dir-hand-written"
rendered_sbw    "${SCAN}/node_modules/pkg/repo-vendored"
rendered_sbw    "${SCAN}/vaults/second-brain"
rendered_sbw    "${SCAN}/nested/repo-one-deeper"
rendered_sbw    "${SCAN}/repo with spaces"

VAULT="${SANDBOX}/vault"
"${ENGINE}/scripts/init-vault.sh" --path "${VAULT}" --id work \
  --remote "git@example.com:me/wb.git" >/dev/null 2>&1

echo "rendered-repo scan"

# --- 1. the coverage bug this exists for ------------------------------------
# .sbw-version and no AGENTS.md at all. The find command this replaces matched
# AGENTS.md carrying the marker and nothing else, so this repo was invisible to
# the remediation while every other registry check saw it.
out_scan="$(scan "${SCAN}")"
TESTS_RUN=$((TESTS_RUN + 1))
if found "${out_scan}" "${SCAN}/repo-sbw-only"; then
  pass "a repo with .sbw-version and no AGENTS.md is found"
else
  fail "a repo with .sbw-version and no AGENTS.md is found" "${out_scan}"
fi

# --- 2. the marker in AGENTS.md, no .sbw-version ----------------------------
TESTS_RUN=$((TESTS_RUN + 1))
if found "${out_scan}" "${SCAN}/repo-agents-marker"; then
  pass "a repo whose AGENTS.md carries the marker is found"
else
  fail "a repo whose AGENTS.md carries the marker is found" "${out_scan}"
fi
TESTS_RUN=$((TESTS_RUN + 1))
if found "${out_scan}" "${SCAN}/repo-claude-marker"; then
  pass "and one whose CLAUDE.md carries it"
else
  fail "and one whose CLAUDE.md carries it" "${out_scan}"
fi

# --- 3. an AGENTS.md nobody generated ---------------------------------------
# The real-world shape: render.py leaves a hand-written AGENTS.md alone by
# design, so its presence says nothing about whether we rendered here.
TESTS_RUN=$((TESTS_RUN + 1))
if found "${out_scan}" "${SCAN}/dir-hand-written"; then
  fail "a hand-written AGENTS.md is not a rendered repo" "${out_scan}"
else
  pass "a hand-written AGENTS.md is not a rendered repo"
fi

# --- 4. prunes --------------------------------------------------------------
TESTS_RUN=$((TESTS_RUN + 1))
if found "${out_scan}" "${SCAN}/node_modules/pkg/repo-vendored"; then
  fail "a repo under node_modules is not found" "${out_scan}"
else
  pass "a repo under node_modules is not found"
fi
TESTS_RUN=$((TESTS_RUN + 1))
if found "${out_scan}" "${SCAN}/vaults/second-brain"; then
  fail "and neither is one under a vaults directory" "${out_scan}"
else
  pass "and neither is one under a vaults directory"
fi

# --- 5. depth, and the scope line that explains it --------------------------
# Depth is what find is given, so it counts the marker *file*: at depth 2 a repo
# directly under the root qualifies and one a level further down does not.
shallow="$(scan "${SCAN}" 2)"
TESTS_RUN=$((TESTS_RUN + 1))
if found "${shallow}" "${SCAN}/repo-sbw-only" &&
   ! found "${shallow}" "${SCAN}/nested/repo-one-deeper"; then
  pass "a repo one level deeper than the depth limit is not found"
else
  fail "a repo one level deeper than the depth limit is not found" "${shallow}"
fi
SBW_SCAN_ROOTS="${SCAN}" SBW_SCAN_DEPTH=2
TESTS_RUN=$((TESTS_RUN + 1))
case "$(sbw_scan_scope_line)" in
  *"depth=2"*) pass "and the scope line states the depth that excluded it" ;;
  *) fail "and the scope line states the depth that excluded it" "$(sbw_scan_scope_line)" ;;
esac

# --- 6. overlapping roots ---------------------------------------------------
# Not the same realpath, so deduplicating roots is not enough — the results are
# what get deduplicated.
overlap="$(scan "${SCAN}:${SCAN}/nested" 5)"
TESTS_RUN=$((TESTS_RUN + 1))
n="$(printf '%s\n' "${overlap}" | grep -cxF "${SCAN}/nested/repo-one-deeper")"
if [ "${n}" = "1" ]; then
  pass "two overlapping roots yield each repo once"
else
  fail "two overlapping roots yield each repo once" "counted ${n}: ${overlap}"
fi

# --- 7. a root that is not there --------------------------------------------
doctor "${SANDBOX}/no-such-root:${SCAN}"
out_has "scan root skipped: ${SANDBOX}/no-such-root — no such directory" \
  "a root that does not exist is named"
out_has "${SCAN}/repo-sbw-only" "and the roots that do exist are still scanned"

# --- 8. no usable root at all -----------------------------------------------
doctor "${SANDBOX}/no-such-root:${SANDBOX}/nor-this-one"
out_has "onboarded repo set is undetermined" \
  "every root missing: the set is undetermined again"
out_lacks "onboarded repo(s) registered" "and no count of registered repos is printed"
out_lacks "no repos carry rendered output" "nor a determined-empty claim"
out_has "scanned scope:" "and the scope is still stated"

# --- 9. rendered but not registered -----------------------------------------
# One of three in the registry. The other two are the finding the registry alone
# could never produce.
printf '%s\n' "${SCAN}/repo-sbw-only" > "${REGISTRY}"
doctor "${SCAN}"
out_has "rendered but not registered: ${SCAN}/repo-agents-marker" \
  "a rendered repo the registry does not name is reported"
out_has "rendered but not registered: ${SCAN}/repo-claude-marker" \
  "each one of them, by name"
out_has "register it by rendering again: ./scripts/render.py ${SCAN}/repo-agents-marker" \
  "with the command that registers it"
out_has "or leave it, if that repo is abandoned" \
  "and permission to ignore one that is abandoned"
out_lacks "rendered but not registered: ${SCAN}/repo-sbw-only" \
  "and the registered one is not among them"
TESTS_RUN=$((TESTS_RUN + 1))
case "$(grep -c "warn  rendered but not registered" "${OUT}")" in
  4) pass "reported as warnings, one per repo" ;;
  *) fail "reported as warnings, one per repo" "$(cat "${OUT}")" ;;
esac

# --- 10. the two sources agree ----------------------------------------------
# Every in-scope fixture, so the two sets are identical: the pruned and too-deep
# ones are outside the scan by design and would be reported as registered-but-
# missing if listed here, which is a different assertion.
{ printf '%s\n' "${SCAN}/repo-sbw-only" "${SCAN}/repo-agents-marker" \
    "${SCAN}/repo-claude-marker" "${SCAN}/repo with spaces" \
    "${SCAN}/nested/repo-one-deeper"; } > "${REGISTRY}"
doctor "${SCAN}"
rc=$?
out_has "5 onboarded repo(s) registered, all still rendered, and none unregistered" \
  "registry and scan agreeing reports ok"
out_has "scanned scope: roots=${SCAN} depth=5" "with the scope line present on a clean run"
assert_exit 0 "${rc}" "and the exit code is unaffected"

# --- 11. determined empty, which is not undetermined ------------------------
EMPTY_ROOT="${BASE}/empty-root"
mkdir -p "${EMPTY_ROOT}"
: > "${REGISTRY}"
doctor "${EMPTY_ROOT}"
rc=$?
out_has "no repos carry rendered output here, and the registry names none" \
  "an empty registry and an empty scan is a determined result"
out_lacks "undetermined" "and is never called undetermined"
out_has "scanned scope: roots=${EMPTY_ROOT} depth=5" "with the boundary it holds within"
out_has "a repo outside it" "said explicitly, so it cannot read as 'no repos exist'"
assert_exit 0 "${rc}" "and it is not a finding"

# --- 12. paths with spaces --------------------------------------------------
printf '%s\n' "${SCAN}/repo-sbw-only" > "${REGISTRY}"
doctor "${SCAN}"
out_has "rendered but not registered: ${SCAN}/repo with spaces" \
  "a path with spaces survives the scan and the report"
TESTS_RUN=$((TESTS_RUN + 1))
if found "$(scan "${SCAN}")" "${SCAN}/repo with spaces"; then
  pass "and is emitted as one path, not split on the space"
else
  fail "and is emitted as one path, not split on the space" "$(scan "${SCAN}")"
fi

# --- 13. the scan and the per-entry check cannot drift apart ----------------
# For every fixture inside the scanned scope, "the scan found it" and
# "sbw_registry_marker_present says yes" must be the same answer. The pruned and
# too-deep fixtures are excluded on purpose: those are scope decisions, not
# disagreements about what a rendered repo looks like, and 4 and 5 cover them.
in_scope="repo-sbw-only
repo-agents-marker
repo-claude-marker
dir-hand-written
repo with spaces"
out_scan="$(scan "${SCAN}")"
agree=1
while IFS= read -r name; do
  [ -n "${name}" ] || continue
  in_scan=no
  found "${out_scan}" "${SCAN}/${name}" && in_scan=yes
  by_func=no
  sbw_registry_marker_present "${SCAN}/${name}" && by_func=yes
  if [ "${in_scan}" != "${by_func}" ]; then
    agree=0
    echo "       ${name}: scan=${in_scan} marker_present=${by_func}"
  fi
done <<EOF
${in_scope}
EOF
TESTS_RUN=$((TESTS_RUN + 1))
if [ "${agree}" -eq 1 ]; then
  pass "the scan agrees with sbw_registry_marker_present on every in-scope fixture"
else
  fail "the scan agrees with sbw_registry_marker_present on every in-scope fixture"
fi

# --- 14. --help still prints the whole header block -------------------------
# The range is a line count, and it has silently truncated twice already.
"${DOCTOR}" --help > "${OUT}" 2>&1
out_has "every repo on this machine that carries rendered output is in the registry" \
  "--help lists the new check"
out_has "isn't finished yet\" (1) is what a reader mid-setup needed." \
  "and still reaches the last line of the header, so the sed range has not rotted"
out_lacks "set -euo pipefail" "without spilling past it into code"

# --- the two spellings of each default agree --------------------------------
# lib/config.sh is authoritative and lib/registry.sh carries a fallback for being
# sourced without ds_config_load. Two copies of a default is exactly the drift
# the MARKER parity assertion exists for.
TESTS_RUN=$((TESTS_RUN + 1))
# shellcheck disable=SC2016  # sed and grep patterns matching the literal source
# text of both files; expanding any of it here would defeat the comparison.
cfg_depth="$(sed -n 's/^  \[ -n "${SBW_SCAN_DEPTH+set}" \] || SBW_SCAN_DEPTH="\(.*\)"$/\1/p' \
  "${ENGINE}/scripts/lib/config.sh")"
lib_depth="$(sed -n 's/^SBW_SCAN_DEPTH_FALLBACK="\(.*\)"$/\1/p' "${ENGINE}/scripts/lib/registry.sh")"
if [ -n "${cfg_depth}" ] && [ "${cfg_depth}" = "${lib_depth}" ]; then
  pass "the default depth is the same in config.sh and registry.sh (${cfg_depth})"
else
  fail "the default depth is the same in config.sh and registry.sh" \
    "config.sh='${cfg_depth}' registry.sh='${lib_depth}'"
fi
TESTS_RUN=$((TESTS_RUN + 1))
# shellcheck disable=SC2016  # as above: literal source text, deliberately unexpanded.
if grep -q 'SBW_SCAN_ROOTS="\$HOME"' "${ENGINE}/scripts/lib/config.sh" &&
   grep -q 'SBW_SCAN_ROOTS_FALLBACK="${HOME}"' "${ENGINE}/scripts/lib/registry.sh"; then
  pass "and both default the roots to \$HOME"
else
  fail "and both default the roots to \$HOME"
fi

# --- nothing here ever left the sandbox ------------------------------------
# Asserted last, over everything the scan produced above: a test that walked the
# developer's real home would be slow, machine-dependent, and would report their
# actual repos as findings.
TESTS_RUN=$((TESTS_RUN + 1))
stray="$(scan "${SCAN}" | grep -v "^${BASE}/" || true)"
if [ -z "${stray}" ]; then
  pass "no scanned path lies outside the sandbox"
else
  fail "no scanned path lies outside the sandbox" "${stray}"
fi

finish
