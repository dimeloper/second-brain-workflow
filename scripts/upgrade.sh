#!/usr/bin/env bash
# Move this engine checkout to a release, and report what the machine needs
# afterwards. Preview by default.
#
# Usage:
#   ./upgrade.sh                 # preview: print what would happen, change nothing
#   ./upgrade.sh --dry-run       # the same, said explicitly
#   ./upgrade.sh --yes           # switch the checkout, then report
#   ./upgrade.sh --ref v0.9.1    # target this tag instead of the newest one
#   ./upgrade.sh --no-fetch      # do not contact the remote for tags
#   ./upgrade.sh --vault PATH    # vault to check, overriding the config
#
# Exit codes:
#   0  nothing to act on
#   1  findings: render drift, doctor warnings, or a vault ENGINE_REF behind
#   2  refused before acting (dirty checkout, local commits, bad arguments), or
#      doctor reporting a misconfiguration
#   3  the onboarded repo set is undetermined — see below
#
# Upgrading a set-up machine was seven sequenced commands, and the one that
# could not be done at all was "re-render every onboarded repo": the engine
# recorded nothing about where it had rendered. That is now the repo registry
# (scripts/lib/registry.sh), and this script is the sequence.
#
# Why 3 is its own code, and why it is non-zero: the onboarded repos come from
# the registry, so a missing, empty or wholly stale registry makes the answer
# unknown. The plausible-looking wrong answer — "0 repos need re-rendering" —
# reads as success and leaves every repo on the machine at a stale render
# indefinitely. CHANGELOG.md records that same shape at v0.6.0, v0.8.0 and
# v0.9.0: a check that cannot determine something must not degrade to a
# confident number.
#
# What it never does: render, commit, push, edit a vault, edit a template, or
# touch a file in an onboarded repo. Step 7 is `render.py --check` and prints
# the per-repo command; the human decides what to re-render. Step 8 reports a
# stale ENGINE_REF and does not write the workflow file — a vault is its own
# repo with its own history.
set -euo pipefail

STANDARDS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/config.sh
. "${STANDARDS_DIR}/scripts/lib/config.sh"
# shellcheck source=scripts/lib/invocation.sh
. "${STANDARDS_DIR}/scripts/lib/invocation.sh"
# shellcheck source=scripts/lib/registry.sh
. "${STANDARDS_DIR}/scripts/lib/registry.sh"
ds_config_load

# One awk program for everything version-shaped: the changelog range below and
# the ENGINE_REF comparison in step 8 must agree about what "greater than"
# means for a release, and two implementations of that would be one too many.
# Single-quoted, so it contains no apostrophes.
# shellcheck disable=SC2016  # an awk program, not a shell string: $0 and the
# rest must reach awk unexpanded.
VERSION_AWK='
function vnum(v,   p, i) {
  split(v, p, ".")
  for (i = 1; i <= 3; i++) {
    sub(/[^0-9].*$/, "", p[i])
    if (p[i] == "") p[i] = 0
  }
  return (p[1] * 1000000) + (p[2] * 1000) + p[3]
}
BEGIN {
  if (mode == "cmp") {
    d = vnum(a) - vnum(b)
    print (d < 0) ? "lt" : ((d == 0) ? "eq" : "gt")
    exit
  }
  lo = vnum(cur)
  hi = vnum(tgt)
}
# A version heading opens a range decision; [Unreleased] carries no version and
# is therefore never in range.
/^## / {
  inrange = 0
  insec = ""
  if (match($0, /\[[0-9]+\.[0-9]+\.[0-9]+\]/)) {
    ver = substr($0, RSTART + 1, RLENGTH - 2)
    inrange = (vnum(ver) > lo && vnum(ver) <= hi)
  }
  next
}
/^### / {
  if (!inrange) { insec = ""; next }
  if ($0 ~ /^### Major([[:space:]]|$)/) {
    insec = "major"
    majors++
    if (mode == "print") printf "\n  ---- v%s, verbatim from CHANGELOG.md ----\n", ver
  } else {
    insec = ""
    skipped++
  }
  next
}
# The link definitions at the bottom of the file are not part of any section.
/^\[[^]]*\]: / { insec = ""; next }
mode == "print" && insec == "major" { print }
END {
  if (mode == "count") printf "%d %d\n", majors + 0, skipped + 0
}
'

