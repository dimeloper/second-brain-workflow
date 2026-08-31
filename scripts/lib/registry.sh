#!/usr/bin/env bash
# The set of repos this machine has rendered into, and how. Source, don't execute.
#
#   . "$(dirname "$0")/lib/registry.sh"
#   sbw_registry_path                 # where the list lives
#   sbw_registry_read                 # one absolute path per line
#   sbw_registry_mode PATH            # the recorded render mode, or "" if none
#   sbw_registry_excluded DIR         # does DIR carry our .git/info/exclude block?
#   sbw_registry_mode_effective DIR   # recorded mode, else inferred, else unknown
#   sbw_registry_marker_present DIR   # does DIR still carry rendered output?
#   sbw_scan_rendered_repos           # which repos on this machine do, found
#   sbw_scan_scope_line               # ...and the boundary that answer holds in
#
# Written by render.py (scripts/lib/registry.py) on a successful render, read
# here by doctor.sh. Why it exists at all is documented there; the short
# version is that nothing on the machine recorded where the engine had
# rendered, so "re-render everything after an upgrade" had to guess a glob —
# and a glob that matches nothing looks exactly like a machine that has
# onboarded nothing.
#
# An entry is an absolute path, optionally followed by TAB-separated key=value
# fields — today only `mode=local` / `mode=shared`. sbw_registry_read yields the
# path alone, so every caller that only wants the repo set is unaffected by the
# field ever having been added.
#
# Keep in step with lib/registry.py: same path, same format. Deliberately not
# the machine config file (that parser does not strip trailing comments, and
# this is a list, not key/value), and deliberately not redirected by
# SBW_CONFIG_FILE, which names the config file rather than a config directory.

sbw_registry_path() {
  local base="${XDG_CONFIG_HOME:-$HOME/.config}"
  echo "${base}/second-brain-workflow/repos"
}

# Whole entries, fields and all. Blank lines and comments are stripped, so a
# hand-seeded file can be annotated.
sbw_registry_read_entries() {
  local file line
  file="$(sbw_registry_path)"
  [ -f "${file}" ] || return 0
  while IFS= read -r line || [ -n "${line}" ]; do
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    case "${line}" in
      ''|'#'*) continue ;;
    esac
    printf '%s\n' "${line}"
  done < "${file}"
}

# One absolute path per line — the field list, if any, cut off at the first tab.
# Every existing caller reads the repo set through this, so recording a mode
# beside the path could not change what any of them sees.
sbw_registry_read() {
  local line
  while IFS= read -r line; do
    [ -n "${line}" ] || continue
    printf '%s\n' "${line%%$'\t'*}"
  done <<EOF
$(sbw_registry_read_entries)
EOF
}

# The mode recorded for one path, or "" when the line carries none. Empty is
# *unknown*, not shared: every line written before the field existed has no
# mode, and reading those as shared is the silent switch the field exists to
# stop. sbw_registry_mode_effective below is what a caller usually wants.
sbw_registry_mode() {
  local want="$1" line path rest field
  while IFS= read -r line; do
    [ -n "${line}" ] || continue
    path="${line%%$'\t'*}"
    [ "${path}" = "${want}" ] || continue
    rest="${line#"${path}"}"
    while [ -n "${rest}" ]; do
      rest="${rest#$'\t'}"
      field="${rest%%$'\t'*}"
      rest="${rest#"${field}"}"
      case "${field}" in
        mode=*) printf '%s\n' "${field#mode=}"; return 0 ;;
      esac
    done
    return 0
  done <<EOF
$(sbw_registry_read_entries)
EOF
  return 0
}

# Mirrors EXCLUDE_HEADER in scripts/render.py — matched on its stable prefix, so
# the sentence may be reworded without this stopping to match. The block in a
# clone's .git/info/exclude was for three releases the *only* record that a repo
# was rendered with --local, and adopt.sh's private grep for it was the only
# reader. One definition here instead: the mode question now has one answer
# whoever asks it.
SBW_EXCLUDE_MARKER="second-brain-workflow: rendered locally"

sbw_registry_excluded() {
  grep -qF "${SBW_EXCLUDE_MARKER}" "$1/.git/info/exclude" 2>/dev/null
}

