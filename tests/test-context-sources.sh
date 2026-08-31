#!/usr/bin/env bash
# context-sources.py: where a repo already states what its product is.
#
# Fixtures only — a real repo would make the tier contents depend on whoever
# ran it, and this asserts on which tiers are empty.
# shellcheck source=tests/lib.sh
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
setup_sandbox

CS="${ENGINE}/scripts/context-sources.py"

echo "context-sources.py"

# --- a repo with all four tiers populated -----------------------------------
FULL="${SANDBOX}/full-app"
mkdir -p "${FULL}/docs/features" "${FULL}/metadata/ios" "${FULL}/src/i18n/locales" "${FULL}/assets"
printf '# Roadmap\n\n## Phase 5 — Post-Birth Retention\n' > "${FULL}/ROADMAP.md"
printf '# Knowledge base\n' > "${FULL}/KNOWLEDGE_BASE.md"
printf '# Letters\n' > "${FULL}/docs/features/LETTER_TO_BABY.md"
printf 'A pitch.\n' > "${FULL}/metadata/ios/description.txt"
printf '{"common":{}}\n' > "${FULL}/src/i18n/locales/en.json"
printf '{"common":{}}\n' > "${FULL}/src/i18n/locales/el.json"
printf 'export default {}\n' > "${FULL}/app.config.ts"
: > "${FULL}/assets/icon.png"

out="$("${CS}" --repo "${FULL}" 2>&1)"
assert_exit 0 $? "surveys a repo cleanly"

for tier in "PRODUCT DOCS" "STORE METADATA" "SHIPPED SURFACE" "BRAND"; do
  TESTS_RUN=$((TESTS_RUN + 1))
  case "${out}" in
    *"${tier}"*) pass "reports the ${tier} tier" ;;
    *) fail "reports the ${tier} tier" "${out}" ;;
  esac
done

TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *ROADMAP.md*KNOWLEDGE_BASE.md*) pass "finds the product docs, roadmap first" ;;
  *) fail "finds the product docs" "${out}" ;;
esac
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"locales/el.json"*) pass "finds locale files as shipped surface" ;;
  *) fail "finds locale files" "${out}" ;;
esac
# The ordering is the skill's whole point, so the report has to state it.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"Read tier 1 before tier 2"*) pass "states the reading order, not just the files" ;;
  *) fail "states the reading order" "${out}" ;;
esac
# A full repo has nothing empty, so the disclosure must not fire.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *EMPTY*) fail "no empty-tier disclosure when every tier is populated" "${out}" ;;
  *) pass "no empty-tier disclosure when every tier is populated" ;;
esac

# --- an empty tier is a finding, and must be named --------------------------
# The substitution this exists to stop: a populated tier standing in for an
# absent one, which is how an audience gets inferred from marketing copy.
THIN="${SANDBOX}/thin-app"
mkdir -p "${THIN}/metadata/ios"
printf 'A pitch and nothing else.\n' > "${THIN}/metadata/ios/description.txt"
out_thin="$("${CS}" --repo "${THIN}" 2>&1)"
assert_exit 0 $? "a repo with only a listing still surveys cleanly"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_thin}" in
  *EMPTY*"product docs"*) pass "names product docs as empty when there are none" ;;
  *) fail "names an empty tier" "${out_thin}" ;;
esac
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_thin}" in
  *"do not derive it"*) pass "and says not to derive the answer from a populated tier" ;;
  *) fail "says not to derive from a populated tier" "${out_thin}" ;;
esac
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_thin}" in
  *"(nothing)"*) pass "an empty tier prints (nothing) rather than being omitted" ;;
  *) fail "an empty tier prints (nothing)" "${out_thin}" ;;
esac

# --- a stack this engine meets must not report a false empty ----------------
# The defect: tier-3 and tier-4 globs were JS/TS-shaped, so a Flutter app with
# a complete light/dark palette reported "brand: (nothing)" — and an empty tier
# instructs the reader to record the answer as unestablished. A false empty is
# worse than no survey, because it is a confident wrong answer rather than a
# missing one.
DART="${SANDBOX}/dart-app"
mkdir -p "${DART}/lib/shared/themes" "${DART}/lib/l10n" \
         "${DART}/android/app/src/main/res/values"
printf 'class AppColors { static const lightPrimary = Color(0xFF04AE66); }\n' \
  > "${DART}/lib/shared/themes/app_colors.dart"