# lt / eq / gt, on version strings with or without a leading v.
ver_cmp() {
  awk -v mode=cmp -v a="${1#v}" -v b="${2#v}" "${VERSION_AWK}" </dev/null
}

APPLY=0
FETCH=1
REF=""
VAULT="${SBW_VAULT}"
VAULT_ORIGIN="$(ds_origin_describe SBW_VAULT)"

# Findings are accumulated rather than exited on, so one run reports the whole
# picture instead of stopping at the first thing wrong. The exception is a
# refusal, which is a decision not to proceed and therefore ends the run.
findings=0
undetermined=0
doctor_rc=0

while [ $# -gt 0 ]; do
  case "$1" in
    --yes) APPLY=1; shift ;;
    --dry-run) APPLY=0; shift ;;
    --ref) REF="${2:?--ref needs a value}"; shift 2 ;;
    --no-fetch) FETCH=0; shift ;;
    --vault)
      VAULT="${2:?--vault needs a value}"
      VAULT_ORIGIN="the --vault flag"
      shift 2
      ;;
    -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

heading() { printf '\n%s\n' "$1"; }
ok()   { echo "  ok    $1"; }
warn() { echo "  warn  $1"; findings=$((findings + 1)); }
note() { echo "        $1"; }

# `git checkout` rewrites files under this checkout, and one of them is this
# script. Bash reads a script incrementally, so a switch performed halfway
# through executing it can resume at a byte offset that means something else in
# the new file. Everything therefore lives in functions that are fully parsed
# before main runs, and `main` is the last line of the file.

resolve_target() {
  local newest
  if [ "${FETCH}" -eq 1 ]; then
    if ! git -C "${STANDARDS_DIR}" fetch --tags --quiet 2>/dev/null; then
      warn "could not fetch tags — working from the tags already in this checkout"
      note "pass --no-fetch to skip the attempt entirely"
    fi
  fi
  if [ -n "${REF}" ]; then
    TARGET_REF="${REF}"
    return 0
  fi
  newest="$(git -C "${STANDARDS_DIR}" tag --list 'v[0-9]*' --sort=-v:refname | head -n 1)"
  if [ -z "${newest}" ]; then
    echo "  ERROR no release tags in ${STANDARDS_DIR} — nothing to resolve a target from." >&2
    note "name one with --ref, or fetch tags first."
    exit 2
  fi
  TARGET_REF="${newest}"
  TARGET_FROM=" (newest tag in this checkout)"
}

# Step 1 and 2: where we are, where we would end up.
report_version() {
  CURRENT="0.0.0-unversioned"
  [ ! -f "${STANDARDS_DIR}/VERSION" ] || CURRENT="$(tr -d '[:space:]' < "${STANDARDS_DIR}/VERSION")"
  TARGET_FROM=""
  resolve_target

  TARGET_VERSION="${TARGET_REF#v}"
  # A ref with no version in it cannot be compared with anything. Refused rather
  # than tolerated: vnum() would read "main" as 0.0.0, making the Major range
  # empty and every vault ENGINE_REF look ahead of the target — two confident
  # answers, both wrong, in the one place this script exists to get right.
  #
  # Ahead of the existence check below on purpose. "main is not a release tag" is
  # true whether or not a branch by that name exists here, and it is the more
  # useful of the two answers — "no such ref" would send the reader looking for a
  # fetch problem they do not have.
  case "${TARGET_VERSION}" in
    [0-9]*.[0-9]*.[0-9]*) ;;
    *)
      echo "  ERROR --ref must name a release tag like v0.9.0 (got ${TARGET_REF})." >&2
      note "the changelog range and the vault ENGINE_REF comparison are both"
      note "computed from the version, and a branch name carries none."
      exit 2
      ;;
  esac

  if ! git -C "${STANDARDS_DIR}" rev-parse -q --verify "${TARGET_REF}^{commit}" >/dev/null; then
    echo "  ERROR no such ref in this checkout: ${TARGET_REF}" >&2
    if [ "${FETCH}" -eq 0 ]; then
      note "--no-fetch was given, so nothing new was fetched."
    fi
    exit 2
  fi

  heading "Version"
  echo "  current ${CURRENT} → target ${TARGET_REF}${TARGET_FROM}"
  case "$(ver_cmp "${CURRENT}" "${TARGET_VERSION}")" in
    eq) echo "        already at the target — nothing to switch, everything below still checked" ;;
    gt) echo "        the target is older than this checkout: this is a rollback, and the"
        echo "        required actions for it are the ones between the two releases, read in"
        echo "        reverse. See docs/REFERENCE.md, Versioning." ;;
  esac
}

