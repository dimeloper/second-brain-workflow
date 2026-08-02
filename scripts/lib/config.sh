#!/usr/bin/env bash
# Config resolution for shell consumers. Source, don't execute.
#
#   . "$(dirname "$0")/lib/config.sh"
#   ds_config_load
#   echo "$SBW_VAULT"
#
# Precedence: existing environment wins over the config file, which wins over
# defaults. CLI flags are the caller's job — parse them after loading.
# Keep in step with lib/config.py; both implement the same five keys.

SBW_CONFIG_KEYS="SBW_VAULT RENDER_TARGETS SKILLS_DIRS VENDOR_SKILLS SBW_RULES_DIR"

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

ds_config_load() {
  local file key value line
  file="$(ds_config_path)"

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
    done < "$file"
  fi

  # Defaults, applied only when a key is genuinely unset.
  [ -n "${SBW_VAULT+set}" ] || SBW_VAULT="$HOME/vaults/second-brain"
  [ -n "${RENDER_TARGETS+set}" ]      || RENDER_TARGETS="cursor,claude-code,agents"
  [ -n "${SKILLS_DIRS+set}" ]         || SKILLS_DIRS="$HOME/.cursor/skills:$HOME/.claude/skills"
  [ -n "${VENDOR_SKILLS+set}" ]       || VENDOR_SKILLS="obsidian-bases obsidian-markdown"
  [ -n "${SBW_RULES_DIR+set}" ] || SBW_RULES_DIR=""
  export SBW_VAULT RENDER_TARGETS SKILLS_DIRS VENDOR_SKILLS SBW_RULES_DIR
}
