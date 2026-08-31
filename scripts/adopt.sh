#!/usr/bin/env bash
# Turn on this engine's opt-in features for a machine, and re-render safely.
#
#   ./adopt.sh                 # preview: print every change, write nothing
#   ./adopt.sh --yes           # act
#   ./adopt.sh --vault PATH    # vault to opt in, overriding the config
#
# Exit codes:
#   0  nothing left to do, or a clean preview
#   1  something needs a human — named in the report
#   2  refused before acting (no vault, no promotion map, bad arguments)
#
# What this is for. Two features ship off by default — the applications
# promotion bar and SBW_RENDER_SCOPE=relevant — because switching either one on
# changes a vault's audit or deletes rendered files from every onboarded repo,
# which an engine upgrade must not do on anyone's behalf. Turning them on by
# hand is four steps across three files, and one of them is pasting a Dataview
# query whose operator precedence is easy to get wrong: `A OR B AND C` binds as
# `A OR (B AND C)`, which matches every scoped note regardless of its repo count.
# That bug shipped into the author's own map and was caught on re-read.
#
# The re-render is the part that actually needs a program rather than a
# checklist. A repo onboarded with --local keeps its rendered files out of the
# remote via a marked block in .git/info/exclude, and re-rendering it *without*
# --local starts committing those files into a repo they were deliberately kept
# out of. This re-renders each repo in the mode it was onboarded with, read from
# the registry (falling back to that marker for a line written before the mode
# was recorded) — and render.py now preserves the mode by itself, so this is no
# longer the only command that gets it right.
#
# Deliberately NOT done here, in every case because the answer is a judgement:
#   - committing or pushing anything, in any repo
#   - pruning dead registry lines (doctor names them; an unmounted volume is not
#     a deleted repo)
#   - backfilling applications: onto notes (evidence, not bookkeeping)
#   - reviewing the deletions that `relevant` produces on its first run
set -uo pipefail

STANDARDS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/config.sh
. "${STANDARDS_DIR}/scripts/lib/config.sh"
# shellcheck source=scripts/lib/registry.sh
. "${STANDARDS_DIR}/scripts/lib/registry.sh"
ds_config_load

YES=0
VAULT="${SBW_VAULT}"
while [ $# -gt 0 ]; do
  case "$1" in
    --yes|-y)   YES=1; shift ;;
    --dry-run)  YES=0; shift ;;
    --vault)    VAULT="${2:?--vault needs a value}"; shift 2 ;;
    -h|--help)  sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done
VAULT="${VAULT/#\~/${HOME}}"

todo=0
act() { [ "${YES}" -eq 1 ]; }
step() { echo; echo "== $1"; }
would() { if act; then echo "  $1"; else echo "  would $1"; fi; }

# --- 1. the applications promotion bar --------------------------------------
# Written at the v0.37.0 shape, keyed on `domain` as well as `applies-to`. A
# machine adopting straight from an older release must not paste the earlier
# form, which read every unscoped note as a process rule.
MAP="${VAULT}/00-maps/promotion-candidates.md"
step "Applications promotion bar — ${MAP}"
if [ ! -f "${MAP}" ]; then
  echo "  REFUSED: no promotion map there."
  echo "  This never creates one: the map is where a vault states its own bars,"
  echo "  and a generated default would be this engine deciding them instead."
  exit 2
elif grep -q 'length(applications)' "${MAP}"; then
  echo "  ok    already declared — nothing to do"
else
  would "append the applications block, and scope the repo block to match"
  todo=$((todo + 1))
  if act; then
    python3 - "${MAP}" <<'PY'
import re, sys
path = sys.argv[1]
s = open(path).read()
# Parenthesised deliberately: `A OR B AND C` binds as `A OR (B AND C)`.
s = re.sub(r'^WHERE \(?maturity = "idea" AND length\(repos\)',
           'WHERE (applies-to != "" OR domain != "cross-cutting")\n  AND ((maturity = "idea" AND length(repos)',
           s, count=1, flags=re.M)
s = re.sub(r'^(\s*)OR \(?maturity = "trialing" AND length\(repos\) >= (\d+)\)?',
           r'\1  OR (maturity = "trialing" AND length(repos) >= \2))',
           s, count=1, flags=re.M)
