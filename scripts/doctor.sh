#!/usr/bin/env bash
# Machine health check: four read-only checks, none overlapping with
# `make audit` (content) or `make check` (code):
#   - the vault's commit guard is wired in as a pre-commit hook, and it's ours
#   - commits here would be authored as the identity vault.json declares
#   - a skill installed into one configured skills dir isn't missing from another
#   - a vendored submodule isn't left at the wrong commit after a tag switch
# Changes nothing. Not part of `make check` — like `make guard` and
# `make vault-index-check`, it needs a real vault, and CI has none.
#
#   ./doctor.sh [--vault PATH]
#
# Exit codes:
#   0  everything checked out
#   1  warnings only — setup is unfinished, but nothing is misconfigured
#   2  at least one error — something is configured wrong and no amount of
#      finishing setup will fix it
#
# Warnings stay non-zero deliberately. Every check here exists to surface a
# state nothing else surfaces — a stale submodule still renders fine, a skill
# missing from one skills dir is invisible from the other agent — so a
# scheduled run that exited 0 on those findings would be decorative. What was
# actually wrong was one message and one severity covering two different
# problems; splitting "your configuration points nowhere" (2) from "setup
# isn't finished yet" (1) is what a reader mid-setup needed.
set -euo pipefail

STANDARDS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/config.sh
. "${STANDARDS_DIR}/scripts/lib/config.sh"
# shellcheck source=scripts/lib/vault-state.sh
. "${STANDARDS_DIR}/scripts/lib/vault-state.sh"
# shellcheck source=scripts/lib/author-identity.sh
. "${STANDARDS_DIR}/scripts/lib/author-identity.sh"
# shellcheck source=scripts/lib/skill-links.sh
. "${STANDARDS_DIR}/scripts/lib/skill-links.sh"
ds_config_load
skills_dirs_load

VAULT="${SBW_VAULT}"
VAULT_ORIGIN="$(ds_origin_describe SBW_VAULT)"
while [ $# -gt 0 ]; do
  case "$1" in
    --vault)
      VAULT="${2:?--vault needs a value}"
      VAULT_ORIGIN="the --vault flag"
      shift 2
      ;;
    -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

problems=0
errors=0
ok()   { echo "  ok    $1"; }
warn() { echo "  warn  $1"; problems=$((problems + 1)); }
err()  { echo "  ERROR $1"; problems=$((problems + 1)); errors=$((errors + 1)); }

HOOK_MARKER="# second-brain-workflow: vault-commit guard"

# A path that points nowhere is an error: no amount of finishing setup fixes a
# wrong path, and the fix is in a different place (the config file or the flag)
# than every other finding here. The two unfinished-setup states stay warnings.
check_hook() {
  vault_state "${VAULT}" "${VAULT_ORIGIN}" || true
  case "${VS_STATE}" in
    missing)       err "${VS_MESSAGE}"; return ;;
    not-a-repo)    warn "${VS_MESSAGE}"; return ;;
    no-vault-json) warn "${VS_MESSAGE}"; return ;;
  esac

  local hook="${VAULT}/.git/hooks/pre-commit"
  if [ ! -e "${hook}" ]; then
    warn "no pre-commit hook in ${VAULT} — run: ./scripts/init-vault.sh --path ${VAULT} --id VAULT_ID --adopt"
    return
  fi
  if grep -qF "${HOOK_MARKER}" "${hook}" 2>/dev/null; then
    ok "commit guard installed as a pre-commit hook in ${VAULT}"
  else
    warn "${VAULT}/.git/hooks/pre-commit exists but is not ours — the guard runs only via update-second-brain here, not on every commit"
  fi
}