# Step 3: the required-action entries, before anything is proposed. Read from
# the target ref rather than the working tree — the checkout at the current
# version does not contain the target release's notes, which is exactly the
# step that gets skipped and the one carrying required action. Still local: git
# reads its own objects, no network.
report_major() {
  local changelog counts majors skipped
  changelog="$(git -C "${STANDARDS_DIR}" show "${TARGET_REF}:CHANGELOG.md" 2>/dev/null || true)"
  heading "Required action in this range"
  if [ -z "${changelog}" ]; then
    warn "no CHANGELOG.md at ${TARGET_REF} — cannot tell you what this upgrade requires"
    note "read the release notes by hand before continuing"
    return 0
  fi

  counts="$(printf '%s\n' "${changelog}" \
    | awk -v mode=count -v cur="${CURRENT}" -v tgt="${TARGET_VERSION}" "${VERSION_AWK}")"
  majors="${counts%% *}"
  skipped="${counts##* }"

  if [ "${majors}" -eq 0 ]; then
    echo "  No Major entry between ${CURRENT} and ${TARGET_VERSION} — nothing in this range"
    echo "  requires action in an already-onboarded repo."
  else
    printf '%s\n' "${changelog}" \
      | awk -v mode=print -v cur="${CURRENT}" -v tgt="${TARGET_VERSION}" "${VERSION_AWK}"
    echo
    echo "  ${majors} Major section(s) above. Each names the action required to keep an"
    echo "  already-onboarded repo working."
  fi
  # Only when there are some: "0 non-Major section(s) not shown" is a line about
  # nothing, and the reader has to parse it to find that out.
  [ "${skipped}" -eq 0 ] ||
    echo "  ${skipped} non-Major section(s) in this range not shown — read CHANGELOG.md for those."
}

# Step 4: refuse on anything a checkout switch would silently take with it.
check_clean() {
  local dirty ahead
  heading "Checkout state"
  dirty="$(git -C "${STANDARDS_DIR}" status --porcelain)"
  if [ -n "${dirty}" ]; then
    echo "  ERROR the checkout is not clean, so switching it could lose work:"
    printf '%s\n' "${dirty}" | sed 's/^/          /'
    note "commit, stash or discard the above, then run this again."
    exit 2
  fi
  ahead="$(git -C "${STANDARDS_DIR}" rev-list --count "${TARGET_REF}..HEAD" 2>/dev/null || echo 0)"
  if [ "${ahead}" -gt 0 ]; then
    echo "  ERROR ${ahead} local commit(s) here are not in ${TARGET_REF}:"
    git -C "${STANDARDS_DIR}" log --oneline "${TARGET_REF}..HEAD" | sed 's/^/          /'
    note "switching would leave them reachable only from this checkout."
    note "push or merge them first, or target a ref that contains them with --ref."
    exit 2
  fi
  ok "clean, and no local commits outside ${TARGET_REF}"
}