printf 'class AppTheme {}\n' > "${DART}/lib/shared/themes/app_theme.dart"
printf '{"@@locale":"en"}\n' > "${DART}/lib/l10n/app_en.arb"
printf '<resources/>\n' > "${DART}/android/app/src/main/res/values/colors.xml"
out_dart="$("${CS}" --repo "${DART}" 2>&1)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_dart}" in
  *app_colors.dart*) pass "a Dart palette is found, not reported as an empty brand tier" ;;
  *) fail "a Dart palette is found" "${out_dart}" ;;
esac
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_dart}" in
  *app_en.arb*) pass "an .arb locale file counts as shipped surface" ;;
  *) fail "an .arb locale file counts as shipped surface" "${out_dart}" ;;
esac
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_dart}" in
  *"EMPTY"*brand*) fail "brand is not reported empty when a palette exists" "${out_dart}" ;;
  *) pass "brand is not reported empty when a palette exists" ;;
esac

# Android and Apple string catalogues are shipped surface too.
NATIVE="${SANDBOX}/native-app"
mkdir -p "${NATIVE}/app/src/main/res/values-el" "${NATIVE}/ios/el.lproj"
printf '<resources><string name="a">x</string></resources>\n' \
  > "${NATIVE}/app/src/main/res/values-el/strings.xml"
printf '"a" = "x";\n' > "${NATIVE}/ios/el.lproj/Localizable.strings"
out_native="$("${CS}" --repo "${NATIVE}" 2>&1)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_native}" in
  *strings.xml*Localizable.strings*|*Localizable.strings*strings.xml*)
    pass "Android and Apple string catalogues count as shipped surface" ;;
  *) fail "Android and Apple string catalogues count" "${out_native}" ;;
esac

# --- dependency directories are never a product's own statement -------------
NOISY="${SANDBOX}/noisy-app"
mkdir -p "${NOISY}/node_modules/somepkg/docs/features" \
         "${NOISY}/node_modules/somepkg/messages" "${NOISY}/dist" "${NOISY}/.git"
printf '# not ours\n' > "${NOISY}/node_modules/somepkg/docs/features/X.md"
printf '{"a":1}\n' > "${NOISY}/node_modules/somepkg/messages/en.json"
out_noisy="$("${CS}" --repo "${NOISY}" 2>&1)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_noisy}" in
  *node_modules*) fail "node_modules is never reported" "${out_noisy}" ;;
  *) pass "node_modules is never reported" ;;
esac

# --- a root-only file is not matched three levels down ----------------------
# A ROADMAP.md inside a dependency is somebody else's product.
DEEP="${SANDBOX}/deep-app"
mkdir -p "${DEEP}/packages/inner"
printf '# theirs\n' > "${DEEP}/packages/inner/ROADMAP.md"
out_deep="$("${CS}" --repo "${DEEP}" 2>&1)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_deep}" in
  *ROADMAP.md*) fail "a nested ROADMAP.md is not treated as this product's" "${out_deep}" ;;
  *) pass "a nested ROADMAP.md is not treated as this product's" ;;
esac

# --- case-insensitive at the root -------------------------------------------
CASE="${SANDBOX}/case-app"
mkdir -p "${CASE}"
printf '# lowercase\n' > "${CASE}/Roadmap.md"
out_case="$("${CS}" --repo "${CASE}" 2>&1)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_case}" in
  *Roadmap.md*) pass "matches a root doc whatever its case" ;;
  *) fail "matches a root doc whatever its case" "${out_case}" ;;
esac

# --- it never reads or writes -----------------------------------------------
# The contract: it says where to read, and the reading is the skill's job.
before="$(find "${FULL}" -type f | sort | xargs shasum | shasum)"
"${CS}" --repo "${FULL}" >/dev/null 2>&1
after="$(find "${FULL}" -type f | sort | xargs shasum | shasum)"
TESTS_RUN=$((TESTS_RUN + 1))
if [ "${before}" = "${after}" ]; then
  pass "surveys without touching the repo"
else
  fail "surveys without touching the repo" "something changed"
fi
# Contents must never appear: a tool that summarised these would be one more
# thing between a reader and the source.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"Post-Birth Retention"*) fail "file contents are never printed, only paths" "${out}" ;;
  *) pass "file contents are never printed, only paths" ;;
esac

# --- errors -----------------------------------------------------------------
"${CS}" --repo "${SANDBOX}/nope" >/dev/null 2>&1
assert_exit 1 $? "a missing repo is an error"

finish
