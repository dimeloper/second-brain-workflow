#!/usr/bin/env bash
# Which onboarded repos are behind the rules as they stand right now.
#
#   ./scripts/repos-check.sh              # registry ∪ machine scan (the honest set)
#   ./scripts/repos-check.sh --registry-only   # registered repos only, said so
#
# Reports; never renders. Same contract as `upgrade.sh` step 7, which asks the
# same question at a different moment: upgrade asks it about a version switch
# you are about to make, this asks it about a rule you just changed. Both read
# the repo set through lib/registry.sh, so what counts as an onboarded repo is
# defined once; only the framing differs.
#
# Why it exists separately from upgrade: a rule edit invalidates every rendered
# copy on the machine, and nothing fired at the moment of the edit. The answer
# was reachable only by remembering to run `make upgrade` — and the failure this
# closes (a rule everyone believes is live, rendered nowhere) is invisible
# precisely because nobody thinks to look.
#
# Exit codes match the family: 0 clean, 1 repos need re-rendering *or* carry
# rule files that resolve to nothing, 3 the set is undetermined. 3 is not 1 on
# purpose — "nothing to do" and "cannot tell you" are different answers and a
# caller must be able to distinguish them.
#
# Each verdict carries the repo's render mode. `render.py <repo>` re-renders in
# the mode the registry records, so the printed `fix:` preserves --local by
# itself — but a reader handed a command still has to be able to see that it
# does, and for three releases the mode was visible nowhere outside one clone's
# .git/info/exclude.
#
# The broken case is reported under --scan only, and is not drift: it is a repo
# whose rendered output stopped being readable, which both the registry and the
# scan read as "not onboarded" and drop from every count. That is how five repos
# here spent two weeks loading nothing while this script printed all clear.
set -euo pipefail

STANDARDS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/config.sh
. "${STANDARDS_DIR}/scripts/lib/config.sh"
# shellcheck source=scripts/lib/registry.sh
. "${STANDARDS_DIR}/scripts/lib/registry.sh"
ds_config_load

SCAN=1
for arg in "$@"; do
  case "${arg}" in
    --registry-only) SCAN=0 ;;
    -h|--help) sed -n '2,8p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: ${arg}" >&2; exit 2 ;;
  esac
done

entries="$(sbw_registry_read)"
scan=""

if [ "${SCAN}" -eq 1 ]; then
  # Roots validated before the command substitution: that runs in a subshell and
  # would take the skipped-root record away with it.
  sbw_scan_prepare_roots
  scan="$(sbw_scan_rendered_repos)"
  while IFS= read -r line; do
    [ -n "${line}" ] || continue
    echo "  warn  scan root skipped: ${line}"
  done <<EOF
${SBW_SCAN_SKIPPED}
EOF
  if [ "${SBW_SCAN_USABLE}" -eq 0 ]; then
    # The registry alone cannot be compared against anything, and a count drawn
    # from it would be the guess this check exists to refuse.
    echo "  ERROR the onboarded repo set is undetermined — no scan root could be read"
    echo "        Point SBW_SCAN_ROOTS at a directory that exists, or pass"
    echo "        --registry-only to accept an answer about registered repos alone."
    exit 3
  fi
fi

# `|| true`: with an empty registry and no scan hits, `grep -v` matches nothing
# and exits 1, which under pipefail would abort the run on exactly the machine
# that has nothing to check.
targets="$(printf '%s\n%s\n' "${entries}" "${scan}" \
  | grep -v '^[[:space:]]*$' | LC_ALL=C sort -u || true)"

