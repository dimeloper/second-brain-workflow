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
#   SKILLS_DIRS    colon-separated install targets
#                  (default: ~/.cursor/skills:~/.claude/skills)
#   VENDOR_SKILLS  space-separated allowlist from vendor/obsidian-skills
set -euo pipefail

STANDARDS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILLS_SRC="${STANDARDS_DIR}/cursor-skills"

# shellcheck source=scripts/lib/config.sh
. "${STANDARDS_DIR}/scripts/lib/config.sh"
ds_config_load

# Upstream skills (kepano/obsidian-skills, MIT, pinned submodule). Installed by
# allowlist rather than wholesale: json-canvas and defuddle are unrelated to this
# vault, and obsidian-cli is only useful once the Obsidian CLI is on PATH.
VENDOR_SRC="${STANDARDS_DIR}/vendor/obsidian-skills/skills"

DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

[[ -d "${SKILLS_SRC}" ]] || { echo "Missing ${SKILLS_SRC}" >&2; exit 1; }

run() { if [[ $DRY_RUN -eq 1 ]]; then echo "    would: $*"; else "$@"; fi; }

# Skill source dirs, one per line. Local skills first; a vendored skill sharing
# a name with a local one is shadowed, so local conventions always win.
#
# Note: never pipe this into `grep -q` under `set -o pipefail`. grep -q exits on
# the first match, the producer takes SIGPIPE, and the pipeline reports failure
# even though the match succeeded. Capture the output and match in-shell.
skill_dirs() {
  local local_dirs name dir
  local_dirs="$(find "${SKILLS_SRC}" -mindepth 2 -maxdepth 2 -type d | sort)"
  printf '%s\n' "${local_dirs}"
  [[ -d "${VENDOR_SRC}" ]] || return 0
  for name in ${VENDOR_SKILLS}; do
    dir="${VENDOR_SRC}/${name}"
    if [[ ! -d "${dir}" ]]; then
      echo "  !! vendor skill not found: ${name} (submodule checked out?)" >&2
      continue
    fi
    case $'\n'"${local_dirs}"$'\n' in
      *"/${name}"$'\n'*)
        echo "  -- ${name}: vendored copy shadowed by local skill" >&2
        continue
        ;;
    esac
    echo "${dir}"
  done
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
    echo "  ${name} -> ${skill_dir#"${STANDARDS_DIR}/"}"
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
exit 0
