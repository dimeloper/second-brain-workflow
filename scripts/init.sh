#!/usr/bin/env bash
# Set this machine up, and say what it is being set up to do.
#
#   ./init.sh                      # preview: explain, detect, print the config
#   ./init.sh --yes                # write it, then run doctor
#   ./init.sh --vault-id work      # the one value this script will not invent
#   ./init.sh --vault ~/vaults/x --targets claude-code,agents --rules-dir ~/conv/rules
#
# Exit codes:
#   0  previewed, or written
#   1  written, but something still needs a human — most often SBW_EXPECTED_VAULT_ID
#   2  refused before acting (bad arguments)
#
# Why this exists: setting up a machine was nine numbered steps in
# docs/NEW-MACHINE.md, and every other stage of the lifecycle is a verb —
# doctor, upgrade, uninstall, guard, audit. upgrade.sh was written for exactly
# this reason one stage later ("upgrading a set-up machine was seven sequenced
# commands"); the same argument applies to step zero.
#
# What it deliberately does NOT do:
#
#   - Invent SBW_EXPECTED_VAULT_ID. That key is what makes the commit guard's
#     identity check non-circular: the expectation lives on the machine, never
#     in the vault it is checking. A script that read vault.json to fill it in
#     would be answering the question the check exists to ask, and the guard
#     would then pass on any vault that brought its own answer along. Pass
#     --vault-id, or the key is left out and this exits 1 saying so.
#   - Overwrite a value in an existing config. It appends keys that are missing
#     and never touches a line that is already there — the observed failure was
#     *adding two keys to a config written months earlier*, not writing a fresh
#     one.
#   - Clone anything, or declare a skills roster. Which repo holds your rules,
#     and whether third-party skills belong on this laptop, are decisions about
#     a machine rather than steps in a setup.
set -euo pipefail

STANDARDS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/config.sh
. "${STANDARDS_DIR}/scripts/lib/config.sh"
# Loaded before anything is detected, so every "now:" and "from:" line below
# reports what the tooling would actually resolve rather than what this script
# would like it to be.
ds_config_load

YES=0
WANT_VAULT=""
WANT_TARGETS=""
WANT_RULES=""
WANT_SKILLS_DIRS=""
WANT_ID=""

while [ $# -gt 0 ]; do
  case "$1" in
    --yes|-y)     YES=1; shift ;;
    --vault)      WANT_VAULT="${2:?--vault needs a value}"; shift 2 ;;
    --vault-id)   WANT_ID="${2:?--vault-id needs a value}"; shift 2 ;;
    --targets)    WANT_TARGETS="${2:?--targets needs a value}"; shift 2 ;;
    --rules-dir)  WANT_RULES="${2:?--rules-dir needs a value}"; shift 2 ;;
    --skills-dirs) WANT_SKILLS_DIRS="${2:?--skills-dirs needs a value}"; shift 2 ;;
    -h|--help)    sed -n '2,34p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

CONFIG="$(ds_config_path)"

# One line per key, keyed off SBW_CONFIG_KEYS rather than a list written here.
# A key added to config.sh without a line below is caught by a test: a
# convention living in a script and missing from the thing a person reads is
# the failure this repo has already shipped four times.
describe_key() {
  case "$1" in
    SBW_VAULT)             echo "the Obsidian vault this machine reads and writes" ;;
    RENDER_TARGETS)        echo "which agent formats to render: cursor, claude-code, agents" ;;
    SKILLS_DIRS)           echo "where skills are installed, colon-separated like PATH" ;;
    VENDOR_SKILLS)         echo "which upstream Obsidian skills to install" ;;
    SBW_SKILLS_MANIFEST)   echo "a manifest of third-party skill sources — optional, and a decision" ;;
    SBW_RULES_DIR)         echo "where rules/*.md and AGENTS.md live, if not in this checkout" ;;
    SBW_EXPECTED_VAULT_ID) echo "the vault.json id this machine expects — the commit guard's anchor" ;;
    SBW_SCAN_ROOTS)        echo "where doctor looks for repos carrying rendered output" ;;
    SBW_SCAN_DEPTH)        echo "how deep that scan goes, counted from each root" ;;
    *)                     echo "" ;;
  esac
}