drift=0 live=0 stale=0 unreg=0 rmode='' mode_hint=''
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

  if [ ! -d "${repo}" ]; then
    stale=$((stale + 1))
    echo "  warn  registered, but not there: ${repo} — cannot be checked"
    continue
  fi
  if ! sbw_registry_marker_present "${repo}"; then
    stale=$((stale + 1))
    echo "  warn  registered, but carries no rendered output: ${repo} — cannot be checked"
    continue
  fi

  # The mode travels with the verdict. Without it the `fix:` line below was a
  # command whose effect on a --local repo the reader could not see: it re-renders
  # in the recorded mode now, and saying which mode that is, is what makes the
  # command legible rather than merely safe. `unknown` is a repo the registry has
  # no mode for and that carries no exclusion block — the first render records it.
  rmode="$(sbw_registry_mode_effective "${repo}")"
  case "${rmode}" in
    local)   mode_hint=" — stays local, so this repo's remote still never sees them" ;;
    unknown) mode_hint=" — no mode recorded yet; this render records one" ;;
    *)       mode_hint="" ;;
  esac
  live=$((live + 1))
  if "${STANDARDS_DIR}/scripts/render.py" "${repo}" --check >/dev/null 2>&1; then
    echo "  ok    up to date: ${repo}${label}  [${rmode}]"
  else
    drift=$((drift + 1))
    echo "  DRIFT ${repo}${label}  [${rmode}]"
    echo "        fix: ${STANDARDS_DIR}/scripts/render.py ${repo}${mode_hint}"
  fi
done <<EOF
${targets}
EOF

# A repo whose rule files resolve to nothing never reaches the loop above: it
# carries no marker, so neither the registry nor the scan puts it in `targets`,
# and it is absent from every count this script prints. Reported separately
# because it is a separate answer — not "behind", which re-rendering fixes, but
# "loading nothing", where re-onboarding and deleting the links are both valid
# and the script must not assume which you meant. Only reported under --scan:
# --registry-only promises an answer about registered repos alone, and these are
# by definition not registered.
broken_repos=0
if [ "${SCAN}" -eq 1 ]; then
  broken_repo=""
  while IFS="$(printf '\t')" read -r repo dangler; do
    [ -n "${repo}" ] || continue
    if [ "${repo}" != "${broken_repo}" ]; then
      broken_repo="${repo}"
      broken_repos=$((broken_repos + 1))
      echo "  BROKEN rule files resolve to nothing: ${repo}"
      echo "        re-onboard: ${STANDARDS_DIR}/scripts/render.py ${repo}"
      echo "        or delete the dangling links, if that repo is abandoned."
    fi
    echo "          ${dangler} -> $(readlink "${dangler}" 2>/dev/null || echo '?')"
  done <<EOF
$(sbw_scan_broken_rules)
EOF
fi

echo
if [ "${drift}" -gt 0 ]; then
  echo "  ${drift} of ${live} checkable repo(s) need re-rendering, with the commands above."
  echo "  This script does not render: --check reports, you decide."
elif [ "${live}" -eq 0 ]; then
  if [ -n "${entries}" ]; then
    echo "  Nothing could be checked: all ${stale} registered path(s) are missing or no"
    echo "  longer carry rendered output."
  else
    echo "  ok    no repos carry rendered output here, and the registry names none"
  fi
else
  # Scoped to what was actually checked. "all N are up to date" alone was true
  # and still misread as a clean machine, because the repos it silently excluded
  # are exactly the ones a reader most needs told about.
  echo "  ok    all ${live} checkable repo(s) are up to date"
fi

if [ "${broken_repos}" -gt 0 ]; then
  echo "  ${broken_repos} further repo(s) carry rule files that resolve to nothing, above."
  echo "  They are in no count on this line: carrying no readable rendered output,"
  echo "  they are invisible to both the registry and the scan."
fi

if [ "${unreg}" -gt 0 ]; then
  echo "  ${unreg} of those carr(ies) rendered output the registry does not name."
  echo "  Rendering each registers it; leave the ones you have abandoned."
fi

# The boundary travels with the answer. Without a scan there is no boundary to
# state and no claim about unregistered repos to qualify — so say which question
# was answered instead of implying the wider one was.
if [ "${SCAN}" -eq 1 ]; then
  sbw_scan_say_scope
else
  echo "        registered repos only (--registry-only): a repo rendered here but"
  echo "        never registered was not looked for."
fi

# Exit 1 covers both findings: each one means a repo on this machine is not
# loading the rules you believe it is, which is the question the caller asked.
# They stay distinguishable in the report rather than in the code.
if [ "${drift}" -ne 0 ] || [ "${broken_repos}" -ne 0 ]; then
  exit 1
fi
exit 0
