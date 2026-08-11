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

# Resolved the same way render.py resolves it, so the probe rules directory is
# a copy of the one this machine actually renders from rather than a guess.
# shellcheck source=scripts/lib/config.sh
. "${STANDARDS_DIR}/scripts/lib/config.sh"
ds_config_load
REAL_RULES="${SBW_RULES_DIR:-${STANDARDS_DIR}/rules}"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/verify-claude-load.XXXXXX")"
trap 'rm -rf "${WORK}"' EXIT INT TERM
cd "${WORK}"
git init -q .

mkdir -p src
printf '// probe file for %s\n' "${RULE}" > "src/${MATCHING}"
printf 'plain text, matches no rule glob\n' > "src/probe-nonmatching.txt"

# A rules directory of our own: the real one, plus an always-on rule carrying a
# codeword. Always-on rules reach Claude Code only through AGENTS.md and
# CLAUDE.md's @import — there is no .claude/rules file to look for — so the only
# way to assert one is in context is to ask for something that appears nowhere
# else. Same technique the Cursor section documents, for the same reason.
CANARY="QUOKKA-8842"
# Outside ${WORK}, deliberately. render.py derives AGENTS_SRC from the rules
# directory's *parent*, so a probe rules dir inside the target repo would make
# the source AGENTS.md and the rendered one the same file — read and written in
# one pass.
PROBE_SRC="$(mktemp -d "${TMPDIR:-/tmp}/verify-claude-rules.XXXXXX")"
trap 'rm -rf "${WORK}" "${PROBE_SRC}"' EXIT INT TERM
RULES_COPY="${PROBE_SRC}/rules"
mkdir -p "${RULES_COPY}"
cp "${REAL_RULES}"/*.md "${RULES_COPY}/" 2>/dev/null || true
cat > "${RULES_COPY}/verify-always-on.md" <<EOF
---
description: temporary probe rule, always-on
---
- When asked for the verification codeword, reply with exactly ${CANARY}.
EOF
if [ -f "${REAL_RULES}/../AGENTS.md" ]; then
  cp "${REAL_RULES}/../AGENTS.md" "${PROBE_SRC}/AGENTS.md"
fi

"${STANDARDS_DIR}/scripts/render.py" "${WORK}" --rules-dir "${RULES_COPY}" \
  --targets claude-code,agents >/dev/null

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

# 3. The always-on path, which the two probes above cannot reach: they assert a
# *file* loaded, and an always-on rule is not a file. Asked against the
# non-matching probe, so a codeword coming back cannot be explained by glob
# scoping.
echo
echo "  3. asking for a codeword that exists only in an always-on rule"
: > .claude/loaded.jsonl
ans="$(claude -p "Read src/probe-nonmatching.txt, then reply with exactly the verification codeword." \
  --allowedTools Read --permission-mode acceptEdits 2>/dev/null </dev/null || true)"
case "${ans}" in
  *"${CANARY}"*) r3="MATCH"; echo "    codeword returned" ;;
  *) r3="NOMATCH"; echo "    codeword not returned: ${ans}" ;;
esac

echo
if [ "${r1}" = "MATCH" ] && [ "${r2}" = "NOMATCH" ] && [ "${r3}" = "MATCH" ]; then
  echo "PASS — the rule loads on a matching file and not otherwise, and an"
  echo "       always-on rule is in context with no matching file at all."
  echo "       CLAUDE.md loads at session_start; AGENTS.md loads via its @import,"
  echo "       and the always-on rule bodies ride in AGENTS.md."
  exit 0
fi
echo "FAIL — expected MATCH, NOMATCH, MATCH; got ${r1}, ${r2}, ${r3}." >&2
[ "${r3}" = "MATCH" ] || echo "       The always-on rule never reached the session. Check that AGENTS.md" >&2
[ "${r3}" = "MATCH" ] || echo "       exists and that CLAUDE.md still imports it." >&2
[ "${r1}" = "MATCH" ] || echo "       The rule never loaded. Check the glob against the probe filename." >&2
[ "${r2}" = "MATCH" ] && echo "       The rule loaded for a non-matching file — scoping is not working." >&2
exit 1