# Step 5: the switch itself. Three commands, always all three: a bare checkout
# leaves the vendored submodule at whatever commit it was on, and the installed
# skills are symlinks into it.
do_switch() {
  heading "Switching the checkout"
  if [ "${APPLY}" -eq 0 ]; then
    echo "  preview — would run, in this order:"
    echo "          git -C ${STANDARDS_DIR} checkout ${TARGET_REF}"
    echo "          git -C ${STANDARDS_DIR} submodule update --init --recursive"
    echo "          ${STANDARDS_DIR}/scripts/sync-skills.sh"
    return 0
  fi
  # Each step keeps its own status rather than being left to `set -e`. A failure
  # here must not end the run without a summary: doctor did exactly that for
  # three releases, and the checks it skipped were the ones that would have said
  # what state the machine had been left in.
  if ! git -C "${STANDARDS_DIR}" checkout --quiet "${TARGET_REF}"; then
    echo "  ERROR could not check out ${TARGET_REF} — the checkout is unchanged." >&2
    exit 2
  fi
  ok "checked out ${TARGET_REF}"

  local rc=0
  git -C "${STANDARDS_DIR}" submodule update --init --recursive || rc=$?
  if [ "${rc}" -eq 0 ]; then
    ok "submodules updated to the commits ${TARGET_REF} pins"
  else
    warn "git submodule update exited ${rc} — vendored skills may be at the wrong commit"
    note "doctor below reports which; re-run the command by hand once it can reach the remote."
  fi

  rc=0
  "${STANDARDS_DIR}/scripts/sync-skills.sh" 2>&1 | sed 's/^/        /' || rc=$?
  if [ "${rc}" -eq 0 ]; then
    ok "skills re-linked"
  else
    warn "sync-skills.sh exited ${rc} — the conflicts it printed above are unresolved"
  fi

  # This script just replaced itself on disk, and bash parsed every function in
  # it before main() ran — so everything below is still the *previous* version's
  # logic, reading a checkout that is now the new one. Usually that difference is
  # invisible. It is not invisible when the release being installed fixes one of
  # the checks below: v0.25.2 fixed `upgrade` aborting with no onboarded repos,
  # and upgrading *to* it still aborted, because the code doing the aborting was
  # the copy already in memory. Said out loud rather than left for the reader to
  # deduce from a report that contradicts the release they just installed.
  note "the checks below still run this script's previous version — it was"
  note "already in memory when the checkout switched. Re-run \`make upgrade\` to"
  note "see them as ${TARGET_REF} implements them."
}

# Step 6: doctor, inline. Its output is its own — summarising it here would put
# a second opinion in front of the reader, and its severities already say more
# than a count could.
run_doctor() {
  heading "Machine health (doctor, verbatim)"
  if [ "${APPLY}" -eq 0 ]; then
    echo "  (against the current checkout — the switch has not happened)"
  fi
  doctor_rc=0
  "${STANDARDS_DIR}/scripts/doctor.sh" --vault "${VAULT}" || doctor_rc=$?
  echo "  doctor exited ${doctor_rc}"
}

# Step 7: which onboarded repos are behind. Reports; never renders.
#
# Two sources, the same pair doctor compares: the registry, and a scan of this
# machine for repos carrying rendered output. Reading the registry alone told a
# machine with rendered-but-unregistered repos that "all 1 checkable repo(s) are
# up to date" immediately before a switch that would stale the rest.
#
# A repo the scan found and the registry does not name is drift-checked like any
# other, because it *is* an onboarded repo — the registry not naming it is a
# bookkeeping gap, not a reason to skip it. It is labelled in the same line,
# since `render.py <repo>` closes both at once.
report_repos() {
  local file entries scan targets repo drift=0 live=0 stale=0 unreg=0 label
  heading "Onboarded repos (render --check, nothing is rendered)"
  file="$(sbw_registry_path)"
  entries="$(sbw_registry_read)"
  # Roots validated here, walk captured after: the command substitution below is
  # a subshell and would take the skipped-root record with it when it exits.
  sbw_scan_prepare_roots
  scan="$(sbw_scan_rendered_repos)"

  if [ "${APPLY}" -eq 0 ]; then
    echo "  (drift is measured against the current checkout, not ${TARGET_REF})"
  fi

  while IFS= read -r repo; do
    [ -n "${repo}" ] || continue
    warn "scan root skipped: ${repo}"
  done <<EOF
${SBW_SCAN_SKIPPED}
EOF

  # The one state still genuinely undetermined: no second source ran, so the
  # registry cannot be compared against anything and a count from it alone would
  # be the guess this whole check exists to refuse.
  if [ "${SBW_SCAN_USABLE}" -eq 0 ]; then
    report_undetermined "no scan root could be read"
    sbw_scan_say_scope
    return 0
  fi

  # Registry ∪ scan. A path in both is one path; sort -u decides that, not the
  # order they arrive in.
  # `|| true`: with no registry entries and no scan hits, `grep -v` matches
  # nothing and exits 1, and under `set -o pipefail` that fails the whole
  # substitution — aborting the run under `set -e` after the heading had already
  # printed. A machine with no onboarded repos is the state every fresh install
  # is in, so `make upgrade` died on exactly the machines most likely to run it.
  targets="$(printf '%s\n%s\n' "${entries}" "${scan}" \
    | grep -v '^[[:space:]]*$' | LC_ALL=C sort -u || true)"

  while IFS= read -r repo; do
    [ -n "${repo}" ] || continue
    label=""
    case "
${entries}
" in
      *"
${repo}
"*) ;;
      *) label=" (not in the registry)"; unreg=$((unreg + 1)) ;;
    esac

    # Only a registry entry can be missing or unrendered — the scan found what it
    # found by looking at what is there.
    if [ ! -d "${repo}" ]; then
      stale=$((stale + 1))
      warn "registered, but not there: ${repo} — cannot be checked"
      continue
    fi
    if ! sbw_registry_marker_present "${repo}"; then
      stale=$((stale + 1))
      warn "registered, but carries no rendered output: ${repo} — cannot be checked"
      continue
    fi

    live=$((live + 1))
    if "${STANDARDS_DIR}/scripts/render.py" "${repo}" --check >/dev/null 2>&1; then
      ok "up to date: ${repo}${label}"
      [ -z "${label}" ] || echo "        register it: ./scripts/render.py ${repo}"
    else
      drift=$((drift + 1))
      echo "  DRIFT ${repo}${label}"
      if [ -z "${label}" ]; then
        echo "        fix: ./scripts/render.py ${repo}"
      else
        echo "        fix: ./scripts/render.py ${repo} — re-renders it and registers it"
      fi
    fi
  done <<EOF
