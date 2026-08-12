#!/usr/bin/env bash
# Refuse a vault commit that looks like it is going to the wrong place.
#
#   ./guard-vault-commit.sh [--vault PATH] [--expect-id ID]
#   ./guard-vault-commit.sh [--vault PATH] [--expect-id ID] --range BASE..HEAD
#   ./guard-vault-commit.sh [--vault PATH] [--expect-id ID] --rev REV
#
# Default mode checks the staged index; run against a vault with changes
# staged, exits non-zero with a reason if any check fails. `update-second-brain`
# runs it before committing, and it works as a pre-commit hook inside a vault.
#
# --range/--rev check a commit diff instead — there is no staging area to
# inspect once a push has already happened, which is exactly the case a
# `--no-verify` past the pre-commit hook leaves CI to catch. --range takes two
# revs (`git diff BASE..HEAD`); --rev checks a single commit against its
# parent (`REV^..REV`). Same checks either way, just a different diff source.
#
# An empty diff skips the checks that read one, and only those: a commit that
# changes nothing still records an author, so `git commit --allow-empty` is
# checked rather than waved through — in both modes.
#
# The boundary between a personal and a work second brain is the *vault*, not
# the rule set. Rules flow outward freely — your own conventions applied to an
# employer's code is fine. The direction that must never happen is a practice
# learned on employer work landing in a personal or public repo, and that is a
# vault write. So the identity of the vault being written to is what gets
# checked, on every commit, rather than trusted to whoever set up the machine.
set -euo pipefail

STANDARDS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/config.sh
. "${STANDARDS_DIR}/scripts/lib/config.sh"
ds_config_load
# shellcheck source=scripts/lib/vault-identity.sh
. "${STANDARDS_DIR}/scripts/lib/vault-identity.sh"
# shellcheck source=scripts/lib/vault-state.sh
. "${STANDARDS_DIR}/scripts/lib/vault-state.sh"
# shellcheck source=scripts/lib/author-identity.sh
. "${STANDARDS_DIR}/scripts/lib/author-identity.sh"

MAX_FILES="${GUARD_MAX_FILES:-20}"
MAX_LINES="${GUARD_MAX_LINES:-2000}"
VAULT="${SBW_VAULT}"
VAULT_ORIGIN="$(ds_origin_describe SBW_VAULT)"
# Precedence: --expect-id flag (below) > SBW_EXPECTED_VAULT_ID env > machine
# config (both already resolved by ds_config_load) > empty. Never the vault
# under inspection itself — see the trust-model note in README.md.
EXPECT_ID="${SBW_EXPECTED_VAULT_ID}"
RANGE=""
REV=""

while [ $# -gt 0 ]; do
  case "$1" in
    --vault)
      VAULT="${2:?--vault needs a value}"
      VAULT_ORIGIN="the --vault flag"
      shift 2
      ;;
    --expect-id) EXPECT_ID="${2:?--expect-id needs a value}"; shift 2 ;;
    --range) RANGE="${2:?--range needs a BASE..HEAD value}"; shift 2 ;;
    --rev) REV="${2:?--rev needs a value}"; shift 2 ;;
    -h|--help) sed -n '2,27p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

fail() { echo "guard: $1" >&2; exit 1; }

[ -z "${RANGE}" ] || [ -z "${REV}" ] || fail "--range and --rev are mutually exclusive"

# Same four-state classification doctor reports, so the guard and the checkup
# never describe the same broken path two different ways. Only the first two
# states abort here: a git repo with no vault.json is handled further down,
# where the identity check already has a documented "nothing to check against"
# path — tightening that is a change to what the guard blocks, not to how it
# describes things, so it is deliberately left alone.
vault_state "${VAULT}" "${VAULT_ORIGIN}" || true
case "${VS_STATE}" in
  missing|not-a-repo) fail "${VS_MESSAGE}" ;;
esac

