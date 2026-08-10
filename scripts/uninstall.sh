#!/usr/bin/env bash
# Remove the skills this engine installed, from every directory in SKILLS_DIRS
# *and* from the built-in defaults, which are not always the same set.
#
# Usage:
#   ./uninstall.sh                # print what would happen, change nothing
#   ./uninstall.sh --dry-run      # the same, said explicitly
#   ./uninstall.sh --yes          # actually remove
#
# Resetting a machine to try setup again was entirely manual, and the obvious
# cleanup does not work. How a link is judged ours, and why the directory list
# is wider than SKILLS_DIRS, both live in scripts/lib/skill-links.sh — the same
# implementation doctor.sh reports from, so the two can't disagree about what is
# installed or where.
#
# The short version: links are identified by *resolving* them, never by matching
# "second-brain-workflow" against the link text, and a directory that once held
# our links stays in scope even after the config stopped naming it.
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
# shellcheck source=scripts/lib/skill-links.sh
. "${STANDARDS_DIR}/scripts/lib/skill-links.sh"
# shellcheck source=scripts/lib/invocation.sh
. "${STANDARDS_DIR}/scripts/lib/invocation.sh"
# Only for naming the repo registry in the closing "not removed" list — this
# script never reads or writes it.
# shellcheck source=scripts/lib/registry.sh
. "${STANDARDS_DIR}/scripts/lib/registry.sh"
skills_dirs_load

APPLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --yes) APPLY=1; shift ;;
    --dry-run) APPLY=0; shift ;;
    -h|--help) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

remove=""
removed=0
kept=0
outside=0

echo "second-brain-workflow uninstall — checkout: ${STANDARDS_DIR}"
[ "${APPLY}" -eq 1 ] || echo "(preview only — nothing will be changed)"
echo

while IFS= read -r skills_home; do
  [ -n "${skills_home}" ] || continue
  # Labelled, always, and before anything under it is listed: a directory the
  # config no longer names is exactly where an install becomes invisible, so
  # --yes widening to reach it must never be something the reader discovers
  # afterwards.
  if skills_dir_is_configured "${skills_home}"; then
    echo "${skills_home}"
  else
    echo "${skills_home}  [not in SKILLS_DIRS — installed before the config narrowed it]"
  fi
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

    target="$(skill_link_target "${entry}")"

    case "$(skill_link_class "${target}" "${STANDARDS_DIR}")" in
      ours)
        echo "  REMOVE  ${name} -> ${target}"
        remove="${remove}${entry}"$'\n'
        removed=$((removed + 1))
        skills_dir_is_configured "${skills_home}" || outside=$((outside + 1))
        ;;
      ours-dangling)
        echo "  REMOVE  ${name} -> ${target} (dangling, from a deleted checkout)"
        remove="${remove}${entry}"$'\n'
        removed=$((removed + 1))
        skills_dir_is_configured "${skills_home}" || outside=$((outside + 1))
        ;;
      foreign)
        echo "  keep    ${name} -> ${target} (not ours)"
        kept=$((kept + 1))
        ;;
      *)
        echo "  keep    ${name} -> ${target} (dangling, but not ours)"
        kept=$((kept + 1))
        ;;
    esac
  done
  [ "${found}" -eq 1 ] || echo "  (empty)"
done <<EOF
${SKILLS_DIRS_ALL}
EOF

echo
if [ "${removed}" -eq 0 ]; then
  echo "Nothing of ours is installed. ${kept} entr(ies) left alone."
  exit 0
fi

# Said as its own line rather than left to be inferred from the listing above,
# because it is the one number that changes what --yes touches.
if [ "${outside}" -gt 0 ]; then
  echo "${outside} of those are outside the configured SKILLS_DIRS (marked above)."
fi

if [ "${APPLY}" -eq 0 ]; then
  echo "${removed} link(s) to remove, ${kept} left alone."
  echo "Re-run with $(say_remediation 'YES=1 (make uninstall YES=1)' '--yes') to remove them."
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
echo "the repo registry ($(sbw_registry_path)), and rendered"
echo "rules in any repo you onboarded (.cursor/rules, .claude/rules, AGENTS.md,"
echo "CLAUDE.md, .sbw-version — delete those per repo if you want them gone)."
