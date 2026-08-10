#!/usr/bin/env bash
# Machine health check: read-only, none of it overlapping with
# `make audit` (content) or `make check` (code):
#   - the vault's commit guard is wired in as a pre-commit hook, and it's ours
#   - commits here would be authored as the identity vault.json declares
#   - a skill installed into one configured skills dir isn't missing from another
#   - a vendored submodule isn't left at the wrong commit after a tag switch
#   - every repo the registry names still exists, and still carries rendered output
#   - every repo on this machine that carries rendered output is in the registry
# Changes nothing. Not part of `make check` — like `make guard` and
# `make vault-index-check`, it needs a real vault, and CI has none.
#
#   ./doctor.sh [--vault PATH]
#
# Exit codes:
#   0  everything checked out
#   1  warnings only — setup is unfinished, but nothing is misconfigured
#   2  at least one error — something is configured wrong and no amount of
#      finishing setup will fix it
#
# Warnings stay non-zero deliberately. Every check here exists to surface a
# state nothing else surfaces — a stale submodule still renders fine, a skill
# missing from one skills dir is invisible from the other agent — so a
# scheduled run that exited 0 on those findings would be decorative. What was
# actually wrong was one message and one severity covering two different
# problems; splitting "your configuration points nowhere" (2) from "setup
# isn't finished yet" (1) is what a reader mid-setup needed.
set -euo pipefail

STANDARDS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/config.sh
. "${STANDARDS_DIR}/scripts/lib/config.sh"
# shellcheck source=scripts/lib/vault-state.sh
. "${STANDARDS_DIR}/scripts/lib/vault-state.sh"
# shellcheck source=scripts/lib/author-identity.sh
. "${STANDARDS_DIR}/scripts/lib/author-identity.sh"
# shellcheck source=scripts/lib/skill-links.sh
. "${STANDARDS_DIR}/scripts/lib/skill-links.sh"
# shellcheck source=scripts/lib/invocation.sh
. "${STANDARDS_DIR}/scripts/lib/invocation.sh"
# shellcheck source=scripts/lib/vault-identity.sh
. "${STANDARDS_DIR}/scripts/lib/vault-identity.sh"
# shellcheck source=scripts/lib/registry.sh
. "${STANDARDS_DIR}/scripts/lib/registry.sh"
ds_config_load
skills_dirs_load

VAULT="${SBW_VAULT}"
VAULT_ORIGIN="$(ds_origin_describe SBW_VAULT)"
while [ $# -gt 0 ]; do
  case "$1" in
    --vault)
      VAULT="${2:?--vault needs a value}"
      VAULT_ORIGIN="the --vault flag"
      shift 2
      ;;
    # The whole header block, line 2 to the last comment line before `set`. A
    # line count is a thing that rots: it used to stop at 20, then 21, cutting
    # the closing paragraph mid-sentence each time a bullet was added.
    # tests/test-registry-scan.sh asserts the final line still reaches the
    # reader, so the next edit here cannot truncate it silently.
    -h|--help) sed -n '2,27p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

problems=0
errors=0
ok()   { echo "  ok    $1"; }
warn() { echo "  warn  $1"; problems=$((problems + 1)); }
err()  { echo "  ERROR $1"; problems=$((problems + 1)); errors=$((errors + 1)); }

HOOK_MARKER="# second-brain-workflow: vault-commit guard"

# A path that points nowhere is an error: no amount of finishing setup fixes a
# wrong path, and the fix is in a different place (the config file or the flag)
# than every other finding here. The two unfinished-setup states stay warnings.
check_hook() {
  vault_state "${VAULT}" "${VAULT_ORIGIN}" || true
  case "${VS_STATE}" in
    missing)       err "${VS_MESSAGE}"; return ;;
    not-a-repo)    warn "${VS_MESSAGE}"; return ;;
    no-vault-json) warn "${VS_MESSAGE}"; return ;;
  esac

  local hook="${VAULT}/.git/hooks/pre-commit"
  if [ ! -e "${hook}" ]; then
    # The vault's own id, not the literal "VAULT_ID" this used to print: a
    # placeholder in a copy-paste remediation is a command that fails when
    # pasted — and since init-vault.sh started refusing unedited placeholders,
    # it fails by design. VS_STATE is `ready` here, so vault.json exists and
    # the id is readable through the shared check.
    local suggest_id="VAULT_ID"
    vault_identity_check "${VAULT}" "" || true
    [ -z "${VI_ID}" ] || suggest_id="${VI_ID}"
    warn "no pre-commit hook in ${VAULT} — run: ./scripts/init-vault.sh --path ${VAULT} --id ${suggest_id} --adopt"
    return
  fi
  if grep -qF "${HOOK_MARKER}" "${hook}" 2>/dev/null; then
    ok "commit guard installed as a pre-commit hook in ${VAULT}"
  else
    warn "${VAULT}/.git/hooks/pre-commit exists but is not ours — the guard runs only via update-second-brain here, not on every commit"
  fi
}