say_capabilities() {
  cat <<'TXT'
second-brain-workflow — what this machine is being set up to do

  Rules.     You write short imperative rules once, in one format. Every agent
             format is rendered from them: .cursor/rules/*.mdc, .claude/rules/
             *.md, AGENTS.md. A rule with `paths:` loads only when a matching
             file is touched; one without loads on every turn and is charged
             against a token ceiling.  ->  make explain, make render

  Vault.     An Obsidian vault of practice notes, each recording where it was
             observed. A note earns `trialing` at 2 repos and `enforced` at 3,
             and only then is it worth distilling into a rule. Promotion is a
             human decision; the tooling only reports.  ->  make audit

  Guard.     A pre-commit hook on the vault, so a practice learned on one
             machine's work cannot be committed under another's identity. This
             is the isolation boundary — rules flow outward freely, vault
             writes do not.  ->  make guard, make doctor

  Skills.    Agent skills linked into your editors, both this engine's own and
             (optionally) third-party ones you pin by sha.  ->  make sync-skills

  Health.    make doctor reports what is missing or drifted; make upgrade moves
             this checkout to a release and names every repo needing a
             re-render. Neither writes into a repo for you.

TXT
}

say_config_keys() {
  local key desc current origin
  echo "Configuration — ${CONFIG}"
  echo "  Format is KEY=value, one per line. A comment must have its own line."
  echo "  Only a leading ~ is expanded: write ~/vaults/x, never \$HOME/vaults/x."
  echo "  Precedence: CLI flag > environment > this file > built-in default."
  echo
  for key in $SBW_CONFIG_KEYS; do
    desc="$(describe_key "$key")"
    eval "current=\${$key:-}"
    origin="$(ds_origin_describe "$key")"
    printf '  %-22s %s\n' "$key" "$desc"
    printf '  %-22s   now: %s\n' "" "${current:-(unset)}"
    printf '  %-22s   from: %s\n' "" "${origin}"
  done
  echo
}

# Detection. Everything here is a fact about the disk; nothing is adopted from
# it without being printed first.
detect_targets() {
  local t=""
  [ -d "${HOME}/.cursor" ] && t="cursor"
  [ -d "${HOME}/.claude" ] && t="${t}${t:+,}claude-code"
  [ -n "$t" ] && t="${t},agents"
  echo "${t:-cursor,claude-code,agents}"
}

detect_skills_dirs() {
  # shellcheck disable=SC2088  # a literal "~/" is wanted: this string is written
  # into the config file, which expands a leading tilde itself. An absolute path
  # here would hardcode this machine's home into a file meant to be portable.
  local d=""
  # shellcheck disable=SC2088
  [ -d "${HOME}/.cursor" ] && d="~/.cursor/skills"
  # shellcheck disable=SC2088
  [ -d "${HOME}/.claude" ] && d="${d}${d:+:}~/.claude/skills"
  # shellcheck disable=SC2088
  echo "${d:-~/.cursor/skills:~/.claude/skills}"
}

detect_rules_dir() {
  local candidate resolved
  for candidate in "${HOME}"/*/rules "${STANDARDS_DIR}"/../*/rules; do
    [ -d "${candidate}" ] || continue
    resolved="$(cd "${candidate}" && pwd)"
    [ "${resolved}" != "${STANDARDS_DIR}/rules" ] || continue
    find "${resolved}" -maxdepth 1 -name '*.md' -type f 2>/dev/null | grep -q . || continue
    echo "${resolved}"
    return 0
  done
  echo ""
}

say_machine() {
  echo "This machine"
  printf '  %-24s %s\n' "config file" \
    "$([ -f "${CONFIG}" ] && echo "exists — missing keys would be appended, nothing overwritten" || echo "absent — would be created")"
  printf '  %-24s %s\n' "editors detected" "$(detect_targets)"
  local found; found="$(detect_rules_dir)"
  printf '  %-24s %s\n' "rules directory found" "${found:-none outside this checkout}"
  printf '  %-24s %s\n' "vault at SBW_VAULT" \
    "$([ -d "${SBW_VAULT}" ] && echo "${SBW_VAULT}" || echo "${SBW_VAULT} (not created yet — ./scripts/init-vault.sh)")"
  echo
}

# Written back as ~/... where the path is under HOME. config.sh expands a
# leading ~ and nothing else, so both forms work — but an absolute /Users/you
# path in a config file is one more thing that has to change when the machine
# does, and config.example is written the portable way.
tildify() {
  # shellcheck disable=SC2088  # same reason as detect_skills_dirs: producing the
  # literal ~ that config.sh will expand, not expanding one here.
  case "$1" in
    "${HOME}") echo "~" ;;
    "${HOME}/"*) echo "~/${1#"${HOME}"/}" ;;
    *) echo "$1" ;;
  esac
}

# --- the values this run would write ----------------------------------------
V_VAULT="${WANT_VAULT:-${SBW_VAULT}}"
V_TARGETS="${WANT_TARGETS:-$(detect_targets)}"
V_SKILLS="${WANT_SKILLS_DIRS:-$(detect_skills_dirs)}"
V_RULES="${WANT_RULES:-$(detect_rules_dir)}"
V_ID="${WANT_ID}"

proposed_line() {
  case "$1" in
    # Written only when the vault is really there, or when --vault named it
    # explicitly. Writing the *default* path for a vault nobody has created is
    # the plausible-looking answer: the key reads as configured and points
    # nowhere, and init-vault.sh will not correct it later because it leaves an
    # existing config file untouched. Omitted, SBW_VAULT resolves to the same
    # default anyway — so nothing changes except that the file stops claiming it.
    SBW_VAULT)             { [ -d "${V_VAULT}" ] || [ -n "${WANT_VAULT}" ]; } \
                             && echo "SBW_VAULT=$(tildify "${V_VAULT}")" ;;
    RENDER_TARGETS)        echo "RENDER_TARGETS=${V_TARGETS}" ;;
    SKILLS_DIRS)           echo "SKILLS_DIRS=${V_SKILLS}" ;;
    SBW_RULES_DIR)         [ -n "${V_RULES}" ] && echo "SBW_RULES_DIR=$(tildify "${V_RULES}")" ;;
    SBW_EXPECTED_VAULT_ID) [ -n "${V_ID}" ] && echo "SBW_EXPECTED_VAULT_ID=${V_ID}" ;;
  esac
  return 0
}

config_has_key() {
  [ -f "${CONFIG}" ] || return 1
  grep -qE "^[[:space:]]*$1[[:space:]]*=" "${CONFIG}"
}

PENDING=""
for key in SBW_VAULT RENDER_TARGETS SKILLS_DIRS SBW_RULES_DIR SBW_EXPECTED_VAULT_ID; do
  line="$(proposed_line "$key")"
  [ -n "${line}" ] || continue
  config_has_key "$key" && continue
  PENDING="${PENDING}${line}
"
done

say_capabilities
say_config_keys
say_machine

echo "Configuration this run would add"
if [ -z "${PENDING}" ]; then
  echo "  nothing — every key this script sets is already present in ${CONFIG}"
else
  printf '%s' "${PENDING}" | sed 's/^/  /'
fi
echo

# The one value never inferred. Printed whether or not it is missing, so the
# reason stays visible to the reader who did supply it — the same argument as
# printing an exemption at zero.
NEEDS_HUMAN=0
if config_has_key SBW_EXPECTED_VAULT_ID || [ -n "${V_ID}" ]; then
  echo "SBW_EXPECTED_VAULT_ID: set. It is never read from vault.json — the guard's"
  echo "  expectation lives on the machine, so a repointed or freshly cloned vault"
  echo "  cannot bring its own answer with it."
else
  NEEDS_HUMAN=1
  echo "SBW_EXPECTED_VAULT_ID: NOT SET, and this script will not choose one."
  echo "  It is what makes the commit guard's identity check non-circular. Reading"
  echo "  it from the vault's own vault.json would answer the question the check"
  echo "  exists to ask, and the guard would then pass on any vault that brought"
  echo "  its own answer along. Until it is set, guard-vault-commit.sh fails closed."
  echo "  Re-run with:  ./scripts/init.sh --vault-id <id> --yes"
fi
echo

VAULT_MISSING=0
if [ ! -d "${V_VAULT}" ] && [ -z "${WANT_VAULT}" ] && ! config_has_key SBW_VAULT; then
  VAULT_MISSING=1
  NEEDS_HUMAN=1
  echo "SBW_VAULT: no vault at ${V_VAULT}, and none named with --vault."
  echo "  Not written, because the default path for a vault nobody created reads as"
  echo "  configured and points nowhere. Create it first — init-vault.sh writes the"
  echo "  vault and its id together, which is what keeps them from disagreeing:"
  echo "    ./scripts/init-vault.sh --path ~/vaults/<id>-brain --id <id> --remote <url>"
  echo "  then re-run this. Or pass --vault <path> if it lives somewhere else."
  echo
fi

if [ "${YES}" -ne 1 ]; then
  echo "Preview only — nothing was written. Re-run with --yes (or make init YES=1)."
  exit 0
fi

if [ -n "${PENDING}" ]; then
  mkdir -p "$(dirname "${CONFIG}")"
  if [ ! -f "${CONFIG}" ]; then
    printf '# second-brain-workflow machine configuration\n# See config.example for every key. Written by init.sh.\n\n' > "${CONFIG}"
  else
    printf '\n# Appended by init.sh — existing lines were left untouched.\n' >> "${CONFIG}"
  fi
  printf '%s' "${PENDING}" >> "${CONFIG}"
  echo "Wrote ${CONFIG}:"
  sed 's/^/  /' "${CONFIG}"
else
  echo "Nothing to write."
fi
echo

echo "Now checking the machine (doctor, verbatim)"
"${STANDARDS_DIR}/scripts/doctor.sh" 2>&1 | sed 's/^/  /' || true
echo

if [ "${NEEDS_HUMAN}" -eq 1 ]; then
  echo "Setup is not finished — see the notes above:"
  [ "${VAULT_MISSING}" -eq 1 ] && echo "  - no vault yet, so SBW_VAULT was not written"
  config_has_key SBW_EXPECTED_VAULT_ID || [ -n "${V_ID}" ] || \
    echo "  - SBW_EXPECTED_VAULT_ID is unset"
  exit 1
fi
exit 0
