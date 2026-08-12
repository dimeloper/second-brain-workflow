#!/usr/bin/env bash
# The vault-ci templates are the only thing this repo ships that runs inside
# somebody else's repository, holding somebody else's token. Nothing here
# executes them — that needs GitHub — so this checks the one class of mistake
# that a local run cannot catch and a green CI badge does not rule out.
#
# `${{ ... }}` inside an `actions/github-script` `script:` block is textual
# substitution into JavaScript source before node parses it. Whatever it
# expands to is *code*, not data. audit.yml pasted the audit report in that way
# and worked for twenty-six releases, because the reports it saw happened to
# contain no JavaScript punctuation. The first report that did — check-lineage.py
# writes `repos:` in backticks — closed the template literal and failed the job
# with `SyntaxError: Unexpected identifier 'repos'`.
#
# The syntax error is the harmless half. The same substitution means a `${...}`
# in any note title or rule body reaching the report is *evaluated*, in a job
# with `issues: write`. So this is a fail-closed check on a security property,
# not a style rule: pass values through `env:` and read them with process.env,
# where nothing in them can be code.
# shellcheck source=tests/lib.sh
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
setup_sandbox

TEMPLATES="${ENGINE}/docs/vault-ci"

echo "vault-ci templates"

# Reports the line of every `${{ }}` that lands inside a script: block, and
# exits 1 when there is one. Indentation decides where the block ends, which is
# what YAML itself uses for a literal scalar.
scan() {
  python3 - "$1" <<'PY'
import re
import sys

lines = open(sys.argv[1], encoding="utf-8").read().splitlines()
inside = None
bad = []
for number, line in enumerate(lines, 1):
    opener = re.match(r'^(\s*)script:\s*[|>]', line)
    if opener:
        inside = len(opener.group(1))
        continue
    if inside is None:
        continue
    indent = len(line) - len(line.lstrip())
    if line.strip() and indent <= inside:
        inside = None            # dedented out of the block
        continue
    if "${{" in line:
        bad.append(f"{number}: {line.strip()}")
print("\n".join(bad))
sys.exit(1 if bad else 0)
PY
}

for template in "${TEMPLATES}"/*.yml; do
  name="$(basename "${template}")"
  out="$(scan "${template}" 2>&1)"
  rc=$?
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ "${rc}" -eq 0 ]; then
    pass "${name} interpolates nothing into a github-script block"
  else
    fail "${name} interpolates nothing into a github-script block" "${out}"
  fi
done

# A check nobody has watched fail is a check nobody knows works. This repo has
# already shipped one assertion that could not fail — the release-tag check that
# reported "undetermined" in CI while passing locally — so the scanner is shown
# catching the exact line that was fixed.
BROKEN="${SANDBOX}/broken.yml"
cat > "${BROKEN}" <<'YML'
jobs:
  audit:
    steps:
      - uses: actions/github-script@v7
        with:
          script: |
            const body = `${{ steps.audit.outputs.report }}`;
            await github.rest.issues.create({ body });
      - name: a later step may interpolate freely
        run: echo "${{ github.repository }}"
YML
out="$(scan "${BROKEN}" 2>&1)"
rc=$?
assert_exit 1 "${rc}" "the scanner fails on the pattern that broke the audit job"

TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"steps.audit.outputs.report"*) pass "and names the offending line" ;;
  *) fail "and names the offending line" "${out}" ;;
esac

# ...while leaving alone the `${{ }}` that every workflow legitimately uses
# outside a script block. A check that flagged those would be turned off.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"github.repository"*) fail "a run: step's own interpolation is not flagged" "${out}" ;;
  *) pass "a run: step's own interpolation is not flagged" ;;
esac

# The safe form has to actually read as safe, or the fix is cosmetic.
assert_contains "${TEMPLATES}/audit.yml" 'REPORT: ' \
  "audit.yml passes the report through env:"
assert_contains "${TEMPLATES}/audit.yml" 'process.env.REPORT' \
  "audit.yml reads the report from process.env"

finish