s = s.rstrip() + '''

Process notes (`domain: cross-cutting` + `applies-to: ""`) — evidence = entries
in `applications:`. Same numbers, different denominator: an entry is
`"<repo> <YYYY-MM-DD>"`, and two re-applications in one session are one entry.
A process note with no `applications:` list is uncounted, not zero.

```dataview
TABLE maturity, length(applications) AS "applications", last-reviewed
FROM "practices"
WHERE applies-to = "" AND domain = "cross-cutting"
  AND ((maturity = "idea" AND length(applications) >= 2)
    OR (maturity = "trialing" AND length(applications) >= 3))
SORT length(applications) DESC
```
'''
open(path, 'w').write(s)
PY
    # Verify rather than ask. The repo block is rewritten by pattern, and a map
    # worded differently from the one this expects would leave it unscoped — so
    # both queries would then match the same notes, and the reader would be the
    # one who found out. "Review the parentheses before committing" put that
    # work on a person who has no reason to know what the right shape is.
    if grep -qF 'WHERE (applies-to != "" OR domain != "cross-cutting")' "${MAP}"; then
      echo "  wrote the applications block, and scoped the repo block to match"
    else
      echo "  WARN  wrote the applications block, but could not scope the repo block:"
      echo "        its WHERE clause is not in the shape this knows how to rewrite."
      echo "        Both queries now match the same notes. Add to the repo block:"
      echo "          WHERE (applies-to != \"\" OR domain != \"cross-cutting\")"
      echo "        as its first condition, with the existing maturity tests"
      echo "        parenthesised under an AND — see 00-maps/promotion-candidates.md"
      echo "        in the engine's own vault for the finished shape."
    fi
  fi
fi

# --- 2. selective rendering -------------------------------------------------
CFG="$(ds_config_path)"
step "Selective rendering — ${CFG}"
if [ "${SBW_RENDER_SCOPE:-all}" = "relevant" ]; then
  echo "  ok    already relevant — nothing to do"
else
  would "set SBW_RENDER_SCOPE=relevant"
  echo "        first render after this DELETES rules that cannot match; read the diff"
  todo=$((todo + 1))
  if act; then
    printf '\n# Render a rule only into repos where its globs match something.\nSBW_RENDER_SCOPE=relevant\n' >> "${CFG}"
    export SBW_RENDER_SCOPE=relevant
  fi
fi

# --- 3. the index, whose format moved in v0.36.0 ----------------------------
step "Practices index"
if "${STANDARDS_DIR}/scripts/build-vault-index.py" --vault "${VAULT}" --check >/dev/null 2>&1; then
  echo "  ok    current"
else
  would "regenerate practices/INDEX.md"
  todo=$((todo + 1))
  act && "${STANDARDS_DIR}/scripts/build-vault-index.py" --vault "${VAULT}" | tail -1
fi

# --- 4. re-render every registered repo, in the mode it was onboarded with ---
step "Re-render (--local preserved per repo)"
while IFS= read -r repo; do
  [ -n "${repo}" ] || continue
  name="$(basename "${repo}")"
  if [ ! -d "${repo}" ]; then
    echo "  skip  ${name}: not there — left in the registry on purpose"
    continue
  fi
  # Through the lib, not a private grep: the mode question had two answers on
  # this machine — this grep, and nothing at all everywhere else — and the whole
  # point of recording it in the registry is that there is now one. Still passed
  # explicitly rather than left to render.py's own preservation, because this
  # script prints the mode it used per repo and a flag it did not pass is a
  # column it cannot honestly fill.
  mode=()
  if [ "$(sbw_registry_mode_effective "${repo}")" = "local" ]; then
    mode=(--local)
  fi
  if act; then
    out="$("${STANDARDS_DIR}/scripts/render.py" "${repo}" "${mode[@]}" 2>&1)"
  else
    out="$("${STANDARDS_DIR}/scripts/render.py" "${repo}" "${mode[@]}" --dry-run 2>&1)"
  fi
  scope="$(printf '%s\n' "${out}" | grep '^Scope:' | sed 's/^Scope: *//')"
  # The version stamp is excluded: since v0.34.0 a lagging .sbw-version is not
  # drift, so counting it here would report a file's worth of work on every repo
  # after every release — the exact noise that fix removed.
  n="$(printf '%s\n' "${out}" | grep -E '^  (wrote|would write|would remove|removed):' | grep -cv '\.sbw-version')"
  printf '  %-30s %-9s %-3s file(s)  %s\n' "${name}" "${mode[*]:-shared}" "${n}" "${scope:-}"
done <<EOF
$(sbw_registry_read)
EOF

# --- 5. what is left for a human -------------------------------------------
step "Left for you"
echo "  - review each repo's diff, then commit and push. Nothing here commits."
echo "  - a --local repo should still show a clean 'git status'; if it does not,"
echo "    the render wrote something tracked and wants looking at."
"${STANDARDS_DIR}/scripts/doctor.sh" --vault "${VAULT}" 2>&1 | grep -E '^  (ERROR|warn)' | sed 's/^/  /' || true
echo
# The count means two different things, and only one of them is a finding.
#
# In preview it is work *pending*, so a non-zero exit is right: a caller — a
# person reading `make adopt`, or a script gating on it — is being told there is
# something to do. After `--yes` the same number is work *done*, and exiting
# non-zero on it turned a successful run into `make: *** [adopt] Error 1`,
# reported on the machine it was written for, the morning it shipped.
#
# A tool that has just completed its job must say so with its exit code. What
# still needs a human is in the report above and never blocks; a real failure
# exits before reaching here.
if act; then
  echo "Done. ${todo} change(s) made."
  exit 0
fi
echo "Preview only — ${todo} change(s) would be made. Re-run with --yes."
[ "${todo}" -eq 0 ] || exit 1
exit 0
