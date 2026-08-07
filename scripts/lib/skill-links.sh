#!/usr/bin/env bash
# shellcheck disable=SC2034  # SKILLS_DIRS_* are consumed by callers after
# sourcing this file, not read in it.
# Where skills are installed, and which of the links found there are ours.
#
# Source, don't execute. Requires ds_config_load to have run.
#
# Two tools need both answers and each used to carry only one. uninstall.sh
# knew how to judge a link but walked only the *configured* SKILLS_DIRS;
# doctor.sh walked the same narrow set and knew nothing about links at all.
# That shared blind spot is how fourteen real links became invisible to every
# tool here at once:
#
#   sync-skills.sh runs during the Quickstart *before* a machine config exists,
#   so it installs into the built-in default — both directories. The config
#   written afterwards narrows SKILLS_DIRS to one. Everything installed under
#   the wider set is now unreachable by every tool that walks the narrower one,
#   including `make uninstall`, which is the documented recovery path for the
#   dangling links a deleted checkout leaves behind.
#
# So directories resolve as the *union* of what is configured and what is built
# in, with the two kept distinguishable — nothing outside the configured set is
# ever removed without having been shown as outside it first.

# Fills three newline-delimited lists: the configured directories, the built-in
# ones that are not configured, and their union in that order. Deduplicated on
# the path with any trailing slashes removed, so ~/.claude/skills and
# ~/.claude/skills/ are one directory rather than two.
skills_dirs_load() {
  local -a conf def
  local d
  SKILLS_DIRS_CONFIGURED=""
  SKILLS_DIRS_UNCONFIGURED=""
  SKILLS_DIRS_ALL=""

  IFS=':' read -r -a conf <<< "${SKILLS_DIRS:-}"
  IFS=':' read -r -a def <<< "${SBW_SKILLS_DIRS_DEFAULT:-}"

  for d in ${conf[@]+"${conf[@]}"}; do
    d="$(skills_dir_normalize "${d}")"
    [ -n "${d}" ] || continue
    if ! skills_dir_in "${d}" "${SKILLS_DIRS_CONFIGURED}"; then
      SKILLS_DIRS_CONFIGURED="${SKILLS_DIRS_CONFIGURED}${d}"$'\n'
    fi
  done

  for d in ${def[@]+"${def[@]}"}; do
    d="$(skills_dir_normalize "${d}")"
    [ -n "${d}" ] || continue
    if skills_dir_in "${d}" "${SKILLS_DIRS_CONFIGURED}"; then continue; fi
    if skills_dir_in "${d}" "${SKILLS_DIRS_UNCONFIGURED}"; then continue; fi
    SKILLS_DIRS_UNCONFIGURED="${SKILLS_DIRS_UNCONFIGURED}${d}"$'\n'
  done

  SKILLS_DIRS_ALL="${SKILLS_DIRS_CONFIGURED}${SKILLS_DIRS_UNCONFIGURED}"
}

# Trailing slashes off, but never turn "/" into "".
skills_dir_normalize() {
  local p="$1"
  while [ "${#p}" -gt 1 ] && [ "${p%/}" != "${p}" ]; do p="${p%/}"; done
  printf '%s' "${p}"
}

skills_dir_in() {
  case $'\n'"$2" in
    *$'\n'"$1"$'\n'*) return 0 ;;
    *) return 1 ;;
  esac
}

skills_dir_is_configured() {
  skills_dir_in "$(skills_dir_normalize "$1")" "${SKILLS_DIRS_CONFIGURED}"
}

# Absolute path for a symlink's target, computed lexically. Deliberately no
# filesystem access: the whole dangling case involves targets that do not
# exist, so cd/realpath are unavailable exactly when this matters most.
skill_link_normalize_path() {
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

skill_link_target() {
  local link="$1" text dir
  text="$(readlink "${link}")"
  case "${text}" in
    /*) skill_link_normalize_path "${text}" ;;
    *)  dir="$(dirname "${link}")"
        # The link's own directory does exist, so it can be made absolute the
        # reliable way; only the target may be missing.
        dir="$(cd "${dir}" && pwd -P)"
        skill_link_normalize_path "${dir}/${text}" ;;
  esac
}

# Does a resolved target have the shape of a skill inside an engine checkout?
skill_link_engine_layout() {
  case "$1" in
    */vendor/obsidian-skills/skills/*) return 0 ;;
    */skills/*/*) return 0 ;;
    *) return 1 ;;
  esac
}

# Classify a resolved target against a checkout. Prints one of:
#
#   ours              resolves inside this checkout
#   ours-dangling     target is gone, but had this engine's skills layout
#   foreign           resolves somewhere else that exists — another tool's
#   foreign-dangling  broken, and not shaped like ours — someone else's problem
#
# Links are judged by *resolving* them, never by looking for
# "second-brain-workflow" in the link text: a relative link contains no such
# substring, and once the checkout is deleted nothing in the text can confirm
# it was ever ours. The dangling shape test is what covers that second case,
# including a skill renamed or dropped since the dead checkout installed it.
skill_link_class() {
  local target="$1" checkout="$2"
  case "${target}" in
    "${checkout}"/*) printf 'ours'; return 0 ;;
  esac
  if [ -e "${target}" ]; then
    printf 'foreign'
  elif skill_link_engine_layout "${target}"; then
    printf 'ours-dangling'
  else
    printf 'foreign-dangling'
  fi
}

# Count the links in one directory that are ours, by either route. Used where
# only the number matters (doctor); uninstall walks the entries itself because
# it has to name and remove them.
skill_links_ours_in() {
  local dir="$1" checkout="$2" entry n=0
  [ -d "${dir}" ] || { printf '0'; return 0; }
  for entry in "${dir}"/* "${dir}"/.[!.]*; do
    [ -L "${entry}" ] || continue
    case "$(skill_link_class "$(skill_link_target "${entry}")" "${checkout}")" in
      ours|ours-dangling) n=$((n + 1)) ;;
    esac
  done
  printf '%s' "${n}"
}
