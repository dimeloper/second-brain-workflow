#!/usr/bin/env bash
# Choosing a probe path for verify-claude-load.sh.
#
# This logic silently rotted for two weeks and nothing here caught it, because
# `verify-claude-load.sh` costs two model calls and is therefore outside
# `make check`. The pure half is now importable, so the part that broke is the
# part that is tested; the script keeps only the model calls.
#
# What broke: the probe filename was `probe` + the glob's basename with a
# leading `*` stripped, so `**/lib/auth.ts` became `probeauth.ts`. It matched
# nothing, the run reported FAIL, and FAIL there reads as "path scoping is
# broken" — the conclusion the whole check exists to rule out.
# shellcheck source=tests/lib.sh
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"

echo "probe path selection"

py() { PYTHONPATH="${ENGINE}/scripts" python3 -c "$1" 2>&1; }

# One case per glob shape, asserted as glob -> expected path (or NONE).
# `-` in the expected column means the shape must be refused.
while IFS='|' read -r glob want; do
  [ -n "${glob}" ] || continue
  got="$(py "
from lib.probe_path import probe_for_glob
print(probe_for_glob('''${glob}''') or 'NONE')
")"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ "${got}" = "${want}" ]; then
    pass "${glob} -> ${want}"
  else
    fail "${glob} -> ${want}" "got '${got}'"
  fi
done <<'CASES'
**/lib/auth.ts|src/lib/auth.ts
**/*.tsx|src/probe.tsx
**/*.dart|src/probe.dart
**/*.component.ts|src/probe.component.ts
data/db.ts|data/db.ts
app.json|app.json
targets/**/*.swift|NONE
app.config.*|NONE
**/api/**/*.py|NONE
**/|NONE
CASES

# The regression itself, stated as the property that failed rather than as one
# more case: a returned path must actually match the glob it was built for.
# fnmatch is not the matcher Claude Code uses, but it agrees on these shapes and
# is enough to catch a probe that matches nothing at all — which is the whole
# defect.
out="$(py "
from fnmatch import fnmatch
from lib.probe_path import probe_for_glob
bad = []
for g in ['**/lib/auth.ts', '**/*.tsx', '**/*.dart', 'data/db.ts', 'app.json',
          '**/_layout.tsx', '**/pubspec.yaml', '**/core/config.py']:
    p = probe_for_glob(g)
    if p is None:
        continue
    # '**/x' matches 'a/x'; fnmatch needs the '**' spelled as '*' per segment.
    if not (fnmatch(p, g) or fnmatch(p, g.replace('**/', '*/'))):
        bad.append((g, p))
print('ALLMATCH' if not bad else 'MISMATCH ' + repr(bad))
")"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  ALLMATCH) pass "every path returned is matched by the glob it was built for" ;;
  *) fail "every path returned is matched by the glob it was built for" "${out}" ;;
esac

# Selection scans past rules it cannot serve rather than failing on the first —
# the behaviour that stops one reordered rule set from disabling the check.
out="$(py "
from lib.probe_path import select
explain = '''app-store-assets  [scoped: app.config.*]
app-expo-ios-native  [scoped: targets/**/*.swift, data/db.ts]
app-flutter  [scoped: **/*.dart]'''
print(*(select(explain) or ('NONE',)))
")"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  "app-expo-ios-native data/db.ts data/db.ts")
    pass "skips an unusable rule and an unusable glob, taking the first it can serve" ;;
  *) fail "skips an unusable rule and an unusable glob, taking the first it can serve" "${out}" ;;
esac

# Nothing usable is None, not a guess. The caller turns this into a refusal with
# an explanation; a plausible-looking path here would be reported as a failing
# check on a healthy machine, which is the bug this file exists for.
out="$(py "
from lib.probe_path import select
print(select('rule-a  [scoped: app.config.*]\nrule-b  [scoped: a/**/b/*.x]') or 'NONE')
")"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  NONE) pass "no serviceable glob returns None rather than a guess" ;;
  *) fail "no serviceable glob returns None rather than a guess" "${out}" ;;
esac

# An unscoped rule carries no globs and must not be picked: an always-on rule
# loads on every file, so it can never demonstrate that scoping works.
out="$(py "
from lib.probe_path import select
explain = '''verify-integrations  [always-on]
app-flutter  [scoped: **/*.dart]'''
print(*(select(explain) or ('NONE',)))
")"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  "app-flutter **/*.dart src/probe.dart")
    pass "an always-on rule is passed over — it cannot demonstrate scoping" ;;
  *) fail "an always-on rule is passed over — it cannot demonstrate scoping" "${out}" ;;
esac

# The script and the library must not drift back into two implementations.
TESTS_RUN=$((TESTS_RUN + 1))
if grep -q 'lib.probe_path' "${ENGINE}/scripts/verify-claude-load.sh"; then
  pass "verify-claude-load.sh selects through the library, not a copy of it"
else
  fail "verify-claude-load.sh selects through the library, not a copy of it" \
    "no reference to lib.probe_path"
fi

finish