# What mode a render of this repo should use: local | shared | unknown.
#
# The recorded field wins, because it is declared. Absent, the exclude block is
# the fallback — inference, but honest inference about a repo we did render, and
# it is what stops a registry line written before the field existed from reading
# as a decision to share. `unknown` is only for a repo we have no line for and
# no block in: a first render, where the flags decide and nothing is overridden.
sbw_registry_mode_effective() {
  local repo="$1" real recorded
  real="$(cd "${repo}" 2>/dev/null && pwd -P)" || real=""
  [ -n "${real}" ] || real="${repo}"
  recorded="$(sbw_registry_mode "${real}")"
  if [ -n "${recorded}" ]; then
    printf '%s\n' "${recorded}"
    return 0
  fi
  if sbw_registry_excluded "${repo}"; then
    echo local
  elif [ -n "$(sbw_registry_mode_line "${real}")" ]; then
    # Registered, no mode field, no exclude block: rendered before the field
    # existed and not rendered locally, which is `shared` and not an unknown.
    echo shared
  else
    echo unknown
  fi
}

# Does the registry name this path at all? Separate from the mode lookup because
# "registered with no mode" and "not registered" are different answers.
sbw_registry_mode_line() {
  local want="$1" line
  while IFS= read -r line; do
    [ -n "${line}" ] || continue
    [ "${line}" = "${want}" ] || continue
    printf '%s\n' "${line}"
    return 0
  done <<EOF
$(sbw_registry_read)
EOF
  return 0
}

# Mirrors MARKER in scripts/render.py. tests/test-repo-registry.sh asserts the
# two strings are identical, so this copy cannot drift into never matching.
SBW_RENDER_MARKER="generated by second-brain-workflow@"

# Is this still a repo the engine rendered into? `.sbw-version` first: it is
# written on every successful render regardless of RENDER_TARGETS, so a
# cursor-only repo (no AGENTS.md, no CLAUDE.md) is not mistaken for a stale
# entry. The marker files are the fallback for a repo rendered by an engine old
# enough not to have written it.
sbw_registry_marker_present() {
  local repo="$1" f
  [ -f "${repo}/.sbw-version" ] && return 0
  for f in AGENTS.md CLAUDE.md; do
    [ -f "${repo}/${f}" ] || continue
    grep -qF "${SBW_RENDER_MARKER}" "${repo}/${f}" 2>/dev/null && return 0
  done
  return 1
}

# --- the second source ------------------------------------------------------
#
# The registry cannot answer "which repos on this machine are onboarded". It
# only knows what a render told it, so one render on a machine with twelve
# pre-registry repos reads as complete coverage: one entry, present, rendered,
# nothing to report. The direction that actually matters — a repo carrying
# rendered output that the registry does not name — needs a second source.
#
# What replaced: a `find` command that doctor and upgrade.sh each printed for
# the reader to run. Two copies of one rule is one copy too many, and both had
# drifted from sbw_registry_marker_present above — they matched AGENTS.md
# carrying the marker and nothing else, so a repo whose AGENTS.md is
# hand-written (render.py leaves those alone, by design) or absent entirely
# (RENDER_TARGETS=cursor) was invisible to the remediation while being visible
# to every other registry check. On such a machine the command printed nothing,
# which reads as "onboarded nothing at all".
#
# What this cannot do is claim completeness: a repo on another volume, or nested
# deeper than the depth limit, is outside it. So the scope travels with the
# answer (sbw_scan_scope_line), and a root that could not be read is named
# rather than dropped — coverage that went unmeasured must never present as
# measured. A declared boundary is a different object from an unknown.
#
# Defaults: lib/config.sh is authoritative, so a machine sets these the way it
# sets everything else. The fallbacks here exist only for the case where this
# file is sourced without ds_config_load, and tests/test-registry-scan.sh
# asserts the two spellings of each default agree.
SBW_SCAN_ROOTS_FALLBACK="${HOME}"
SBW_SCAN_DEPTH_FALLBACK="5"

sbw_scan_roots_configured() { printf '%s' "${SBW_SCAN_ROOTS:-${SBW_SCAN_ROOTS_FALLBACK}}"; }
sbw_scan_depth_configured() { printf '%s' "${SBW_SCAN_DEPTH:-${SBW_SCAN_DEPTH_FALLBACK}}"; }

# The scope as declared, not as achieved: a root that turned out to be
# unreadable is reported separately, by name, so a reader sees both facts rather
# than a scope line quietly shrinking to match a failure.
sbw_scan_scope_line() {
  echo "roots=$(sbw_scan_roots_configured) depth=$(sbw_scan_depth_configured)"
}

