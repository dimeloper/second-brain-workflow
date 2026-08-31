#!/usr/bin/env bash
# project-for.py: the read path for projects/ — what the vault already knows
# about this repo's initiative.
#
# Fixtures only. A real vault would make the output depend on whoever ran it,
# and this asserts on specific project names.
# shellcheck source=tests/lib.sh
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
setup_sandbox

PF="${ENGINE}/scripts/project-for.py"

echo "project-for.py"

# --- fixture vault ----------------------------------------------------------
V="${SANDBOX}/vault"
mkdir -p "${V}/projects"

project() {  # project <slug> <status> <repos-json>
  mkdir -p "${V}/projects/$1/features"
  cat > "${V}/projects/$1/_project.md" <<EOF
---
kind: project
status: $2
started: 2026-07-01
last-reviewed: 2026-08-01
repos: $3
tags: []
---

# $1 — the overview

## TL;DR

The stable half of $1.

## Constraints

- One constraint, which is the sort of thing only the overview carries.
EOF
}

feature() {  # feature <project> <slug> <status> <repos-json> <outcome>
  cat > "${V}/projects/$1/features/$2.md" <<EOF
---
kind: feature
status: $3
started: 2026-07-01
last-reviewed: 2026-08-01
outcome: $5
repos: $4
tags: []
---

# $2 — one slice

## State

Where $2 stands right now.

## Decisions

- **2026-07-02** — the expensive half, which must stay in the file.
EOF
}

project alpha active '["target-repo"]'
feature alpha first-slice active '["target-repo"]' ''
feature alpha second-slice closed '["target-repo"]' 'done'

# An initiative in somebody else's repo, one slice of which touches ours.
project beta active '["other-repo"]'
feature beta ours active '["target-repo"]' ''
feature beta theirs active '["other-repo"]' ''

# Names neither: must not appear at all.
project gamma paused '["unrelated"]'
feature gamma nope active '["unrelated"]' ''

# --- fixture repos ----------------------------------------------------------
REPO="${SANDBOX}/target-repo"
mkdir -p "${REPO}"
: > "${REPO}/README.md"

out="$("${PF}" --repo "${REPO}" --vault "${V}" 2>&1)"
assert_exit 0 $? "reports cleanly against a fixture vault and repo"

# --- matching is on repos:, never on the stack -------------------------------
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"PROJECT  alpha"*) pass "a project whose overview names the repo is printed" ;;
  *) fail "a project whose overview names the repo is printed" "${out}" ;;
esac
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *gamma*) fail "a project naming no matching repo does not appear" "${out}" ;;
  *) pass "a project naming no matching repo does not appear" ;;
esac

# --- the stable half first, whole -------------------------------------------
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"The stable half of alpha"*"## Constraints"*)
    pass "the overview is printed whole, not excerpted" ;;
  *) fail "the overview is printed whole, not excerpted" "${out}" ;;
esac
# The order is the point of the tool: a session that reads only the first screen
# must have read the half that changes least.
overview_at="$(printf '%s\n' "${out}" | grep -n "The stable half of alpha" | head -1 | cut -d: -f1)"
feature_at="$(printf '%s\n' "${out}" | grep -n "FEATURE  first-slice" | head -1 | cut -d: -f1)"
TESTS_RUN=$((TESTS_RUN + 1))
if [ -n "${overview_at}" ] && [ -n "${feature_at}" ] && [ "${overview_at}" -lt "${feature_at}" ]; then
  pass "the overview comes before the features"
else
  fail "the overview comes before the features" "overview@${overview_at:-none} feature@${feature_at:-none}"
fi

# --- a feature contributes its State and keeps its decision log in the file --
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"Where first-slice stands right now"*) pass "a feature's ## State section is printed" ;;
  *) fail "a feature's ## State section is printed" "${out}" ;;
esac
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"the expensive half, which must stay in the file"*)
    fail "the decision log stays in the file rather than being printed" "${out}" ;;
  *) pass "the decision log stays in the file rather than being printed" ;;
esac
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"projects/alpha/features/first-slice.md"*)
    pass "each file is named by its vault-relative path, so it can be opened" ;;
  *) fail "each file is named by its vault-relative path" "${out}" ;;
esac
# `closed` alone says the work left the list and nothing about how, the same gap
# a bare `- [x]` leaves on a follow-up.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"status:   closed (done)"*) pass "a closed feature carries its outcome beside the status" ;;
  *) fail "a closed feature carries its outcome beside the status" "${out}" ;;
esac

