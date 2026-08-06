#!/usr/bin/env bash
# Remove the skills this engine installed, from every directory in SKILLS_DIRS.
#
# Usage:
#   ./uninstall.sh                # print what would happen, change nothing
#   ./uninstall.sh --dry-run      # the same, said explicitly
#   ./uninstall.sh --yes          # actually remove
#
# Resetting a machine to try setup again was entirely manual, and the obvious
# cleanup does not work. Links are identified by resolving each one to an
# absolute path and comparing it against this checkout — never by looking for
# "second-brain-workflow" in the link text:
#
#   - A relative link ("../../elsewhere/thing") contains no such substring, so a
#     substring match misses it while resolving it finds it.
#   - Once the checkout has been deleted, the path a stale link names no longer
#     exists, so nothing can confirm by inspection that it was ever ours. That is
#     the state a reset leaves behind: fourteen dangling links across two skills
#     directories, identifiable only by their targets failing to resolve.
#
# So there are two ways a link is judged ours, and nothing else counts:
#   1. it resolves to a path inside this checkout, or
#   2. it is broken *and* its target has this engine's skills layout
#      (.../skills/<category>/<name> or .../vendor/obsidian-skills/skills/<name>)
#
# (2) covers the dangling case without a checkout to compare against, including
# a skill that was renamed or dropped since the dead checkout was installed from.
# A broken link that matches neither is reported and left alone — it belongs to
# something else that is also broken, which is not this script's business.
#
# What it never touches: a real directory (a hand-maintained skill), a symlink
# resolving anywhere outside this checkout (another tool's install, e.g.
# Railway's use-railway), the skills directories themselves, any vault, the
# machine config file, and rendered rules in target repos. It only ever removes
# symlinks, and only ones it can positively account for.
set -euo pipefail

STANDARDS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/config.sh
. "${STANDARDS_DIR}/scripts/lib/config.sh"
ds_config_load

APPLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --yes) APPLY=1; shift ;;
    --dry-run) APPLY=0; shift ;;
    -h|--help) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

# Absolute path for a symlink's target, computed lexically. Deliberately no
# filesystem access: the whole dangling case involves targets that do not exist,
# so cd/realpath are unavailable exactly when this matters most.
normalize_path() {
  local p="$1" out="" seg
  local IFS='/'
  set -f
  for seg in $p; do
    case "${seg}" in
      ''|.) ;;
      ..) out="${out%/*}" ;;
      *) out="${out}/${seg}" ;;
    esac
  done
  set +f
  printf '%s' "${out:-/}"
}

resolve_link() {
  local link="$1" text dir
  text="$(readlink "${link}")"
  case "${text}" in
    /*) normalize_path "${text}" ;;
    *)  dir="$(dirname "${link}")"
        # The link's own directory does exist, so it can be made absolute the
        # reliable way; only the target may be missing.
        dir="$(cd "${dir}" && pwd -P)"
        normalize_path "${dir}/${text}" ;;
  esac
}

# Does a resolved target have the shape of a skill inside an engine checkout?
engine_layout() {
  case "$1" in
    */vendor/obsidian-skills/skills/*) return 0 ;;
    */skills/*/*) return 0 ;;
    *) return 1 ;;
  esac
}

remove=""
removed=0
kept=0

echo "second-brain-workflow uninstall — checkout: ${STANDARDS_DIR}"
[ "${APPLY}" -eq 1 ] || echo "(preview only — nothing will be changed)"
echo

IFS=':' read -r -a dirs <<< "${SKILLS_DIRS}"
for skills_home in "${dirs[@]}"; do
  [ -n "${skills_home}" ] || continue
  echo "${skills_home}"
  if [ ! -d "${skills_home}" ]; then
    echo "  (no such directory)"
    continue
  fi

  found=0
  for entry in "${skills_home}"/* "${skills_home}"/.[!.]*; do
    # The globs above yield their own pattern when nothing matches; a symlink
    # is -L even when broken, which -e is not.
    [ -e "${entry}" ] || [ -L "${entry}" ] || continue
    found=1
    name="$(basename "${entry}")"

    if [ ! -L "${entry}" ]; then
      echo "  keep    ${name} — a real directory, not a link"
      kept=$((kept + 1))
      continue
    fi

    target="$(resolve_link "${entry}")"

    case "${target}" in
      "${STANDARDS_DIR}"/*)
        echo "  REMOVE  ${name} -> ${target}"
        remove="${remove}${entry}"$'\n'
        removed=$((removed + 1))
        continue
        ;;
    esac

    if [ -e "${target}" ]; then
      echo "  keep    ${name} -> ${target} (not ours)"
      kept=$((kept + 1))
    elif engine_layout "${target}"; then
      echo "  REMOVE  ${name} -> ${target} (dangling, from a deleted checkout)"
      remove="${remove}${entry}"$'\n'
      removed=$((removed + 1))
    else
      echo "  keep    ${name} -> ${target} (dangling, but not ours)"
      kept=$((kept + 1))
    fi
  done
  [ "${found}" -eq 1 ] || echo "  (empty)"
done

echo
if [ "${removed}" -eq 0 ]; then
  echo "Nothing of ours is installed. ${kept} entr(ies) left alone."
  exit 0
fi

if [ "${APPLY}" -eq 0 ]; then
  echo "${removed} link(s) to remove, ${kept} left alone."
  echo "Re-run with --yes to remove them."
  exit 0
fi

while IFS= read -r link; do
  [ -n "${link}" ] || continue
  rm -f "${link}"
done <<EOF
${remove}
EOF

echo "Removed ${removed} link(s). ${kept} entr(ies) left alone."
echo
echo "Not removed, by design: your vault(s), $(ds_config_path),"
echo "and rendered rules in any repo you onboarded (.cursor/rules, .claude/rules,"
echo "AGENTS.md, CLAUDE.md, .sbw-version — delete those per repo if you want them gone)."