# A vault created before the author check existed has no identity block, so the
# check silently doesn't apply — on the machine where a personal address reached
# an employer repo, that is still true of the vault it happened in. Nothing else
# tells you: `--adopt` fills scaffold *files* and never edits vault.json, so
# there is no automatic upgrade. Hence naming the exact line to add rather than
# reporting a bare "optional". Severity stays `ok`: the check genuinely is
# opt-in, and doctor cannot know whether a given vault ought to pin one.
# printf, not echo: the pattern example contains a backslash, and echo's
# handling of those is not portable.
#
# Which of the two it is matters to the reader: "you never added the block" and
# "your block is there and pins nothing" have the same consequence but not the
# same fix, and telling someone staring at an identity block that they haven't
# got one is how a real report gets dismissed as wrong.
no_identity() {
  local why="${1:-absent}"
  ok "vault.json pins no commit author — the check is opt-in, so it is not running here"
  if [ "${why}" = "empty" ]; then
    printf '%s\n' '        the identity block is present but declares nothing, so it pins nothing;'
    printf '%s\n' '        give it a key to enable the check:'
  else
    printf '%s\n' '        a vault created before this feature has no identity block; add one to enable it:'
  fi
  printf '%s\n' '          "identity": { "email": "you@example.com" }'
  printf '%s\n' '          or, for addresses that vary: { "email_pattern": ".*@example\\.com$" }'
  printf '%s\n' '        see docs/GUARD.md#upgrading-an-existing-vault'
}

# The point of reporting it here is timing: the guard catches an author
# mismatch at the first commit, which on the machine this came from was already
# one commit too late. An error rather than a warning — a git identity that
# resolves to the wrong address is a setting that is wrong, not a step that
# hasn't been taken yet, and finishing setup won't change it.
check_author() {
  # `return 0`, not a bare `return`: a bare one propagates the failed test's
  # status, and under `set -e` that aborts the whole run — silently dropping
  # the remaining checks and the summary for any vault without a vault.json.
  [ -f "${VAULT}/vault.json" ] || return 0
  local ident="" email="" name="" rc=0
  ident="$(git -C "${VAULT}" var GIT_AUTHOR_IDENT 2>/dev/null || true)"
  if [ -n "${ident}" ]; then
    name="${ident%% <*}"
    email="${ident#*<}"
    email="${email%%>*}"
  fi

  author_identity_check "${VAULT}" "${email}" "${name}" || rc=$?
  case "${rc}" in
    0)
      if [ -n "${AI_EXPECT}" ]; then
        ok "commits here would be authored as ${email}, which is what vault.json declares"
      else
        no_identity empty
      fi
      ;;
    2) no_identity absent ;;
    *) err "${AI_ERROR}" ;;
  esac
}

