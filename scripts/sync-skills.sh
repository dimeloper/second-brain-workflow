#!/usr/bin/env bash
# Install skills from this repo into every configured agent skills directory.
# Both Cursor and Claude Code discover skills only as flat directories, so each
# skill is symlinked in by name; categories live in this repo for organization.
#
# Usage:
#   ./sync-skills.sh                        # install into SKILLS_DIRS
#   ./sync-skills.sh --dry-run              # print planned actions only
#
# Config:
#   SKILLS_DIRS          colon-separated install targets
#                        (default: ~/.cursor/skills:~/.claude/skills)
#   VENDOR_SKILLS        space-separated allowlist from vendor/obsidian-skills
#   SBW_SKILLS_MANIFEST  path to a skills.json declaring third-party sources
#                        (default: none — workflow skills only)
#
# This script never reaches the network. It runs during the Quickstart and
# throughout a test suite of several hundred assertions, so a source that has
# not been fetched is *reported* with the command that fetches it rather than
# fetched here — the same detection-only contract `make doctor` keeps.
set -euo pipefail

STANDARDS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILLS_SRC="${STANDARDS_DIR}/skills"

# shellcheck source=scripts/lib/config.sh
. "${STANDARDS_DIR}/scripts/lib/config.sh"
ds_config_load
# shellcheck source=scripts/lib/invocation.sh
. "${STANDARDS_DIR}/scripts/lib/invocation.sh"

# Upstream skills (kepano/obsidian-skills, MIT, pinned submodule). Installed by
# allowlist rather than wholesale: json-canvas and defuddle are unrelated to this
# vault, and obsidian-cli is only useful once the Obsidian CLI is on PATH.
VENDOR_SRC="${STANDARDS_DIR}/vendor/obsidian-skills/skills"

# Third-party sources, declared outside this repo. Read once, before anything is
# installed: a manifest that cannot be trusted must stop the run rather than
# quietly reduce it to the workflow skills, which is what continuing past a
# parse error would look like from the outside.
#
# Resolution and validation live in lib/skill_manifest.py; severity is decided
# here. That split is the same one lib/vault_state.py and vault-state.sh keep,
# and for the same reason — the policy question ("is this fatal, and what should
# the operator run?") belongs to the tool the operator invoked.
# Guarded on the setting rather than run unconditionally: with no roster
# declared there is nothing to resolve, and shelling out anyway would make this
# script depend on a file it does not otherwise need — which is how a partial
# engine checkout started failing a check about something else entirely.
MANIFEST_ROWS=""
if [[ -n "${SBW_SKILLS_MANIFEST}" ]]; then
  if ! MANIFEST_ROWS="$(python3 "${STANDARDS_DIR}/scripts/lib/skill_manifest.py" \
                          resolve --engine "${STANDARDS_DIR}")"; then
    echo "Manifest unusable — nothing installed." >&2
    exit 2
  fi
fi

DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

# Which directories, and on whose authority. The Quickstart runs this *before*
# a machine config exists, so the built-in default does the choosing — both
# directories — and a config written afterwards may well name fewer. Whatever
# was installed into the others stays there, invisible to every tool that reads
# the config. Seeing the wider install happen is the difference between a
# decision and a discovery three steps later.
case "${SKILLS_DIRS_ORIGIN:-}" in
  config|environment)
    echo "Installing into ${SKILLS_DIRS}"
    echo "  (from $(ds_origin_describe SKILLS_DIRS))"
    ;;
  *)
    echo "!! No SKILLS_DIRS configured, so this is installing into the built-in"
    echo "   default — BOTH of these directories:"
    echo "     ${SKILLS_DIRS//:/$'\n     '}"
    echo "   If you later set SKILLS_DIRS to fewer, what landed in the others"
    echo "   stays there. 'make doctor' reports it; ./scripts/uninstall.sh removes it."
    ;;
esac
echo

[[ -d "${SKILLS_SRC}" ]] || { echo "Missing ${SKILLS_SRC}" >&2; exit 1; }

run() { if [[ $DRY_RUN -eq 1 ]]; then echo "    would: $*"; else "$@"; fi; }

# Skill source dirs, one per line. Local skills first; a vendored skill sharing
# a name with a local one is shadowed, so local conventions always win.
#
# Note: never pipe this into `grep -q` under `set -o pipefail`. grep -q exits on
# the first match, the producer takes SIGPIPE, and the pipeline reports failure
# even though the match succeeded. Capture the output and match in-shell.
skill_dirs() {
  local local_dirs name dir status path source
  local_dirs="$(find "${SKILLS_SRC}" -mindepth 2 -maxdepth 2 -type d | sort)"
  printf '%s\n' "${local_dirs}"

  # The pinned submodule, by allowlist.
  if [[ -d "${VENDOR_SRC}" ]]; then
    for name in ${VENDOR_SKILLS}; do
      dir="${VENDOR_SRC}/${name}"
      if [[ ! -d "${dir}" ]]; then
        echo "  !! vendor skill not found: ${name} (submodule checked out?)" >&2
        continue
      fi
      shadowed_by_local "${name}" "${local_dirs}" && continue
      echo "${dir}"
    done
  fi

  # Declared third-party sources. Only rows that actually resolved reach here;
  # the unresolved ones were reported and counted before this ran, because a
  # count assembled inside this function would be assembled in a subshell and
  # never reach the exit status.
  while IFS=$'\t' read -r status name path source; do
    [[ "${status}" == "ok" ]] || continue
    shadowed_by_local "${name}" "${local_dirs}" && continue
    echo "${path}"
  done <<< "${MANIFEST_ROWS}"
}