# --- diff source: the staged index, or a commit range/single rev -----------
# Every diff-derived check reads through diff_paths()/diff_body()/PRE_REF
# rather than calling `git diff --cached` directly, so they run unchanged
# regardless of where the diff comes from. The author check below takes
# neither route — it is not derived from the diff at all.
if [ -n "${RANGE}" ] || [ -n "${REV}" ]; then
  if [ -n "${REV}" ]; then
    BASE="${REV}^"
    NEW="${REV}"
  else
    case "${RANGE}" in
      *..*) BASE="${RANGE%%..*}"; NEW="${RANGE#*..}" ;;
      *) fail "--range needs BASE..HEAD, got: ${RANGE}" ;;
    esac
  fi
  # ^{tree}, not ^{commit}: BASE in particular is legitimately the empty
  # tree (4b825dc6...) rather than a real commit on a vault repo's first
  # push, where there is no prior commit to diff against — `git diff` and
  # `git show <ref>:<path>` both work the same against a bare tree as
  # against a commit, so accepting either here is not a weaker check.
  git -C "${VAULT}" rev-parse --verify --quiet "${BASE}^{tree}" >/dev/null \
    || fail "--range/--rev: not a commit or tree in ${VAULT}: ${BASE}"
  git -C "${VAULT}" rev-parse --verify --quiet "${NEW}^{tree}" >/dev/null \
    || fail "--range/--rev: not a commit or tree in ${VAULT}: ${NEW}"
  PRE_REF="${BASE}"
  diff_paths() { git -C "${VAULT}" diff "${BASE}" "${NEW}" --name-only "$@"; }
  diff_numstat() { git -C "${VAULT}" diff "${BASE}" "${NEW}" --numstat; }
  diff_body() { git -C "${VAULT}" diff "${BASE}" "${NEW}"; }
  nothing_msg="no changes in ${BASE}..${NEW} — no diff to check, but the recorded commit authors were."
else
  PRE_REF="HEAD"
  diff_paths() { git -C "${VAULT}" diff --cached --name-only "$@"; }
  diff_numstat() { git -C "${VAULT}" diff --cached --numstat; }
  diff_body() { git -C "${VAULT}" diff --cached; }
  nothing_msg="nothing staged — no diff to check, but the commit author was."
fi

# --- 1. commit author identity ----------------------------------------------
# First, and before the empty-diff short-circuit below, because this is the one
# check here that is a property of *the commit* rather than of its diff. It
# holds for a commit that changes nothing: `git commit --allow-empty` still
# writes an author into the vault's history permanently, and until this ran
# first it was a bypass that didn't even need --no-verify. The same early
# return gated --range, so a pushed empty commit survived the CI tier too —
# the tier that exists precisely because --no-verify can skip the local one.
#
# The mirror of the vault-identity check below, on the axis it doesn't cover.
# Everything else here asks where content is going; this asks who the commit
# claims to be from. The two are independent: a commit can satisfy every
# destination check, push with the right credentials, and still carry a
# personal identity into an employer-owned repo — which is exactly what
# happened, silently, because nothing looked.
#
# This blocks rather than warns. A warning is what the machine already
# effectively produced — the guard passed, everything looked fine, and the
# wrong author is now permanent in someone else's history. Before the commit
# the fix is one command; after the push it needs a history rewrite on a repo
# you may not control. Since the whole check is opt-in per vault, blocking
# only ever happens where someone declared they wanted it, so it can't become
# the routine nuisance that teaches --no-verify — the one habit that would
# genuinely weaken this guard. A vault that declares nothing is silent here;
# `make doctor` is where "you haven't configured this" gets said.
author_check() {
  local email="$1" name="$2" prefix="$3" rc=0
  author_identity_check "${VAULT}" "${email}" "${name}" || rc=$?
  case "${rc}" in
    0|2) return 0 ;;
    *)   fail "${prefix}${AI_ERROR}" ;;
  esac
}

if [ -n "${RANGE}" ] || [ -n "${REV}" ]; then
  # The commits already exist, so their recorded authors are what matters —
  # the local config that made them is long gone by the time CI runs. Driven by
  # `git log`, not by the diff: a range whose net diff is empty can still carry
  # commits, which is the whole of the --allow-empty case as CI sees it.
  while IFS="$(printf '\t')" read -r c_sha c_name c_email; do
    [ -n "${c_sha}" ] || continue
    author_check "${c_email}" "${c_name}" "commit ${c_sha}: "
  done <<EOF
$(git -C "${VAULT}" log --no-merges --format='%h%x09%an%x09%ae' "${BASE}..${NEW}" 2>/dev/null)
EOF
else
  # The identity this commit would actually be made with — `git var` resolves
  # includeIf, the environment and every fallback, which reading user.email
  # straight out of a config file would not.
  author_ident="$(git -C "${VAULT}" var GIT_AUTHOR_IDENT 2>/dev/null || true)"
  if [ -z "${author_ident}" ]; then
    author_check "" "" ""
  else
    author_name="${author_ident%% <*}"
    author_email="${author_ident#*<}"
    author_email="${author_email%%>*}"
    author_check "${author_email}" "${author_name}" ""
  fi
fi

# --- everything below here reads the diff -------------------------------------
# So an empty one genuinely has nothing to examine: no paths to match against
# the allowlist, no lines to cap, no deletion to inspect, no body to scan. The
# message says which half was skipped rather than "nothing to check", because
# that wording is what made a real bypass read as correct behaviour.
staged="$(diff_paths)"
[ -n "${staged}" ] || { echo "guard: ${nothing_msg}"; exit 0; }

