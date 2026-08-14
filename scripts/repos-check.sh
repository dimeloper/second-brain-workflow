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
# Exit codes match the family: 0 clean, 1 repos need re-rendering, 3 the set is
# undetermined. 3 is not 1 on purpose — "nothing to do" and "cannot tell you"
# are different answers and a caller must be able to distinguish them.
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

drift=0 live=0 stale=0 unreg=0
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

  live=$((live + 1))
  if "${STANDARDS_DIR}/scripts/render.py" "${repo}" --check >/dev/null 2>&1; then
    echo "  ok    up to date: ${repo}${label}"
  else
    drift=$((drift + 1))
    echo "  DRIFT ${repo}${label}"
    echo "        fix: ${STANDARDS_DIR}/scripts/render.py ${repo}"
  fi
done <<EOF
${targets}
EOF

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
  echo "  ok    all ${live} checkable repo(s) are up to date"
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

[ "${drift}" -eq 0 ] || exit 1
exit 0