# The boundary printed alongside an answer, rather than left to a header several
# lines up. It lives here, next to the scope string both callers already take
# from sbw_scan_scope_line, because it existed twice — once in doctor.sh and once
# in upgrade.sh — and the two copies had already drifted at birth: one closed
# with "does not appear above", the other with "is not covered". Two copies of a
# disclosure is how one of them quietly ends up disclosing something else.
#
# Takes no argument on purpose: reading the scope itself means a caller cannot
# print one scope while having scanned another.
sbw_scan_say_scope() {
  echo "        scanned scope: $(sbw_scan_scope_line)"
  echo "        (a repo outside it — another volume, nested deeper — is not covered)"
}

# One root. Both branches print a *file*, so the caller takes the dirname of
# everything and gets the repo directory either way.
#
# `-name Library -prune` is load-bearing on macOS and must not be tidied out of
# this list: ~/Library/Mobile Documents is iCloud Drive, and grepping a file
# that iCloud has offloaded faults it in. Dropping it turns `doctor` into a
# multi-gigabyte download.
#
# `-exec grep -l {} +` rather than `| xargs grep -l`: with nothing to feed it,
# BSD xargs runs grep with no file arguments, grep reads stdin, and the pipeline
# hangs — on precisely the machine that has nothing to find. That trap is why
# the printed command it replaces was already once rewritten.
#
# No -follow: a symlinked tree would be walked twice and reported under a path
# that is not where the repo lives.
sbw_scan_one_root() {
  local root="$1" depth="$2" f
  find "${root}" -maxdepth "${depth}" \
    -type d \( -name node_modules -o -name Library -o -name .git -o -name vaults \) -prune \
    -o -type f -name .sbw-version -print \
    -o -type f \( -name AGENTS.md -o -name CLAUDE.md \) \
       -exec grep -lF -- "${SBW_RENDER_MARKER}" {} + \
    2>/dev/null |
  while IFS= read -r f; do
    [ -n "${f}" ] || continue
    printf '%s\n' "$(dirname "${f}")"
  done
}

# Root validation, kept separate from the walk below on purpose. Everything it
# learns is state, and state does not survive a command substitution: a caller
# writing `scan="$(sbw_scan_rendered_repos)"` would silently drop the record of
# which roots could not be read, which is the one fact that stops unmeasured
# coverage from presenting as measured. So the diagnostics live here, the walk
# stays pure and safe to capture, and neither has to warn the reader about the
# other.
#
# Sets:
#   SBW_SCAN_USABLE_ROOTS  one realpath per line, deduplicated
#   SBW_SCAN_SKIPPED       one "root — reason" per line
#   SBW_SCAN_USABLE        how many roots survived; 0 means there is no second
#                          source at all, the only genuinely undetermined state
#
# Initialised at source time as well, so `set -u` cannot trip a caller that
# reads them before calling anything.
SBW_SCAN_USABLE_ROOTS=""
SBW_SCAN_SKIPPED=""
SBW_SCAN_USABLE=0

sbw_scan_prepare_roots() {
  local roots root real
  local -a root_list
  roots="$(sbw_scan_roots_configured)"
  SBW_SCAN_USABLE_ROOTS=""
  SBW_SCAN_SKIPPED=""
  SBW_SCAN_USABLE=0

  IFS=':' read -r -a root_list <<< "${roots}"
  # A zero-element array expanded as "${root_list[@]}" is an unbound-variable
  # error under `set -u` on bash before 4.4 — which is what the bash32 CI job
  # runs, and what ships on macOS. sbw_scan_roots_configured uses `:-`, so a
  # config key that is present but empty still yields the fallback and this stays
  # unreachable; the guard is here so that `:-` is not the only thing between a
  # future edit and a doctor that dies on such a machine.
  [ "${#root_list[@]}" -gt 0 ] || return 0
  for root in "${root_list[@]}"; do
    [ -n "${root}" ] || continue
    if [ ! -d "${root}" ]; then
      SBW_SCAN_SKIPPED="${SBW_SCAN_SKIPPED}${root} — no such directory
"
      continue
    fi
    # -x as well as -r: a directory needs both to be walked, and from outside the
    # two failures read identically.
    if [ ! -r "${root}" ] || [ ! -x "${root}" ]; then
      SBW_SCAN_SKIPPED="${SBW_SCAN_SKIPPED}${root} — not readable
"
      continue
    fi
    real="$(cd "${root}" 2>/dev/null && pwd -P)"
    if [ -z "${real}" ]; then
      SBW_SCAN_SKIPPED="${SBW_SCAN_SKIPPED}${root} — could not be resolved
"
      continue
    fi
    # The same directory named twice, or once directly and once through a
    # symlink, is one root.
    case "
${SBW_SCAN_USABLE_ROOTS}" in
      *"
${real}
"*) continue ;;
    esac
    SBW_SCAN_USABLE_ROOTS="${SBW_SCAN_USABLE_ROOTS}${real}
"
    SBW_SCAN_USABLE=$((SBW_SCAN_USABLE + 1))
  done
  return 0
}