# --- context/ is surfaced, as paths, between overview and features ----------
mkdir -p "${V}/projects/alpha/context"
cat > "${V}/projects/alpha/context/audience.md" <<'EOF'
# audience
Who alpha is for. This body must never be printed.
EOF
cat > "${V}/projects/alpha/context/pricing.md" <<'EOF'
# pricing
An arbitrary topic — the filename set is not fixed.
EOF
out_ctx="$("${PF}" --repo "${REPO}" --vault "${V}" 2>&1)"
assert_exit 0 $? "a project with context/ still reports cleanly"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_ctx}" in
  *CONTEXT*audience*projects/alpha/context/audience.md*)
    pass "context files are listed with their vault-relative paths" ;;
  *) fail "context files are listed with their paths" "${out_ctx}" ;;
esac
# Not a hardcoded audience|voice|brand set: a new topic needs no code change.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_ctx}" in
  *pricing*) pass "any .md under context/ appears, not a fixed filename set" ;;
  *) fail "any .md under context/ appears" "${out_ctx}" ;;
esac
# Paths, not contents — the overview is short and stable, context is neither.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_ctx}" in
  *"must never be printed"*) fail "context bodies are never printed" "${out_ctx}" ;;
  *) pass "context bodies are never printed, only paths" ;;
esac
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_ctx}" in
  *"2 context file(s)"*) pass "the summary line counts them" ;;
  *) fail "the summary line counts them" "${out_ctx}" ;;
esac
# Order is the point: stable half, then what does not change per session, then
# the work in flight.
ctx_at="$(printf '%s\n' "${out_ctx}" | grep -n "^CONTEXT" | head -1 | cut -d: -f1)"
ov_at="$(printf '%s\n' "${out_ctx}" | grep -n "The stable half of alpha" | head -1 | cut -d: -f1)"
feat_at="$(printf '%s\n' "${out_ctx}" | grep -n "FEATURE  first-slice" | head -1 | cut -d: -f1)"
TESTS_RUN=$((TESTS_RUN + 1))
if [ -n "${ctx_at}" ] && [ "${ov_at}" -lt "${ctx_at}" ] && [ "${ctx_at}" -lt "${feat_at}" ]; then
  pass "context sits between the overview and the features"
else
  fail "context sits between the overview and the features" \
    "overview@${ov_at:-none} context@${ctx_at:-none} feature@${feat_at:-none}"
fi
# Silence, not "none found": most projects have no context/, and a line on
# every run teaches a reader to skim past the block on the ones that do.
TESTS_RUN=$((TESTS_RUN + 1))
case "$("${PF}" --repo "${REPO}" --vault "${V}" 2>&1 | sed -n "/PROJECT  beta/,/^====/p")" in
  *CONTEXT*) fail "a project with no context/ prints no block at all" "beta printed one" ;;
  *) pass "a project with no context/ prints no block at all" ;;
esac
rm -rf "${V}/projects/alpha/context"

# --- a feature-only match does not drag in the rest of the initiative --------
# Printing every sibling would hand a session context for work in repos it is
# not in, which is the failure mode a context tool can least afford.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"FEATURE  ours"*) pass "a feature naming this repo brings its project in" ;;
  *) fail "a feature naming this repo brings its project in" "${out}" ;;
esac
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"FEATURE  theirs"*)
    fail "a sibling feature naming only another repo is not printed" "${out}" ;;
  *) pass "a sibling feature naming only another repo is not printed" ;;
esac
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"Only the feature(s) below name this repo"*)
    pass "and the partial view says so rather than reading as the whole project" ;;
  *) fail "the partial view says so rather than reading as the whole project" "${out}" ;;
esac

# --- last-reviewed is stated with its age, and no bar is applied -------------
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"reviewed: 2026-08-01 ("*"ago)"*) pass "last-reviewed carries its age in days" ;;
  *) fail "last-reviewed carries its age in days" "${out}" ;;
esac

# --- the flat shape is still read -------------------------------------------
# It is somebody's committed vault content. A read path that skipped it would
# make a document visible in Obsidian and invisible to every session — and the
# index would still list it, which is the asymmetry lib/projects exists to stop.
cat > "${V}/projects/legacy.md" <<'EOF'
---
kind: project
status: active
started: 2026-06-01
last-reviewed: 2026-08-01
repos: ["target-repo"]
tags: []
---

# legacy — the flat shape

## TL;DR

Written before a project was a directory.
EOF
out_flat="$("${PF}" --repo "${REPO}" --vault "${V}" 2>&1)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_flat}" in
  *"PROJECT  legacy"*"Written before a project was a directory"*)
    pass "a flat projects/<name>.md is read like any other project" ;;
  *) fail "a flat projects/<name>.md is read like any other project" "${out_flat}" ;;
esac
rm "${V}/projects/legacy.md"

