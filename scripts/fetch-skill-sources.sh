#!/usr/bin/env bash
# Fetch every third-party skill source the manifest declares, at its pinned ref.
#
# Usage:
#   ./fetch-skill-sources.sh              # print what would happen, change nothing
#   ./fetch-skill-sources.sh --dry-run    # the same, said explicitly
#   ./fetch-skill-sources.sh --yes        # actually clone and check out
#
# This is the only script here that reaches the network, and it is separate from
# sync-skills.sh for exactly that reason: sync runs during the Quickstart and
# several hundred times during `make check`, and a sync that cloned would make
# the suite depend on GitHub being up and on whoever runs it having credentials.
# Fetch is the network step, sync is the link step, and each can be run and
# reasoned about without the other.
#
# Checkouts land in vendor/external/<source-name>/, which is gitignored. That is
# the whole reason these are not submodules: a submodule records its pin in
# .gitmodules, and this repo is public, so the roster of skills a person chose
# to adopt would be published along with the engine. The manifest lives in the
# operator's own private content repo instead — same split as rules/.
#
# Always a *detached* checkout at the ref. A branch name would mean two machines
# reading one manifest install different skills on different days, which is the
# failure the pin exists to prevent, so an unpinned source is refused upstream in
# lib/skill_manifest.py rather than tolerated here.
#
# What it never does: touch a source directory that is not declared in the
# manifest (removal is reported, never performed — a stale checkout costs disk
# and nothing else, and `rm -rf` on a path assembled from a config file is not a
# thing this script will do unattended), and never write outside
# vendor/external/.
set -euo pipefail

STANDARDS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/config.sh
. "${STANDARDS_DIR}/scripts/lib/config.sh"
ds_config_load
# shellcheck source=scripts/lib/invocation.sh
. "${STANDARDS_DIR}/scripts/lib/invocation.sh"

EXTERNAL_DIR="${STANDARDS_DIR}/vendor/external"

APPLY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes) APPLY=1; shift ;;
    --dry-run) APPLY=0; shift ;;
    -h|--help) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

if ! SOURCES="$(python3 "${STANDARDS_DIR}/scripts/lib/skill_manifest.py" \
                  sources --engine "${STANDARDS_DIR}")"; then
  echo "Manifest unusable — nothing fetched." >&2
  exit 2
fi

if [[ -z "${SOURCES}" ]]; then
  echo "No skill sources declared."
  echo "  (${SBW_SKILLS_MANIFEST:+manifest: ${SBW_SKILLS_MANIFEST}}${SBW_SKILLS_MANIFEST:-set SBW_SKILLS_MANIFEST to a skills.json to declare some})"
  exit 0
fi

run() { if [[ ${APPLY} -eq 1 ]]; then "$@"; else echo "    would: $*"; fi; }

# The sha a checkout is actually sitting at, or empty if it isn't a git repo.
# Never fails the script: a half-made checkout is a state to report, not a crash.
head_sha() {
  git -C "$1" rev-parse HEAD 2>/dev/null || true
}

planned=0
already=0
errors=0

while IFS=$'\t' read -r name repo ref dir; do
  [[ -n "${name}" ]] || continue
  echo "${name}"
  echo "  repo: ${repo}"
  echo "  ref:  ${ref}"

  if [[ -e "${dir}" && ! -d "${dir}" ]]; then
    echo "  !! ${dir} exists and is not a directory — left untouched" >&2
    errors=$((errors + 1))
    continue
  fi

  if [[ -d "${dir}/.git" ]]; then
    current="$(head_sha "${dir}")"
    if [[ "${current}" == "${ref}" ]]; then
      echo "  already at ${ref}"
      already=$((already + 1))
      continue
    fi
    echo "  at ${current:-<unknown>}, wants ${ref}"
    # Fetch before checkout: the pin may be newer than whatever this clone last
    # saw, and `checkout` on an absent object fails with a message about a
    # pathspec, which reads as a typo rather than as "you need to fetch".
    run git -C "${dir}" fetch --quiet origin
    run git -C "${dir}" checkout --quiet --detach "${ref}"
    planned=$((planned + 1))
    continue
  fi

  if [[ -d "${dir}" ]]; then
    # A directory with no .git: someone put something here, or a clone died
    # partway. Either way this script did not leave it in a state it recognises,
    # so it does not get to decide what happens to it.
    echo "  !! ${dir} exists but is not a git checkout — left untouched" >&2
    echo "     remove it by hand, then re-run" >&2
    errors=$((errors + 1))
    continue
  fi

  run mkdir -p "${EXTERNAL_DIR}"
  run git clone --quiet "${repo}" "${dir}"
  run git -C "${dir}" checkout --quiet --detach "${ref}"
  planned=$((planned + 1))
done <<< "${SOURCES}"

# Checkouts nothing declares any more. Reported, never removed: the cost of
# keeping one is disk, and the cost of a wrong `rm -rf` on a path built from a
# config file is not symmetrical with that.
if [[ -d "${EXTERNAL_DIR}" ]]; then
  declared=""
  while IFS=$'\t' read -r name _ _ _; do
    [[ -n "${name}" ]] || continue
    declared="${declared}${name}"$'\n'
  done <<< "${SOURCES}"
  for entry in "${EXTERNAL_DIR}"/*; do
    [[ -d "${entry}" ]] || continue
    base="$(basename "${entry}")"
    case $'\n'"${declared}" in
      *$'\n'"${base}"$'\n'*) continue ;;
    esac
    echo "-- ${base}: checked out but no longer declared"
    echo "   remove by hand if you want the disk back: rm -rf ${entry}"
  done
fi

echo
echo "${already} up to date, ${planned} to fetch."
if [[ ${errors} -gt 0 ]]; then
  echo "${errors} source(s) could not be fetched — see above." >&2
  exit 1
fi
if [[ ${planned} -gt 0 && ${APPLY} -eq 0 ]]; then
  echo "Preview only — nothing written."
  echo "Re-run with $(say_remediation 'YES=1 (make fetch-skills YES=1)' '--yes') to fetch."
fi
if [[ ${APPLY} -eq 1 && ${planned} -gt 0 ]]; then
  echo "Now run $(say_remediation 'make sync-skills' './scripts/sync-skills.sh') to link them in."
fi
exit 0