# One absolute realpath per line, sorted and deduplicated. Pure: safe to capture
# in a command substitution, which is why the diagnostics are not here.
#
# Calls sbw_scan_prepare_roots itself so there is no order to get wrong; it is a
# handful of stat calls, and a caller that wants the diagnostics simply calls it
# first as well.
sbw_scan_rendered_repos() {
  local depth root found=""
  depth="$(sbw_scan_depth_configured)"
  sbw_scan_prepare_roots

  while IFS= read -r root; do
    [ -n "${root}" ] || continue
    found="${found}$(sbw_scan_one_root "${root}" "${depth}")
"
  done <<EOF
${SBW_SCAN_USABLE_ROOTS}
EOF

  # sort -u over the results, not just over the roots: nested roots ($HOME and
  # $HOME/dev) are two different realpaths that find the same repo twice, so
  # deduplicating roots alone would not be enough.
  printf '%s' "${found}" | grep -v '^[[:space:]]*$' | LC_ALL=C sort -u
  return 0
}

# --- the third direction ----------------------------------------------------
#
# Both sources above ask the same question — does this repo carry our rendered
# output — so both answer no for a repo whose rendered output has stopped being
# readable. It is not registered (nothing registered it), it is not found by the
# scan (no marker survives to match), and it is therefore not in the denominator
# of any count either one prints. A repo whose rules broke does not report as
# broken. It reports as out of scope, and the run goes green.
#
# That is how a repo here spent two weeks loading nothing: four `.cursor/rules`
# symlinks into `~/dev-standards`, the engine's own name before the rebrand,
# every one of them dangling from the moment the directory was renamed. Every
# check on this machine passed throughout, because each one had already decided
# the repo was not its business.
#
# What is reported is deliberately narrow: a rule file that cannot be read *at
# all*. A dangling symlink delivers nothing to any agent regardless of who wrote
# it or which tool rendered it, so the finding needs no claim about ownership —
# which is what keeps a hand-written `.cursor/rules/*.mdc`, the common and
# correct case, from being called a fault. A regular file whose content is
# merely stale is a different question, and `render.py --check` already answers
# that one for repos it knows about.
#
# Not folded into sbw_scan_one_root: that walk answers "is this repo onboarded"
# and its callers count what it returns. A broken repo added to that return
# would inflate the onboarded count with repos that are onboarded to nothing.
sbw_scan_broken_rules_one_root() {
  local root="$1" depth="$2" f
  # depth + 3, not depth: a rule file sits three levels below its repo
  # (`.cursor/rules/x.mdc`), so reusing the repo depth here would search a
  # strictly shallower set of repos than the marker scan does — the same
  # silently-narrowed coverage this check exists to catch, reintroduced one
  # directory at a time.
  find "${root}" -maxdepth "$((depth + 3))" \
    -type d \( -name node_modules -o -name Library -o -name .git -o -name vaults \) -prune \
    -o -type l -path '*/.cursor/rules/*' -print \
    -o -type l -path '*/.claude/rules/*' -print \
    2>/dev/null |
  while IFS= read -r f; do
    [ -n "${f}" ] || continue
    # `if`, not `[ -e "${f}" ] && continue`: under `set -e` a bare AND-list
    # whose left side fails is a failed command, and the loop would exit on the
    # first *intact* symlink it saw — leaving a check that only ever reports
    # findings when the very first file is already broken.
    if [ -e "${f}" ]; then continue; fi
    printf '%s\t%s\n' "$(dirname "$(dirname "$(dirname "${f}")")")" "${f}"
  done
}

# One "repo<TAB>dangling-file" per line, sorted. Pure, like
# sbw_scan_rendered_repos, and prepares roots itself for the same reason.
sbw_scan_broken_rules() {
  local depth root found=""
  depth="$(sbw_scan_depth_configured)"
  sbw_scan_prepare_roots

  while IFS= read -r root; do
    [ -n "${root}" ] || continue
    found="${found}$(sbw_scan_broken_rules_one_root "${root}" "${depth}")
"
  done <<EOF
${SBW_SCAN_USABLE_ROOTS}
EOF

  # `|| true` on the filter: with nothing found, `grep -v` matches nothing and
  # exits 1, which under pipefail is a failed command substitution on precisely
  # the machine that has nothing wrong with it.
  printf '%s' "${found}" | grep -v '^[[:space:]]*$' | LC_ALL=C sort -u || true
  return 0
}
