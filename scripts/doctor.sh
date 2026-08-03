#!/usr/bin/env bash
# Machine health check: reports gaps that nothing else surfaces on its own —
# a vault whose commit guard isn't wired in as a pre-commit hook, a skill
# installed for one agent but not another, and so on. Read-only; changes
# nothing. Exits non-zero if anything is worth a look, so it composes with CI
# or a cron job, but it is not part of `make check` — like `make guard` and
# `make vault-index-check`, it needs a real vault, and CI has none.
#
#   ./doctor.sh [--vault PATH]
set -euo pipefail

STANDARDS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/config.sh
. "${STANDARDS_DIR}/scripts/lib/config.sh"
ds_config_load

VAULT="${SBW_VAULT}"
while [ $# -gt 0 ]; do
  case "$1" in
    --vault) VAULT="${2:?--vault needs a value}"; shift 2 ;;
    -h|--help) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

problems=0
ok()   { echo "  ok    $1"; }
warn() { echo "  warn  $1"; problems=$((problems + 1)); }

HOOK_MARKER="# second-brain-workflow: vault-commit guard"

check_hook() {
  if [ ! -d "${VAULT}/.git" ]; then
    warn "${VAULT} is not a git repo yet — nothing to guard"
    return
  fi
  local hook="${VAULT}/.git/hooks/pre-commit"
  if [ ! -e "${hook}" ]; then
    warn "no pre-commit hook in ${VAULT} — run: ./scripts/init-vault.sh --path ${VAULT} --id <id> --adopt"
    return
  fi
  if grep -qF "${HOOK_MARKER}" "${hook}" 2>/dev/null; then
    ok "commit guard installed as a pre-commit hook in ${VAULT}"
  else
    warn "${VAULT}/.git/hooks/pre-commit exists but is not ours — the guard runs only via update-second-brain here, not on every commit"
  fi
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

echo "second-brain-workflow doctor — vault: ${VAULT}"
check_hook
check_skills

echo
if [ "${problems}" -eq 0 ]; then
  echo "All checks passed."
  exit 0
fi
echo "${problems} thing(s) worth a look."
exit 1