${targets}
EOF

  if [ "${drift}" -gt 0 ]; then
    findings=$((findings + 1))
    echo
    if preview_of_another_version; then
      echo "  at least ${drift} of ${live} checkable repo(s) need re-rendering, with the"
      echo "  commands above — and expect all ${live} to, once the switch has happened."
    else
      echo "  ${drift} of ${live} checkable repo(s) need re-rendering, with the commands above."
    fi
    echo "  This script does not render: --check reports, you decide."
  elif [ "${live}" -eq 0 ]; then
    # Nothing was checkable, and the two ways that happens do not read alike.
    # Guarded on the registry being empty, the way check_registry guards its
    # equivalent: with stale entries present, "the registry names none" printed
    # as `ok` directly under the warnings naming them — and `ok` is the line a
    # reader takes as the verdict.
    if [ -n "${entries}" ]; then
      echo "  Nothing could be checked: all ${stale} registered path(s) are missing or no"
      echo "  longer carry rendered output, and the scan found no others."
    else
      # Determined, not unknown: the scan ran and found nothing, within a
      # boundary printed below. What is refused is a count with no boundary.
      ok "no repos carry rendered output here, and the registry names none"
    fi
  elif preview_of_another_version; then
    ok "all ${live} repo(s) match the current checkout — expect all ${live} to need"
    note "re-rendering after switching to ${TARGET_REF}"
  else
    ok "all ${live} checkable repo(s) are up to date"
  fi

  # An unregistered repo is a finding even when it is up to date: the next run of
  # anything that reads the registry alone will not know it exists.
  if [ "${unreg}" -gt 0 ]; then
    findings=$((findings + 1))
    echo "  ${unreg} of those carr(ies) rendered output the registry does not name."
    echo "  Rendering each registers it; leave the ones you have abandoned."
  fi

  sbw_scan_say_scope
}

# In preview, --check has run against the checkout as it stands, so a clean
# result is true when printed and false the moment --yes switches the ref. That
# is fine for the per-repo lines and not fine for the summary: "all N up to
# date" is the line a reader scans for permission to stop reading, and a caveat
# in a header several lines above it is not carried by the line that gets read.
# So the qualification goes in the wording itself.
#
# Keyed on the version rather than on whether the commit moves: the version is
# stamped into every rendered file's provenance header and into .sbw-version, so
# a target with a different version is what *guarantees* all of them drift.
# Same-version targets are the only case where the plain wording is true, and
# `--ref` already refuses anything that is not a release tag.
preview_of_another_version() {
  [ "${APPLY}" -eq 0 ] && [ "$(ver_cmp "${CURRENT}" "${TARGET_VERSION}")" != "eq" ]
}