# A vault created before the author check existed has no identity block, so the
# check silently doesn't apply — on the machine where a personal address reached
# an employer repo, that is still true of the vault it happened in. Nothing else
# tells you: `--adopt` fills scaffold *files* and never edits vault.json, so
# there is no automatic upgrade. Hence naming the exact line to add rather than
# reporting a bare "optional". Severity stays `ok`: the check genuinely is
# opt-in, and doctor cannot know whether a given vault ought to pin one.
# printf, not echo: the pattern example contains a backslash, and echo's
# handling of those is not portable.
#
# Which of the two it is matters to the reader: "you never added the block" and
# "your block is there and pins nothing" have the same consequence but not the
# same fix, and telling someone staring at an identity block that they haven't
# got one is how a real report gets dismissed as wrong.
no_identity() {
  local why="${1:-absent}"
  ok "vault.json pins no commit author — the check is opt-in, so it is not running here"
  if [ "${why}" = "empty" ]; then
    printf '%s\n' '        the identity block is present but declares nothing, so it pins nothing;'
    printf '%s\n' '        give it a key to enable the check:'
  else
    printf '%s\n' '        a vault created before this feature has no identity block; add one to enable it:'
  fi
  printf '%s\n' '          "identity": { "email": "you@example.com" }'
  printf '%s\n' '          or, for addresses that vary: { "email_pattern": ".*@example\\.com$" }'
  printf '%s\n' '        see docs/GUARD.md#upgrading-an-existing-vault'
}

# The point of reporting it here is timing: the guard catches an author
# mismatch at the first commit, which on the machine this came from was already
# one commit too late. An error rather than a warning — a git identity that
# resolves to the wrong address is a setting that is wrong, not a step that
# hasn't been taken yet, and finishing setup won't change it.
check_author() {
  # `return 0`, not a bare `return`: a bare one propagates the failed test's
  # status, and under `set -e` that aborts the whole run — silently dropping
  # the remaining checks and the summary for any vault without a vault.json.
  [ -f "${VAULT}/vault.json" ] || return 0
  local ident="" email="" name="" rc=0
  ident="$(git -C "${VAULT}" var GIT_AUTHOR_IDENT 2>/dev/null || true)"
  if [ -n "${ident}" ]; then
    name="${ident%% <*}"
    email="${ident#*<}"
    email="${email%%>*}"
  fi

  author_identity_check "${VAULT}" "${email}" "${name}" || rc=$?
  case "${rc}" in
    0)
      if [ -n "${AI_EXPECT}" ]; then
        ok "commits here would be authored as ${email}, which is what vault.json declares"
      else
        no_identity empty
      fi
      ;;
    2) no_identity absent ;;
    *) err "${AI_ERROR}" ;;
  esac
}

