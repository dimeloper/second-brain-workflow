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

MAX_FILES="${GUARD_MAX_FILES:-20}"
MAX_LINES="${GUARD_MAX_LINES:-2000}"
VAULT="${SBW_VAULT}"
# Precedence: --expect-id flag (below) > SBW_EXPECTED_VAULT_ID env > machine
# config (both already resolved by ds_config_load) > empty. Never the vault
# under inspection itself — see the trust-model note in README.md.
EXPECT_ID="${SBW_EXPECTED_VAULT_ID}"
RANGE=""
REV=""

while [ $# -gt 0 ]; do
  case "$1" in
    --vault) VAULT="${2:?--vault needs a value}"; shift 2 ;;
    --expect-id) EXPECT_ID="${2:?--expect-id needs a value}"; shift 2 ;;
    --range) RANGE="${2:?--range needs a BASE..HEAD value}"; shift 2 ;;
    --rev) REV="${2:?--rev needs a value}"; shift 2 ;;
    -h|--help) sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

fail() { echo "guard: $1" >&2; exit 1; }

[ -z "${RANGE}" ] || [ -z "${REV}" ] || fail "--range and --rev are mutually exclusive"

[ -d "${VAULT}" ] || fail "vault not found: ${VAULT}"
[ -d "${VAULT}/.git" ] || fail "not a git repo: ${VAULT}"

# --- diff source: the staged index, or a commit range/single rev -----------
# Every check below reads through diff_paths()/diff_body()/PRE_REF rather than
# calling `git diff --cached` directly, so the same five checks run
# unchanged regardless of where the diff comes from.
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
  nothing_msg="no changes in ${BASE}..${NEW} — nothing to check."
else
  PRE_REF="HEAD"
  diff_paths() { git -C "${VAULT}" diff --cached --name-only "$@"; }
  diff_numstat() { git -C "${VAULT}" diff --cached --numstat; }
  diff_body() { git -C "${VAULT}" diff --cached; }
  nothing_msg="nothing staged — nothing to check."
fi

staged="$(diff_paths)"
[ -n "${staged}" ] || { echo "guard: ${nothing_msg}"; exit 0; }

# --- 1. vault identity -------------------------------------------------------
# Catches the case that matters: a session configured for one vault committing
# into another, or a clone repointed at someone else's remote. Shared with
# init-vault.sh's --adopt check via scripts/lib/vault-identity.sh — one
# implementation of "does this vault match what was expected."
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

# --- 2. staged paths ---------------------------------------------------------
while IFS= read -r f; do
  [ -n "${f}" ] || continue
  case "${f}" in
    practices/*|bases/*|00-maps/*|_templates/*) ;;
    vault.json|.gitignore) ;;
    .obsidian/*) ;;
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9].md) ;;
    *) fail "staged path outside the vault's allowed set: ${f}" ;;
  esac
done <<EOF
${staged}
EOF

# --- 3. size caps ------------------------------------------------------------
n_files="$(printf '%s\n' "${staged}" | grep -c . || true)"
n_lines="$(diff_numstat | awk '{a+=$1; d+=$2} END {print a+d+0}')"
[ "${n_files}" -le "${MAX_FILES}" ] || \
  fail "${n_files} files staged, cap is ${MAX_FILES} (GUARD_MAX_FILES to override)"
[ "${n_lines}" -le "${MAX_LINES}" ] || \
  fail "${n_lines} changed lines staged, cap is ${MAX_LINES} (GUARD_MAX_LINES to override)"

# --- 4. no enforced note deleted --------------------------------------------
# PRE_REF is HEAD in staged mode (the last commit, before the staged
# deletion) or the range's BASE in --range/--rev mode (the state before the
# range's changes) — same question either way: did this diff delete a note
# that was enforced right before it.
deleted="$(diff_paths --diff-filter=D -- 'practices/*')"
while IFS= read -r f; do
  [ -n "${f}" ] || continue
  if git -C "${VAULT}" show "${PRE_REF}:${f}" 2>/dev/null | grep -q '^maturity: enforced'; then
    fail "deleting an enforced practice note: ${f}
       Demote it to trialing with a recorded counterexample instead."
  fi
done <<EOF
${deleted}
EOF

# --- 5. conflict markers and secrets ----------------------------------------
body="$(diff_body)"
if printf '%s' "${body}" | grep -qE '^\+(<<<<<<< |>>>>>>> |=======$)'; then
  fail "conflict markers in the diff"
fi
if printf '%s' "${body}" | grep -qE '^\+.*(ghp_[A-Za-z0-9]{20,}|gho_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]{10,}|-----BEGIN [A-Z ]*PRIVATE KEY)'; then
  fail "the diff looks like it contains a credential"
fi

echo "guard: ok — ${n_files} file(s), ${n_lines} line(s), vault '${vid:-unchecked}'"