# Never a count. "0 repos need re-rendering" is the answer that reads as success
# while leaving every repo on this machine at a stale render.
#
# What used to live here was a find command for the reader to run, carrying the
# second copy of a rule that had drifted from what counts as a rendered repo
# everywhere else — it matched AGENTS.md alone, so a repo with a hand-written or
# absent AGENTS.md was invisible to it. The scan does that job now, which leaves
# this function the one state that is genuinely unknown: the scan could not run.
report_undetermined() {
  undetermined=1
  echo "  ERROR the onboarded repo set is undetermined — $1"
  note "so this run cannot tell you which repos need re-rendering, and will not"
  note "report that none do: with no scan, the registry has nothing to be"
  note "compared against, and it only holds what renders recorded."
  note "Point SBW_SCAN_ROOTS at a directory that exists, then run this again."
}

# Step 8: the vault's CI pins. Reported only — the vault is its own repo, and
# nothing here writes to it.
report_vault_pins() {
  local wf file ref
  heading "Vault CI pins (reported only)"
  if [ ! -d "${VAULT}" ]; then
    echo "  none  no vault at ${VAULT} (from ${VAULT_ORIGIN}) — skipped"
    return 0
  fi
  local found=0
  for wf in guard audit; do
    file="${VAULT}/.github/workflows/${wf}.yml"
    [ -f "${file}" ] || continue
    found=1
    ref="$(sed -n 's/^[[:space:]]*ENGINE_REF:[[:space:]]*\([^[:space:]]*\).*/\1/p' "${file}" | head -1)"
    if [ -z "${ref}" ]; then
      warn "${wf}.yml pins no ENGINE_REF — its checks run against whatever main is"
      continue
    fi
    # A pin that is not a release tag is not "behind": it tracks a moving ref,
    # which is a different decision with a different consequence, and reading it
    # as 0.0.0 would report every such vault as several releases out of date.
    case "${ref#v}" in
      [0-9]*.[0-9]*.[0-9]*) ;;
      *)
        warn "${wf}.yml pins ${ref}, which is not a release tag — that workflow follows"
        note "a moving ref, so what it checks changes without the vault changing."
        continue
        ;;
    esac
    case "$(ver_cmp "${ref}" "${TARGET_VERSION}")" in
      eq) ok "${wf}.yml pins ${ref}, matching the target" ;;
      lt) warn "${wf}.yml pins ${ref}, behind the target ${TARGET_REF}"
          note "that workflow runs an older engine than this machine will."
          note "edit ENGINE_REF in ${file} yourself — this script never writes to a vault." ;;
      gt) warn "${wf}.yml pins ${ref}, ahead of the target ${TARGET_REF}"
          note "the workflow would run an engine this machine does not have." ;;
    esac
  done
  [ "${found}" -eq 1 ] || echo "  none  no guard.yml or audit.yml in ${VAULT}/.github/workflows — skipped"
  return 0
}

summarise() {
  heading "Summary"
  if [ "${APPLY}" -eq 0 ]; then
    echo "  Preview only — nothing was changed."
    echo "  Re-run with $(say_remediation 'YES=1 (make upgrade YES=1)' '--yes') to switch the checkout."
  fi
  if [ "${undetermined}" -eq 1 ]; then
    echo "  Exit 3: the onboarded repo set is undetermined (above)."
    exit 3
  fi
  if [ "${doctor_rc}" -ge 2 ]; then
    echo "  Exit 2: doctor reported a misconfiguration (above)."
    exit 2
  fi
  if [ "${findings}" -gt 0 ] || [ "${doctor_rc}" -ne 0 ]; then
    echo "  Exit 1: ${findings} finding(s) here, doctor exited ${doctor_rc}."
    exit 1
  fi
  echo "  Nothing to act on."
  exit 0
}

main() {
  echo "second-brain-workflow upgrade — checkout: ${STANDARDS_DIR}"
  [ "${APPLY}" -eq 1 ] || echo "(preview only — nothing will be changed)"

  report_version
  report_major
  check_clean
  do_switch
  run_doctor
  report_repos
  report_vault_pins
  summarise
}

main
