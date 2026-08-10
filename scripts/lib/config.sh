#!/usr/bin/env bash
# Config resolution for shell consumers. Source, don't execute.
#
#   . "$(dirname "$0")/lib/config.sh"
#   ds_config_load
#   echo "$SBW_VAULT"
#
# Precedence: existing environment wins over the config file, which wins over
# defaults. CLI flags are the caller's job — parse them after loading.
# Keep in step with lib/config.py; both implement the same eight keys.

SBW_CONFIG_KEYS="SBW_VAULT RENDER_TARGETS SKILLS_DIRS VENDOR_SKILLS SBW_RULES_DIR SBW_EXPECTED_VAULT_ID SBW_SCAN_ROOTS SBW_SCAN_DEPTH"

ds_config_path() {
  local base="${XDG_CONFIG_HOME:-$HOME/.config}"
  echo "${SBW_CONFIG_FILE:-$base/second-brain-workflow/config}"
}

# Expand a leading ~ only. Deliberately not eval: a config file should not be
# able to run commands.
ds_expand_tilde() {
  # shellcheck disable=SC2088  # the "~/" below is a literal case pattern being
  # matched, not a path we expect the shell to expand — expanding it is the point.
  case "$1" in
    "~") echo "$HOME" ;;
    "~/"*) echo "$HOME/${1#\~/}" ;;
    *) echo "$1" ;;
  esac
}

# Human phrase for where a key's value came from, for an error message that
# tells the reader which knob to reach for. Requires ds_config_load to have
# run — it records <KEY>_ORIGIN as it resolves.
ds_origin_describe() {
  local key="$1" origin
  eval "origin=\${${key}_ORIGIN:-}"
  case "$origin" in
    environment) echo "the ${key} environment variable" ;;
    config)      echo "${key} in $(ds_config_path)" ;;
    *)           echo "the built-in default (no ${key} in $(ds_config_path))" ;;
  esac
}

ds_config_load() {
  local file key value line
  file="$(ds_config_path)"

  # Snapshot provenance before anything is resolved: once the file has been
  # read there is no way to tell a value that arrived from the environment
  # from one this function assigned.
  for key in $SBW_CONFIG_KEYS; do
    eval "is_set=\${$key+set}"
    if [ "${is_set:-}" = "set" ]; then
      eval "${key}_ORIGIN=environment"
    else
      eval "${key}_ORIGIN="
    fi
  done

  if [ -f "$file" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      case "$line" in
        ''|'#'*) continue ;;
      esac
      key="${line%%=*}"
      value="${line#*=}"
      [ "$key" = "$line" ] && continue          # no '=' on the line
      key="$(echo "$key" | tr -d '[:space:]')"
      value="${value%"${value##*[![:space:]]}"}"  # rstrip
      value="${value#"${value%%[![:space:]]*}"}"  # lstrip
      case " $SBW_CONFIG_KEYS " in
        *" $key "*) ;;
        *) echo "warning: $file: unknown key '$key'" >&2; continue ;;
      esac
      # Environment wins. Set-but-empty counts as set: an explicitly empty
      # value is a deliberate "none", not a request for the default.
      eval "is_set=\${$key+set}"
      [ "${is_set:-}" = "set" ] && continue
      eval "$key=\$(ds_expand_tilde \"\$value\")"
      eval "export $key"
      eval "${key}_ORIGIN=config"
    done < "$file"
  fi

  # Anything still unaccounted for is about to take its built-in default.
  for key in $SBW_CONFIG_KEYS; do
    eval "origin=\${${key}_ORIGIN:-}"
    [ -n "${origin:-}" ] || eval "${key}_ORIGIN=default"
  done

  # Defaults, applied only when a key is genuinely unset.
  [ -n "${SBW_VAULT+set}" ] || SBW_VAULT="$HOME/vaults/second-brain"
  [ -n "${RENDER_TARGETS+set}" ]      || RENDER_TARGETS="cursor,claude-code,agents"
  # Named, not inlined: uninstall.sh and doctor.sh have to union the configured
  # value against this to see installs that predate a narrowed config, and a
  # second copy of the pair is exactly the drift that would reopen the hole.
  SBW_SKILLS_DIRS_DEFAULT="$HOME/.cursor/skills:$HOME/.claude/skills"
  [ -n "${SKILLS_DIRS+set}" ]         || SKILLS_DIRS="${SBW_SKILLS_DIRS_DEFAULT}"
  [ -n "${VENDOR_SKILLS+set}" ]       || VENDOR_SKILLS="obsidian-bases obsidian-markdown"
  [ -n "${SBW_RULES_DIR+set}" ] || SBW_RULES_DIR=""
  # Empty by design — there is no sensible default "expected id". A guard
  # that fell back to something here would defeat the point of it; unset
  # means "not configured yet," and callers that care must fail closed on it.
  [ -n "${SBW_EXPECTED_VAULT_ID+set}" ] || SBW_EXPECTED_VAULT_ID=""
  # Where sbw_scan_rendered_repos looks, and how deep. Authoritative here rather
  # than in lib/registry.sh: a scan whose boundary can be configured has to read
  # that boundary the same way every other setting is read, or the config file
  # stops being the place a machine is described. registry.sh carries matching
  # fallbacks for the case where it is sourced without ds_config_load, and
  # tests/test-registry-scan.sh asserts the two agree.
  [ -n "${SBW_SCAN_ROOTS+set}" ] || SBW_SCAN_ROOTS="$HOME"
  [ -n "${SBW_SCAN_DEPTH+set}" ] || SBW_SCAN_DEPTH="5"
  export SBW_VAULT RENDER_TARGETS SKILLS_DIRS VENDOR_SKILLS SBW_RULES_DIR SBW_EXPECTED_VAULT_ID
  export SBW_SCAN_ROOTS SBW_SCAN_DEPTH
  export SBW_SKILLS_DIRS_DEFAULT
}