# Not vault-specific — SKILLS_DIRS is a machine-wide setting, so this runs
# regardless of --vault. Detection only: a real directory or a symlink to
# another tool's install (e.g. Railway's use-railway, which its own
# installer writes into ~/.claude/skills only) can silently exist in one
# configured dir and not another, and nothing notices until someone reaches
# for it from the missing side. One of ours (a symlink into this repo) gets
# a simpler fix — re-run sync-skills.sh — since that command alone would
# already propagate it everywhere; anything else gets the exact `ln -s`.
check_skills() {
  local dir name entry names missing_dirs first_dir target clean=1
  local -a dirs

  IFS=':' read -r -a dirs <<< "${SKILLS_DIRS}"
  if [ "${#dirs[@]}" -lt 2 ]; then
    ok "only one skills directory configured — nothing to compare across"
    return
  fi

  names=""
  for dir in "${dirs[@]}"; do
    [ -d "${dir}" ] || continue
    for entry in "${dir}"/*; do
      [ -e "${entry}" ] || continue
      names="${names}$(basename "${entry}")
"
    done
  done
  names="$(printf '%s' "${names}" | sort -u)"
  [ -n "${names}" ] || { ok "no skills installed anywhere yet"; return; }

  while IFS= read -r name; do
    [ -n "${name}" ] || continue
    missing_dirs=""
    first_dir=""
    for dir in "${dirs[@]}"; do
      if [ -e "${dir}/${name}" ]; then
        [ -n "${first_dir}" ] || first_dir="${dir}"
      else
        missing_dirs="${missing_dirs}${dir}
"
      fi
    done
    [ -n "${missing_dirs}" ] || continue

    clean=0
    target=""
    [ -L "${first_dir}/${name}" ] && target="$(readlink "${first_dir}/${name}")"

    case "${target}" in
      "${STANDARDS_DIR}"/*)
        warn "${name}: not installed in every configured skills dir — run ./scripts/sync-skills.sh"
        ;;
      *)
        while IFS= read -r dir; do
          [ -n "${dir}" ] || continue
          warn "${name}: in ${first_dir} but not ${dir} — fix: ln -s ${first_dir}/${name} ${dir}/${name}"
        done <<< "${missing_dirs}"
        ;;
    esac
  done <<< "${names}"

  [ "${clean}" -eq 1 ] && ok "every installed skill is present in all configured skills directories"
}

# Our links in a directory SKILLS_DIRS no longer names. Separate from the
# parity check above on purpose: parity asks whether the *configured* set
# agrees with itself, and folding an unconfigured directory into that
# comparison would report every skill in it as a gap to fill — the opposite of
# the advice wanted, which is to clean it up.
#
# How it happens is ordinary. sync-skills.sh runs during the Quickstart before
# a machine config exists, so it installs into the built-in default, meaning
# both directories; the config written afterwards narrows SKILLS_DIRS to one.
# From then on the wider install is invisible to every tool that reads the
# config — including `make uninstall`, which is the documented way out of the
# dangling-link state a deleted checkout leaves. A warning, not an error:
# nothing is broken, but nothing else will ever mention it.
check_orphaned_skills() {
  local dir n clean=1
  while IFS= read -r dir; do
    [ -n "${dir}" ] || continue
    n="$(skill_links_ours_in "${dir}" "${STANDARDS_DIR}")"
    [ "${n}" -gt 0 ] || continue
    clean=0
    warn "${n} of our skill link(s) in ${dir}, which is not in SKILLS_DIRS
        installed before the config narrowed it, and invisible to everything
        that reads the config. Remove them with ./scripts/uninstall.sh (it
        looks here too, and shows them before it acts), or widen SKILLS_DIRS
        in $(ds_config_path) to include it."
  done <<EOF
${SKILLS_DIRS_UNCONFIGURED}
EOF
  [ "${clean}" -eq 1 ] && ok "no skills of ours are installed outside SKILLS_DIRS"
  return 0
}

# Not vault-specific — vendor/obsidian-skills is pinned in this engine
# checkout, not the vault. `git submodule status` prefixes each line with
# ' ' (in sync), '+' (checked out commit doesn't match what the superproject
# pins — the "switched tags/branches and forgot to update" state that
# checking out a tag alone can't fix on its own) or '-' (never initialized).
# Nothing else surfaces this: a stale submodule renders/links fine, it's
# just silently not the commit the current tag actually pins.
check_submodules() {
  if [ ! -d "${STANDARDS_DIR}/.git" ]; then
    ok "engine checkout is not a git repo — nothing to check for submodule drift"
    return
  fi
  local status
  status="$(git -C "${STANDARDS_DIR}" submodule status 2>/dev/null)"
  if [ -z "${status}" ]; then
    ok "no submodules configured"
    return
  fi
  local clean=1 line
  while IFS= read -r line; do
    [ -n "${line}" ] || continue
    case "${line}" in
      "+"*)
        clean=0
        warn "submodule out of sync with the pinned commit (${line#?}) — run: git submodule update --init --recursive"
        ;;
      "-"*)
        clean=0
        warn "submodule not initialized (${line#?}) — run: git submodule update --init --recursive"
        ;;
    esac
  done <<< "${status}"
  [ "${clean}" -eq 1 ] && ok "vendored submodule(s) match the commit this checkout pins"
}

echo "second-brain-workflow doctor — vault: ${VAULT}"
check_hook
check_author
check_skills
check_orphaned_skills
check_submodules

echo
if [ "${problems}" -eq 0 ]; then
  echo "All checks passed."
  exit 0
fi
if [ "${errors}" -gt 0 ]; then
  echo "${problems} thing(s) worth a look, ${errors} of them misconfiguration."
  exit 2
fi
echo "${problems} thing(s) worth a look — setup unfinished, nothing misconfigured."
exit 1
