#!/usr/bin/env bash
# check-rules.py: validates rule frontmatter against the shape the rest of the
# system reads. Fixtures are written into the sandbox rather than committed,
# because most of them are deliberately malformed and a committed broken rule
# would be picked up by render.py's own fixtures.
# shellcheck source=tests/lib.sh
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
setup_sandbox

CHECK="${ENGINE}/scripts/check-rules.py"
TEMPLATE="${ENGINE}/rule.md.example"

echo "check-rules.py"

# --- a well-formed rule set is silent and green -----------------------------
GOOD_R="${SANDBOX}/good-rules"
mkdir -p "${GOOD_R}"
cat > "${GOOD_R}/scoped.md" <<'EOF'
---
paths:
  - "**/*.component.ts"
description: Angular component conventions
source: [prefer-signal-apis, next-server-components-by-default]
---

Fixture rule body.
EOF
# No `paths` is legal and meaningful — that's an always-on rule, not a defect.
# A scalar source is legal too; check-lineage.py coerces it to a one-element
# list, and this must not second-guess that.
cat > "${GOOD_R}/always-on.md" <<'EOF'
---
description: Always-on conventions
source: mcp-per-project
---

Fixture rule body.
EOF
out_good="$("${CHECK}" --rules-dir "${GOOD_R}" 2>/dev/null)"
assert_exit 0 $? "a well-formed rule set exits 0"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_good}" in
  *"Rules checked: 2    Findings: 0"*) pass "a well-formed rule set reports no findings" ;;
  *) fail "a well-formed rule set reports no findings" "${out_good}" ;;
esac

# --- a misspelled key is the whole reason this script exists ----------------
# Nothing reads `sourse:`, and nothing else in the system would ever say so:
# the rule renders, diffs clean, and records no lineage.
TYPO_R="${SANDBOX}/typo-rules"
mkdir -p "${TYPO_R}"
cat > "${TYPO_R}/typo.md" <<'EOF'
---
paths:
  - "**/*.ts"
description: A rule whose lineage key is misspelled
sourse: prefer-signal-apis
---

Fixture rule body.
EOF
out_typo="$("${CHECK}" --rules-dir "${TYPO_R}" 2>/dev/null)"
rc_typo=$?
assert_exit 1 "${rc_typo}" "a misspelled key fails"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_typo}" in
  *"unknown key 'sourse'"*) pass "the misspelled key is named" ;;
  *) fail "the misspelled key is named" "${out_typo}" ;;
esac
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_typo}" in
  *"Known keys: description, paths, provisional, source"*) pass "the known key set is listed so the typo is obvious" ;;
  *) fail "the known key set is listed so the typo is obvious" "${out_typo}" ;;
esac
# The typo means the rule also has no source at all — both must be reported,
# not just the first. Fixing the spelling and re-running should be the last
# step, not the start of a new round of findings.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_typo}" in
  *"no 'source:'"*) pass "a typo'd lineage key also reports as no source" ;;
  *) fail "a typo'd lineage key also reports as no source" "${out_typo}" ;;
esac

# --- a missing source is caught at authoring time ---------------------------
NOSRC_R="${SANDBOX}/nosource-rules"
mkdir -p "${NOSRC_R}"
cat > "${NOSRC_R}/no-source.md" <<'EOF'
---
paths:
  - "**/*.ts"
description: Perfectly valid, records no lineage
---

Fixture rule body.
EOF
out_nosrc="$("${CHECK}" --rules-dir "${NOSRC_R}" 2>/dev/null)"
rc_nosrc=$?
assert_exit 1 "${rc_nosrc}" "a rule with no source fails"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_nosrc}" in
  *"no 'source:'"*"rule.md.example"*) pass "the missing-source finding points at the template" ;;
  *) fail "the missing-source finding points at the template" "${out_nosrc}" ;;
esac

# --- a key that looks declared but declares nothing --------------------------
# `source:` with nothing after it parses to an empty list. It reads, in a diff,
# exactly like a rule that recorded its lineage.
BLANK_R="${SANDBOX}/blank-rules"
mkdir -p "${BLANK_R}"
cat > "${BLANK_R}/blank.md" <<'EOF'
---
paths:
description: Both list keys present, neither declaring anything
source:
---

Fixture rule body.
EOF
out_blank="$("${CHECK}" --rules-dir "${BLANK_R}" 2>/dev/null)"
rc_blank=$?
assert_exit 1 "${rc_blank}" "empty list keys fail"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_blank}" in
  *"'source:' is present but empty"*) pass "an empty source: is reported as declaring nothing" ;;
  *) fail "an empty source: is reported as declaring nothing" "${out_blank}" ;;
esac
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_blank}" in
  *"'paths:' is present but empty"*) pass "an empty paths: is reported too" ;;
  *) fail "an empty paths: is reported too" "${out_blank}" ;;
esac