# Not vault-specific — SKILLS_DIRS is a machine-wide setting, so this runs
# regardless of --vault. Detection only: a real directory or a symlink to
# another tool's install (e.g. Railway's use-railway, which its own
# installer writes into ~/.claude/skills only) can silently exist in one
# configured dir and not another, and nothing notices until someone reaches
# for it from the missing side. One of ours (a symlink into this repo) gets
# a simpler fix — re-run sync-skills.sh — since that command alone would
# already propagate it everywhere; anything else gets the exact `ln -s`.
check_skills() {
  local dir name entry names missing_dirs first_dir target clean=1
  local -a dirs

  IFS=':' read -r -a dirs <<< "${SKILLS_DIRS}"
  if [ "${#dirs[@]}" -lt 2 ]; then
    ok "only one skills directory configured — nothing to compare across"
    return
  fi

  names=""
  for dir in "${dirs[@]}"; do
    [ -d "${dir}" ] || continue
    for entry in "${dir}"/*; do
      [ -e "${entry}" ] || continue
      names="${names}$(basename "${entry}")
"
    done
  done
  names="$(printf '%s' "${names}" | sort -u)"
  [ -n "${names}" ] || { ok "no skills installed anywhere yet"; return; }

  while IFS= read -r name; do
    [ -n "${name}" ] || continue
    missing_dirs=""
    first_dir=""
    for dir in "${dirs[@]}"; do
      if [ -e "${dir}/${name}" ]; then
        [ -n "${first_dir}" ] || first_dir="${dir}"
      else
        missing_dirs="${missing_dirs}${dir}
"
      fi
    done
    [ -n "${missing_dirs}" ] || continue

    clean=0
    target=""
    [ -L "${first_dir}/${name}" ] && target="$(readlink "${first_dir}/${name}")"

    case "${target}" in
      "${STANDARDS_DIR}"/*)
        warn "${name}: not installed in every configured skills dir — run $(say_remediation 'make sync-skills' './scripts/sync-skills.sh')"
        ;;
      *)
        while IFS= read -r dir; do
          [ -n "${dir}" ] || continue
          warn "${name}: in ${first_dir} but not ${dir} — fix: ln -s ${first_dir}/${name} ${dir}/${name}"
        done <<< "${missing_dirs}"
        ;;
    esac
  done <<< "${names}"

  [ "${clean}" -eq 1 ] && ok "every installed skill is present in all configured skills directories"
  # `return 0`, for the same reason check_author has one: the test above is this
  # function's last command, so with a finding to report it returned 1 — and
  # under `set -e` that aborted the whole run, silently dropping every later
  # check and the summary line. A skill missing from one directory is a warning;
  # it is not a reason to stop looking at the machine.
  return 0
}

# Our links in a directory SKILLS_DIRS no longer names. Separate from the
# parity check above on purpose: parity asks whether the *configured* set
# agrees with itself, and folding an unconfigured directory into that
# comparison would report every skill in it as a gap to fill — the opposite of
# the advice wanted, which is to clean it up.
#
# How it happens is ordinary. sync-skills.sh runs during the Quickstart before
# a machine config exists, so it installs into the built-in default, meaning
# both directories; the config written afterwards narrows SKILLS_DIRS to one.
# From then on the wider install is invisible to every tool that reads the
# config — including `make uninstall`, which is the documented way out of the
# dangling-link state a deleted checkout leaves. A warning, not an error:
# nothing is broken, but nothing else will ever mention it.
check_orphaned_skills() {
  local dir n clean=1
  while IFS= read -r dir; do
    [ -n "${dir}" ] || continue
    n="$(skill_links_ours_in "${dir}" "${STANDARDS_DIR}")"
    [ "${n}" -gt 0 ] || continue
    clean=0
    warn "${n} of our skill link(s) in ${dir}, which is not in SKILLS_DIRS
        installed before the config narrowed it, and invisible to everything
        that reads the config. Remove them with $(say_remediation 'make uninstall' './scripts/uninstall.sh') (it
        looks here too, and shows them before it acts), or widen SKILLS_DIRS
        in $(ds_config_path) to include it."
  done <<EOF
${SKILLS_DIRS_UNCONFIGURED}
EOF
  [ "${clean}" -eq 1 ] && ok "no skills of ours are installed outside SKILLS_DIRS"
  return 0
}

# Not vault-specific — vendor/obsidian-skills is pinned in this engine
# checkout, not the vault. `git submodule status` prefixes each line with
# ' ' (in sync), '+' (checked out commit doesn't match what the superproject
# pins — the "switched tags/branches and forgot to update" state that
# checking out a tag alone can't fix on its own) or '-' (never initialized).
# Nothing else surfaces this: a stale submodule renders/links fine, it's
# just silently not the commit the current tag actually pins.
check_submodules() {
  if [ ! -d "${STANDARDS_DIR}/.git" ]; then
    ok "engine checkout is not a git repo — nothing to check for submodule drift"
    return
  fi
  local status
  status="$(git -C "${STANDARDS_DIR}" submodule status 2>/dev/null)"
  if [ -z "${status}" ]; then
    ok "no submodules configured"
    return
  fi
  local clean=1 line
  while IFS= read -r line; do
    [ -n "${line}" ] || continue
    case "${line}" in
      "+"*)
        clean=0
        warn "submodule out of sync with the pinned commit (${line#?}) — run: git submodule update --init --recursive"
        ;;
      "-"*)
        clean=0
        warn "submodule not initialized (${line#?}) — run: git submodule update --init --recursive"
        ;;
    esac
  done <<< "${status}"
  [ "${clean}" -eq 1 ] && ok "vendored submodule(s) match the commit this checkout pins"
  # Same as check_skills: without this, a drifted submodule made the function
  # return 1 and `set -e` exited before the summary — and before the exit-code
  # split between warnings (1) and misconfiguration (2) could be applied, so an
  # ERROR earlier in the run was reported as a warning.
  return 0
}

# Which repos on this machine are onboarded, from two sources rather than one.
#
# The registry alone could not answer it. It knows only what a render told it, so
# one render on a machine with twelve pre-registry repos gave one entry, present
# and rendered, and nothing to report — coverage going from unknown to asserted
# complete on the strength of a single line. sbw_scan_rendered_repos is the
# second source, and comparing the two makes the direction that matters
# reportable: a repo carrying rendered output that the registry does not name.
#
# Neither direction is ever repaired here. A registered repo that has gone
# missing stays in the file (an unmounted volume is not a deleted repo) and a
# found repo is not registered for you (it may be abandoned, or rendered by an
# engine old enough that re-rendering is a decision).
check_registry() {
  local file entries scan repo registered=0 stale=0 unregistered=0 line

  file="$(sbw_registry_path)"
  entries="$(sbw_registry_read)"
  # Roots validated in this shell, then the walk captured. The order matters:
  # sbw_scan_rendered_repos runs inside a command substitution, and the subshell
  # would take SBW_SCAN_SKIPPED and SBW_SCAN_USABLE with it when it exited.
  sbw_scan_prepare_roots
  scan="$(sbw_scan_rendered_repos)"

  # A root that could not be walked is named, never dropped: this is the one
  # place coverage silently shrinks, and a scope line that shrank with it would
  # present unmeasured ground as measured.
  while IFS= read -r line; do
    [ -n "${line}" ] || continue
    warn "scan root skipped: ${line}"
  done <<EOF
${SBW_SCAN_SKIPPED}
EOF

  # No usable root means no second source, so there is nothing to compare the
  # registry against. This is the only state still called undetermined, and it is
  # narrower than the one v0.9.1 used the word for: an empty registry is now
  # answerable, an unrunnable scan is not.
  if [ "${SBW_SCAN_USABLE}" -eq 0 ]; then
    warn "onboarded repo set is undetermined — no scan root could be read
        ${file} is not a second opinion: it holds what renders recorded, so with
        nothing to compare it against, any count from it would be a guess.
        Point SBW_SCAN_ROOTS at a directory that exists — in $(ds_config_path),
        or in the environment for one run."
    sbw_scan_say_scope
    return 0
  fi

  # Direction one: registered, and no longer what it was.
  while IFS= read -r repo; do
    [ -n "${repo}" ] || continue
    if [ ! -d "${repo}" ]; then
      stale=$((stale + 1))
      warn "registered repo is not there: ${repo}
        left in ${file} on purpose — an unmounted volume is not a deleted repo.
        Delete the line yourself once you know it is gone."
    elif ! sbw_registry_marker_present "${repo}"; then
      stale=$((stale + 1))
      warn "registered repo carries no rendered output any more: ${repo}
        re-render it, or delete its line from ${file}."
    else
      registered=$((registered + 1))
    fi
  done <<EOF
${entries}
EOF

  # Direction two: rendered, and the registry has never heard of it. The one the
  # registry cannot see on its own, and the one that was silently true on any
  # machine that onboarded repos before the registry existed.
  while IFS= read -r repo; do
    [ -n "${repo}" ] || continue
    # Newline on both ends of the subject, not just the front: `entries` comes
    # from a command substitution, which strips the trailing one, so a pattern
    # needing "\n<path>\n" would never match the *last* registered repo — and
    # that repo would then be reported as unregistered while sitting in the file.
    case "
${entries}
" in
      *"
${repo}
"*) continue ;;
    esac
    unregistered=$((unregistered + 1))
    warn "rendered but not registered: ${repo}
        register it by rendering again: ./scripts/render.py ${repo}
        or leave it, if that repo is abandoned — nothing here prunes or adopts."
  done <<EOF
${scan}
EOF

  if [ "${stale}" -eq 0 ] && [ "${unregistered}" -eq 0 ]; then
    if [ "${registered}" -eq 0 ]; then
      # Determined, not unknown. The scan ran, found nothing, and states the
      # boundary it ran inside — which is a measurement. What v0.9.1 refused to
      # print was a count with no boundary at all, and that is still refused
      # above whenever the scan cannot run.
      ok "no repos carry rendered output here, and the registry names none"
    else
      ok "${registered} onboarded repo(s) registered, all still rendered, and none unregistered"
    fi
  fi
  sbw_scan_say_scope
  return 0
}

echo "second-brain-workflow doctor — vault: ${VAULT}"
check_hook
check_author
check_skills
check_orphaned_skills
check_submodules
check_registry

echo
if [ "${problems}" -eq 0 ]; then
  echo "All checks passed."
  exit 0
fi
if [ "${errors}" -gt 0 ]; then
  echo "${problems} thing(s) worth a look, ${errors} of them misconfiguration."
  exit 2
fi
echo "${problems} thing(s) worth a look — setup unfinished, nothing misconfigured."
exit 1