# --- 2. vault identity -------------------------------------------------------
# Catches the case that matters: a session configured for one vault committing
# into another, or a clone repointed at someone else's remote. Shared with
# init-vault.sh's --adopt check via scripts/lib/vault-identity.sh — one
# implementation of "does this vault match what was expected."
#
# Deliberately below the short-circuit, unlike the author check: this one asks
# where *content* is going, and an empty commit carries none. Running it above
# would also make an unconfigured machine fail closed on a commit that writes
# nothing — a widening of what the guard blocks that nothing here needs.
#
# An unconfigured expectation is not "nothing to check" — it is exactly the
# state that would make the check circular if we let vault.json's own id
# stand in for it. Fail closed instead: a vault.json to check against, with
# no configured expectation to check it against, blocks the commit.
if [ -f "${VAULT}/vault.json" ] && [ -z "${EXPECT_ID}" ]; then
  fail "no expected vault id configured for this machine.
       Set SBW_EXPECTED_VAULT_ID in \$XDG_CONFIG_HOME/second-brain-workflow/config
       (see config.example), or pass --expect-id explicitly. Refusing to
       guess which vault this machine expects."
fi

if vault_identity_check "${VAULT}" "${EXPECT_ID}"; then
  vid="${VI_ID}"
else
  case $? in
    1) fail "${VI_ERROR}" ;;
    2) echo "guard: no vault.json in ${VAULT} — identity unchecked." >&2
       echo "       create one with scripts/init-vault.sh --adopt to enable this check." >&2 ;;
  esac
fi

# --- 3. staged paths ---------------------------------------------------------
# .github/workflows/*: infrastructure (docs/vault-ci/{audit,guard}.yml,
# copied in once by a human, not written by update-second-brain), not
# capture content — but it's still vault-repo content only this allowlist
# protects, so it belongs here rather than working around the guard.
while IFS= read -r f; do
  [ -n "${f}" ] || continue
  case "${f}" in
    practices/*|bases/*|00-maps/*|_templates/*) ;;
    vault.json|.gitignore) ;;
    .obsidian/*) ;;
    .github/workflows/*.yml|.github/workflows/*.yaml) ;;
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9].md) ;;
    *) fail "staged path outside the vault's allowed set: ${f}" ;;
  esac
done <<EOF
${staged}
EOF

# --- 4. size caps ------------------------------------------------------------
n_files="$(printf '%s\n' "${staged}" | grep -c . || true)"
n_lines="$(diff_numstat | awk '{a+=$1; d+=$2} END {print a+d+0}')"
[ "${n_files}" -le "${MAX_FILES}" ] || \
  fail "${n_files} files staged, cap is ${MAX_FILES} (GUARD_MAX_FILES to override)"
[ "${n_lines}" -le "${MAX_LINES}" ] || \
  fail "${n_lines} changed lines staged, cap is ${MAX_LINES} (GUARD_MAX_LINES to override)"

# --- 5. no enforced note deleted --------------------------------------------
# PRE_REF is HEAD in staged mode (the last commit, before the staged
# deletion) or the range's BASE in --range/--rev mode (the state before the
# range's changes) — same question either way: did this diff delete a note
# that was enforced right before it.
deleted="$(diff_paths --diff-filter=D -- 'practices/*')"
while IFS= read -r f; do
  [ -n "${f}" ] || continue
  # Here-string for the same reason as the secret scan below: a match on the
  # note's first lines would SIGPIPE `git show` and, under pipefail, report the
  # pipeline as failed — reading as "not enforced" and allowing the deletion.
  if grep -q '^maturity: enforced' <<< "$(git -C "${VAULT}" show "${PRE_REF}:${f}" 2>/dev/null)"; then
    fail "deleting an enforced practice note: ${f}
       Demote it to trialing with a recorded counterexample instead."
  fi
done <<EOF
${deleted}
EOF

# --- 6. conflict markers and secrets ----------------------------------------
#
# Here-strings, not `printf ... | grep -q`. That pipeline failed *open*: `grep
# -q` exits the moment it matches, `printf` is then killed by SIGPIPE, and
# `pipefail` reports the pipeline as 141 — so `if` took the else branch and the
# commit was allowed. The earlier the credential appeared in the diff and the
# larger the diff, the more reliably it was missed, which is precisely backwards
# for a check whose whole job is to catch one.
body="$(diff_body)"
if grep -qE '^\+(<<<<<<< |>>>>>>> |=======$)' <<< "${body}"; then
  fail "conflict markers in the diff"
fi
if grep -qE '^\+.*(ghp_[A-Za-z0-9]{20,}|gho_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]{10,}|-----BEGIN [A-Z ]*PRIVATE KEY)' <<< "${body}"; then
  fail "the diff looks like it contains a credential"
fi

echo "guard: ok — ${n_files} file(s), ${n_lines} line(s), vault '${vid:-unchecked}'"