# --- a half-written project is named, not hidden -----------------------------
mkdir -p "${V}/projects/halfway/features"
feature halfway only-slice active '["target-repo"]' ''
out_half="$("${PF}" --repo "${REPO}" --vault "${V}" 2>&1)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_half}" in
  *"No _project.md"*"FEATURE  only-slice"*)
    pass "a features dir with no overview is named and its features still shown" ;;
  *) fail "a features dir with no overview is named and its features still shown" "${out_half}" ;;
esac
rm -rf "${V}/projects/halfway"

# --- the ordinary answer is a clean nothing, not an error --------------------
# Most repos have no project doc and never will. A non-zero exit here would make
# the common case look like a failure and teach every caller to ignore it.
BARE="${SANDBOX}/bare-repo"
mkdir -p "${BARE}"
out_bare="$("${PF}" --repo "${BARE}" --vault "${V}" 2>&1)"
assert_exit 0 $? "a repo with no project doc exits 0"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_bare}" in
  *"No project doc names this repo"*"project-candidates"*)
    pass "and says so, pointing at how one gets written" ;;
  *) fail "and says so, pointing at how one gets written" "${out_bare}" ;;
esac

NOPROJ="${SANDBOX}/no-projects-vault"
mkdir -p "${NOPROJ}/practices"
out_noproj="$("${PF}" --repo "${REPO}" --vault "${NOPROJ}" 2>&1)"
assert_exit 0 $? "a vault with no projects/ at all exits 0"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_noproj}" in
  *"No projects/ directory in this vault"*)
    pass "and distinguishes an absent projects/ from an unmatched repo" ;;
  *) fail "and distinguishes an absent projects/ from an unmatched repo" "${out_noproj}" ;;
esac

# --- it never writes ---------------------------------------------------------
# The whole contract. The vault has one write path and this is not it.
before="$(find "${V}" "${REPO}" -type f | sort | xargs shasum 2>/dev/null | shasum)"
"${PF}" --repo "${REPO}" --vault "${V}" >/dev/null 2>&1
after="$(find "${V}" "${REPO}" -type f | sort | xargs shasum 2>/dev/null | shasum)"
TESTS_RUN=$((TESTS_RUN + 1))
if [ "${before}" = "${after}" ]; then
  pass "reports without touching the vault or the repo"
else
  fail "reports without touching the vault or the repo" "something changed"
fi

# --- the errors that are real errors -----------------------------------------
"${PF}" --repo "${SANDBOX}/nope" --vault "${V}" >/dev/null 2>&1
assert_exit 1 $? "a missing repo is an error"
"${PF}" --repo "${REPO}" --vault "${SANDBOX}/no-such-vault" >/dev/null 2>&1
assert_exit 1 $? "a missing vault is an error"

# --- the repo slug is spelled the way practices-for spells it ----------------
# Two answers to "what is this repo called" would silently split the vault: a
# project doc found by one tool and not the other, with no error either way.
agree="$(python3 -c "
import importlib.util, sys
sys.path.insert(0, '${ENGINE}/scripts')

def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
    return mod

pf = load('pf', '${ENGINE}/scripts/practices-for.py')
prf = load('prf', '${ENGINE}/scripts/project-for.py')
a, b = pf.repo_slug('${REPO}'), prf.repo_slug('${REPO}')
print('AGREE %s' % a if a == b else 'DIFFER %s vs %s' % (a, b))
" 2>/dev/null)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${agree}" in
  "AGREE "*) pass "practices-for and project-for spell a repo the same way (${agree#AGREE })" ;;
  *) fail "practices-for and project-for spell a repo the same way" "${agree:-no output}" ;;
esac

# --- the index and the read path see the same projects -----------------------
# The asymmetry lib/projects exists to prevent: a document the index lists and
# no session can reach, or the reverse. Both go through discover().
same="$(python3 -c "
import importlib.util, sys
from pathlib import Path
sys.path.insert(0, '${ENGINE}/scripts')
from lib.projects import discover
spec = importlib.util.spec_from_file_location('bvi', '${ENGINE}/scripts/build-vault-index.py')
bvi = importlib.util.module_from_spec(spec); spec.loader.exec_module(bvi)
vault = Path('${V}')
indexed = sorted(n['slug'] for n in bvi.collect_projects(vault)[0])
found = sorted(p['slug'] for p in discover(vault))
print('SAME %s' % ','.join(found) if indexed == found else 'DIFFER %s vs %s' % (indexed, found))
" 2>/dev/null)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${same}" in
  "SAME "*) pass "the index and the read path discover the same projects (${same#SAME })" ;;
  *) fail "the index and the read path discover the same projects" "${same:-no output}" ;;
esac

finish
