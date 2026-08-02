#!/usr/bin/env bash
# Prove that Claude Code actually loads what render.py emits.
#
#   ./verify-claude-load.sh
#
# Renders into a throwaway repo, then runs two headless sessions with an
# InstructionsLoaded hook attached and inspects what loaded:
#
#   1. reading a file that matches a rule's globs  -> the rule must load
#   2. reading a file that matches nothing         -> it must not
#
# The second run is the one that matters. Without it, "the rule loaded" is
# consistent with every rule always loading, which would make path scoping
# decorative. Run this on a new machine before trusting the toolchain there.
#
# Costs two small model calls. Needs `claude` on PATH.
set -euo pipefail

STANDARDS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v claude >/dev/null || { echo "claude not on PATH" >&2; exit 2; }

# Pick a rule with globs, and build a filename its first glob matches.
read -r RULE GLOB <<EOF
$("${STANDARDS_DIR}/scripts/render.py" --explain \
  | awk '/\[scoped: /{name=$1; sub(/.*\[scoped: /,""); sub(/\].*/,""); split($0,g,", "); print name, g[1]; exit}')
EOF
[ -n "${RULE:-}" ] || { echo "No glob-scoped rule to test." >&2; exit 1; }

# `**/*.component.ts` -> `probe.component.ts`
MATCHING="probe$(basename "${GLOB}" | sed 's/^\*//')"
case "${MATCHING}" in */*|"") MATCHING="probe.ts" ;; esac

WORK="$(mktemp -d "${TMPDIR:-/tmp}/verify-claude-load.XXXXXX")"
trap 'rm -rf "${WORK}"' EXIT INT TERM
cd "${WORK}"
git init -q .

mkdir -p src
printf '// probe file for %s\n' "${RULE}" > "src/${MATCHING}"
printf 'plain text, matches no rule glob\n' > "src/probe-nonmatching.txt"

"${STANDARDS_DIR}/scripts/render.py" "${WORK}" --targets claude-code >/dev/null

mkdir -p .claude
cat > .claude/settings.json <<'JSON'
{
  "hooks": {
    "InstructionsLoaded": [
      { "hooks": [ { "type": "command", "command": "cat >> .claude/loaded.jsonl" } ] }
    ]
  }
}
JSON

probe() {
  : > .claude/loaded.jsonl
  claude -p "Read $1 and reply with exactly: OK" \
    --allowedTools Read --permission-mode acceptEdits >/dev/null 2>&1 </dev/null || true
  python3 - "$2" <<'PY'
import json, os, sys
want = sys.argv[1]
hits = []
for line in open('.claude/loaded.jsonl'):
    line = line.strip()
    if not line:
        continue
    d = json.loads(line)
    hits.append((d.get('load_reason'), os.path.basename(d.get('file_path', '-'))))
for reason, name in hits:
    print(f"    {reason:16} {name}")
print("MATCH" if any(r == 'path_glob_match' and n == want for r, n in hits) else "NOMATCH")
PY
}

echo "Rule under test: ${RULE}  (glob ${GLOB})"
echo
echo "  1. reading src/${MATCHING} — expect the rule to load"
out1="$(probe "src/${MATCHING}" "${RULE}.md")"
echo "${out1}" | sed '$d'
r1="$(echo "${out1}" | tail -1)"

echo
echo "  2. reading src/probe-nonmatching.txt — expect it not to"
out2="$(probe "src/probe-nonmatching.txt" "${RULE}.md")"
echo "${out2}" | sed '$d'
r2="$(echo "${out2}" | tail -1)"

echo
if [ "${r1}" = "MATCH" ] && [ "${r2}" = "NOMATCH" ]; then
  echo "PASS — the rule loads on a matching file and not otherwise."
  echo "       CLAUDE.md loads at session_start; AGENTS.md loads via its @import."
  exit 0
fi
echo "FAIL — expected MATCH then NOMATCH, got ${r1} then ${r2}." >&2
[ "${r1}" = "MATCH" ] || echo "       The rule never loaded. Check the glob against the probe filename." >&2
[ "${r2}" = "MATCH" ] && echo "       The rule loaded for a non-matching file — scoping is not working." >&2
exit 1