# --- no frontmatter at all --------------------------------------------------
NOFM_R="${SANDBOX}/nofm-rules"
mkdir -p "${NOFM_R}"
printf 'Just a body, no frontmatter block at all.\n' > "${NOFM_R}/bare.md"
out_nofm="$("${CHECK}" --rules-dir "${NOFM_R}" 2>/dev/null)"
rc_nofm=$?
assert_exit 1 "${rc_nofm}" "a rule with no frontmatter fails"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_nofm}" in
  *"no frontmatter block"*) pass "a rule with no frontmatter says so" ;;
  *) fail "a rule with no frontmatter says so" "${out_nofm}" ;;
esac

# --- a missing rules directory is a named failure, not an empty green run ----
out_missing="$("${CHECK}" --rules-dir "${SANDBOX}/does-not-exist" 2>&1)"
rc_missing=$?
assert_exit 1 "${rc_missing}" "a missing rules directory fails loudly"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_missing}" in
  *"No rules directory"*) pass "a missing rules directory is named" ;;
  *) fail "a missing rules directory is named" "${out_missing}" ;;
esac

# --- provisional: prose, never a boolean ------------------------------------
# The field exempts a rule from the "source must be enforced" lineage check. A
# boolean exemption outlives the reason it was added for with nothing left to
# read, so the reason *is* the field — and `true` is the first thing anyone
# reaching for a flag will write, which is why it is rejected by name rather
# than quietly accepted as a truthy string.
PROV_R="${SANDBOX}/prov-rules"
mkdir -p "${PROV_R}"
cat > "${PROV_R}/reasoned.md" <<'EOF'
---
paths:
  - "**/*.ts"
description: Cites an immature source on purpose
source: some-note
provisional: read off what the tool writes, so no repo count will mature it
---

Fixture rule body.
EOF
"${CHECK}" --rules-dir "${PROV_R}" >/dev/null 2>&1
assert_exit 0 $? "a provisional reason is accepted"

cat > "${PROV_R}/reasoned.md" <<'EOF'
---
paths:
  - "**/*.ts"
description: Reaches for a flag instead of a reason
source: some-note
provisional: true
---

Fixture rule body.
EOF
out_bool="$("${CHECK}" --rules-dir "${PROV_R}" 2>&1)"
assert_exit 1 $? "a boolean provisional fails"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_bool}" in
  *"is a boolean — write the reason instead"*) pass "the boolean finding says to write a reason" ;;
  *) fail "the boolean finding says to write a reason" "${out_bool}" ;;
esac

cat > "${PROV_R}/reasoned.md" <<'EOF'
---
paths:
  - "**/*.ts"
description: Declares an exemption and justifies nothing
source: some-note
provisional:
---

Fixture rule body.
EOF
out_blank_p="$("${CHECK}" --rules-dir "${PROV_R}" 2>&1)"
assert_exit 1 $? "an empty provisional fails"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_blank_p}" in
  *"'provisional:' is present but empty"*) pass "an empty provisional is named as such" ;;
  *) fail "an empty provisional is named as such" "${out_blank_p}" ;;
esac

# --- template parity --------------------------------------------------------
# The shape this whole thread is about: a convention that lives in a script but
# not in the template someone copies. `source:` was documented in AUDIT.md and
# in check-lineage.py's docstring, and appeared in none of the four rules
# anyone actually wrote — so both directions are asserted here.
assert_file "${TEMPLATE}" "the rule template exists"

# 1. The template must satisfy the validator. If it didn't, every rule copied
#    from it would start life with a finding.
TMPL_R="${SANDBOX}/template-rules"
mkdir -p "${TMPL_R}"
cp "${TEMPLATE}" "${TMPL_R}/from-template.md"
"${CHECK}" --rules-dir "${TMPL_R}" >/dev/null 2>&1
assert_exit 0 $? "the template passes the validator it documents"

# 2. Every key the validator knows about must appear in the template, read out
#    of the script itself rather than restated here — a list duplicated into a
#    test drifts exactly as readily as one duplicated into a template.
keys="$(python3 -c "
import importlib.util
spec = importlib.util.spec_from_file_location('cr', '${ENGINE}/scripts/check-rules.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
print(' '.join(sorted(m.KNOWN_KEYS)))
")"
TESTS_RUN=$((TESTS_RUN + 1))
if [ -z "${keys}" ]; then
  fail "the known key set could be read from check-rules.py" "empty"
else
  pass "the known key set could be read from check-rules.py"
fi
# A key counts as documented whether it is pre-filled in the frontmatter or
# shown in a commented example. Both forms are documentation; the difference is
# whether the key is a sensible *default*, and some are deliberately not. A
# rule copied from the template must not arrive already claiming a lineage
# exemption, so `provisional:` is documented and not pre-filled — requiring
# every known key to be live in the template would force exactly the bad
# default this check is meant to protect against.
for key in ${keys}; do
  TESTS_RUN=$((TESTS_RUN + 1))
  if grep -qE "^${key}:|^#[[:space:]]+${key}:" "${TEMPLATE}"; then
    pass "the template documents '${key}:'"
  else
    fail "the template documents '${key}:'" "not found in ${TEMPLATE}, live or commented"
  fi
done

finish