# A local skill of the same name wins, so local conventions always beat an
# adopted opinion. Shared by both source kinds rather than written twice: the
# check is the same question, and two copies of it is how the two kinds would
# drift into answering it differently.
shadowed_by_local() {
  local name="$1" local_dirs="$2"
  case $'\n'"${local_dirs}"$'\n' in
    *"/${name}"$'\n'*)
      echo "  -- ${name}: vendored copy shadowed by local skill" >&2
      return 0
      ;;
  esac
  return 1
}

# Newline-delimited membership test, no subprocess and no pipeline.
in_set() {
  case $'\n'"$2"$'\n' in
    *$'\n'"$1"$'\n'*) return 0 ;;
    *) return 1 ;;
  esac
}

conflicts=0
total=0
unresolved=0

# Declared but not on disk, reported once for the run rather than once per
# install directory. Counted here in the parent shell deliberately — skill_dirs
# runs in a command substitution, so anything it incremented would be discarded
# and the run would exit 0 having installed less than was asked for.
#
# This exits non-zero, unlike the submodule's missing-skill warning above it. The
# two differ because the recoveries differ: a submodule is checked out by the
# Quickstart and its drift has its own `make doctor` check, whereas a manifest
# source is fetched by a command the operator may never have run. Reporting that
# as a warning and exiting 0 would mean "installed everything you declared" was
# indistinguishable from "installed part of it".
if [[ -n "${MANIFEST_ROWS}" ]]; then
  while IFS=$'\t' read -r status name path source; do
    [[ -n "${status}" ]] || continue
    case "${status}" in
      missing-source)
        echo "  !! ${name}: source '${source}' not fetched — run: $(say_remediation 'make fetch-skills YES=1' './scripts/fetch-skill-sources.sh --yes')" >&2
        unresolved=$((unresolved + 1))
        ;;
      missing-skill)
        echo "  !! ${name}: not in source '${source}' at ${path}" >&2
        echo "     (renamed upstream, or a typo in that source's allow list)" >&2
        unresolved=$((unresolved + 1))
        ;;
    esac
  done <<< "${MANIFEST_ROWS}"
fi

# Resolve the desired set once: it is the same for every install directory, and
# pruning needs it as data rather than as a pipeline.
DESIRED="$(skill_dirs)"

IFS=':' read -r -a targets <<< "${SKILLS_DIRS}"
for skills_home in "${targets[@]}"; do
  [[ -n "${skills_home}" ]] || continue
  echo "${skills_home}"
  [[ -d "${skills_home}" ]] || run mkdir -p "${skills_home}"

  synced=0
  while IFS= read -r skill_dir; do
    [[ -n "${skill_dir}" ]] || continue   # here-string yields one empty line for an empty set
    name="$(basename "${skill_dir}")"
    target="${skills_home}/${name}"

    # A real directory here is a divergent hand-maintained copy, not something
    # this script created. Never delete it — report and skip.
    if [[ -e "${target}" && ! -L "${target}" ]]; then
      echo "  !! ${name}: real directory, not a link — left untouched"
      echo "     compare: diff -u ${skill_dir}/SKILL.md ${target}/SKILL.md"
      conflicts=$((conflicts + 1))
      continue
    fi

    # A symlink pointing somewhere other than this repo belongs to another
    # tool (e.g. a marketplace install). Leave it alone too.
    if [[ -L "${target}" ]]; then
      current="$(cd "$(dirname "${target}")" && readlink "${target}")"
      case "${current}" in
        "${STANDARDS_DIR}"/*) ;;
        *) echo "  !! ${name}: symlink to ${current} (not ours) — left untouched"
           conflicts=$((conflicts + 1))
           continue ;;
      esac
    fi

    run ln -sfn "${skill_dir}" "${target}"
    # The full target, not one shortened to be relative to the checkout. `->`
    # is symlink notation, so printing a relative path next to it reads as a
    # relative link — and that misreading sent a reviewer building a cleanup
    # tool down a path that could never have worked, matching link text against
    # a substring that absolute links do not contain. What this prints is now
    # exactly what readlink would show.
    echo "  ${name} -> ${skill_dir}"
    synced=$((synced + 1))
  done <<< "${DESIRED}"

  # Prune links into this repo that are no longer in the desired set — either
  # the skill was removed upstream, or it was dropped from VENDOR_SKILLS.
  # Checking only for dangling links would leave a deselected vendor skill
  # installed forever, since its source directory still exists.
  for target in "${skills_home}"/*; do
    [[ -L "${target}" ]] || continue
    current="$(cd "$(dirname "${target}")" && readlink "${target}")"
    case "${current}" in
      "${STANDARDS_DIR}"/*) ;;
      *) continue ;;
    esac
    if ! in_set "${current}" "${DESIRED}"; then
      run rm -f "${target}"
      echo "  pruned: $(basename "${target}")"
    fi
  done

  echo "  ${synced} skill(s)"
  total=$((total + synced))
done

echo "Source of truth: ${SKILLS_SRC}/{workflow,...}/<skill>/"
[[ $DRY_RUN -eq 1 ]] && echo "Dry run — nothing written."
if [[ $conflicts -gt 0 ]]; then
  echo "${conflicts} conflict(s) skipped — resolve by hand, then re-run." >&2
  exit 1
fi
if [[ $unresolved -gt 0 ]]; then
  echo "${unresolved} declared skill(s) not installed — see above." >&2
  exit 1
fi
exit 0
