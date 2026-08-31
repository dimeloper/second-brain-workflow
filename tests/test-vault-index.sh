#!/usr/bin/env bash
# build-vault-index.py: determinism, parsing, warnings, and --check.
# shellcheck source=tests/lib.sh
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
setup_sandbox

INDEX="${ENGINE}/scripts/build-vault-index.py"
VAULT="${SANDBOX}/vault"
cp -R "${FIXTURES}/vault" "${VAULT}"

echo "build-vault-index.py"

"${INDEX}" --vault "${VAULT}" >/dev/null 2>&1
assert_exit 0 $? "generates an index"
assert_file "${VAULT}/practices/INDEX.md" "INDEX.md written"

# Determinism is the whole contract: a no-change run must be a zero-byte diff,
# otherwise every session dirties the vault.
cp "${VAULT}/practices/INDEX.md" "${SANDBOX}/first.md"
"${INDEX}" --vault "${VAULT}" >/dev/null 2>&1
diff -q "${SANDBOX}/first.md" "${VAULT}/practices/INDEX.md" >/dev/null 2>&1
assert_exit 0 $? "two runs produce identical output"

assert_contains "${VAULT}/practices/INDEX.md" 'validate-at-the-boundary' "lists a note"
assert_contains "${VAULT}/practices/INDEX.md" 'enforced' "carries maturity"
assert_contains "${VAULT}/practices/INDEX.md" 'Parse untrusted input' "summarises single-line Rule"
assert_contains "${VAULT}/practices/INDEX.md" 'input()' "summarises multi-line Rule block"
assert_not_contains "${VAULT}/practices/INDEX.md" '2026-08' "no timestamp — it would churn daily"

# --- the compatibility guarantee, asserted before the new behaviour ---------
# A vault that has not declared an applications bar has not adopted the two-bar
# model, and its index must keep the column it was built with. `--check` is a
# drift gate: an engine upgrade that reformats a generated file would turn every
# adopter's next CI run red for a change they did not make.
assert_contains "${VAULT}/practices/INDEX.md" '| Note | Maturity | Repos |' \
  "a vault with no applications bar keeps the Repos column"
assert_contains "${VAULT}/practices/INDEX.md" '| 3 |' \
  "...and a bare count, exactly as before"
assert_not_contains "${VAULT}/practices/INDEX.md" 'Evidence' \
  "...with nothing about a model it has not opted into"

# Opting in is declaring the bar in the vault's own promotion map — the same
# file the numbers have always been read from.
mkdir -p "${VAULT}/00-maps"
cat > "${VAULT}/00-maps/promotion-candidates.md" <<'MAP'
# Promotion candidates
```dataview
WHERE (maturity = "idea" AND length(repos) >= 2)
   OR (maturity = "trialing" AND length(repos) >= 3)
```
```dataview
WHERE (maturity = "idea" AND length(applications) >= 2)
   OR (maturity = "trialing" AND length(applications) >= 3)
```
MAP
"${INDEX}" --vault "${VAULT}" >/dev/null 2>&1

# The Evidence column carries the count that actually gates each note, with the
# unit attached. A bare number was ambiguous once two bars existed: `1` beside a
# process rule read as "one repo, two to go" when the repo count is not what
# that note is promoted on and never will be.
assert_contains "${VAULT}/practices/INDEX.md" '| 3 repos |' \
  "a scoped note is counted in repos"

# A process note is `domain: cross-cutting` AND `applies-to: ""`. The fixture's
# unscoped note is `domain: frontend`, which is *unscoped*, not process — so it
# stays on the repo bar, and the sandbox copy is retyped here to exercise the
# other branch. An empty `applies-to` alone was the old discriminator and was
# overloaded: the practice-note template makes it every new note's default.
edit_domain() {
  python3 - "$1" <<'PYX'
import sys
p = sys.argv[1]
s = open(p).read()
assert "domain: frontend" in s, "fixture no longer declares domain: frontend"
open(p, "w").write(s.replace("domain: frontend", "domain: cross-cutting", 1))
PYX
}
edit_domain "${VAULT}/practices/frontend/prefer-signals.md"
"${INDEX}" --vault "${VAULT}" >/dev/null 2>&1

# The three states of a process note, walked in order on the sandbox copy —
# tests/fixtures is left alone so the vault other suites read is unchanged.
#
# Nothing recorded at all is `—`. Zero would be a claim: it would read as
# evidence against every process note in a vault that has not migrated yet.
assert_contains "${VAULT}/practices/INDEX.md" '| — |' \
  "a process note with nothing recorded is uncounted, not zero"

SIGNALS="${VAULT}/practices/frontend/prefer-signals.md"
edit_note() {
  python3 - "${SIGNALS}" "$1" "$2" <<'PY'
import sys
path, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(path).read()
assert old in s, f"fixture no longer contains {old!r}"
open(path, 'w').write(s.replace(old, new, 1))
PY
  "${INDEX}" --vault "${VAULT}" >/dev/null 2>&1
}

# Repos but no applications: show what was seen, labelled so nobody reads it as
# progress toward a bar this note is not held to.
edit_note 'repos: []' 'repos: ["fixture-api", "fixture-web"]'
assert_contains "${VAULT}/practices/INDEX.md" '| 2 seen |' \
  "a process note with repos but no applications shows what was seen"

# Once applications exist they are the count, and the fallback stops.
edit_note 'applies-to: ""' 'applies-to: ""
applications: ["fixture-api 2026-01-01", "fixture-api 2026-02-02", "fixture-web 2026-03-03"]'
assert_contains "${VAULT}/practices/INDEX.md" '| 3 applied |' \
  "a process note with applications is counted in applications"
assert_not_contains "${VAULT}/practices/INDEX.md" '| 2 seen |' \
  "and stops being reported as merely seen"

# The point of the second bar, stated as an assertion: two applications in one
# repo count as two. Under the repo bar this note would show 2 and stall.
assert_contains "${VAULT}/practices/INDEX.md" '| 3 applied |' \
  "two applications in the same repo count separately"

# Malformed frontmatter warns but never fails the run.
out="$("${INDEX}" --vault "${VAULT}" 2>&1 >/dev/null)"
rc=$?
assert_exit 0 "${rc}" "warnings do not fail the run"
TESTS_RUN=$((TESTS_RUN + 1))
if grep -q "broken-frontmatter" <<< "${out}"; then
  pass "reports the malformed note"
else
  fail "reports the malformed note" "${out}"
fi
TESTS_RUN=$((TESTS_RUN + 1))
if grep -q "unknown maturity: bogus" <<< "${out}"; then
  pass "names the specific problem"
else
  fail "names the specific problem" "${out}"
fi

# --check
"${INDEX}" --vault "${VAULT}" --check >/dev/null 2>&1
assert_exit 0 $? "--check passes when current"
echo "| tampered |" >> "${VAULT}/practices/INDEX.md"
"${INDEX}" --vault "${VAULT}" --check >/dev/null 2>&1
assert_exit 1 $? "--check exits 1 when stale"

# A new note must appear without any other edit.
"${INDEX}" --vault "${VAULT}" >/dev/null 2>&1
cat > "${VAULT}/practices/backend/new-note.md" <<'EOF'
---
domain: backend
applies-to: ""
maturity: trialing
last-reviewed: 2026-03-01
repos: ["a", "b"]
tags: [new]
---

# A new note

**Rule:** Freshly added.
EOF
"${INDEX}" --vault "${VAULT}" >/dev/null 2>&1
assert_contains "${VAULT}/practices/INDEX.md" 'new-note' "picks up a new note"

# --- projects/INDEX.md ------------------------------------------------------
# The compatibility guarantee first, again: a vault that has never written a
# project doc must regenerate to exactly the bytes it had before this engine
# knew about them, or every adopter's next --check goes red for a change they
# did not make. An empty projects/ directory is that state too, not a stale one.
mkdir -p "${VAULT}/projects"
"${INDEX}" --vault "${VAULT}" >/dev/null 2>&1
assert_no_file "${VAULT}/projects/INDEX.md" \
  "an empty projects/ gets no index — nothing to index is not staleness"
"${INDEX}" --vault "${VAULT}" --check >/dev/null 2>&1
assert_exit 0 $? "...and --check is not made red by its absence"

cat > "${VAULT}/projects/vendor-migration.md" <<'EOF'
---
kind: project
status: active
started: 2026-01-04
last-reviewed: 2026-03-02
repos: ["alpha-service", "beta-app"]
tags: [migration]
---

# Vendor migration

<!-- an explanatory comment the template ships, which is not content -->

## TL;DR

- The vendor deprecates the v1 API in June [verified]

## Timeline

- 2026-01-04 — started [verified]
EOF
"${INDEX}" --vault "${VAULT}" >/dev/null 2>&1
assert_file "${VAULT}/projects/INDEX.md" "one project doc produces an index"
assert_contains "${VAULT}/projects/INDEX.md" 'vendor-migration' "lists the initiative"
assert_contains "${VAULT}/projects/INDEX.md" 'active' "carries its status"
assert_contains "${VAULT}/projects/INDEX.md" 'The vendor deprecates' \
  "summarises the TL;DR, not the template's comment"
assert_contains "${VAULT}/projects/INDEX.md" 'alpha-service, beta-app' "names the repos"

# A project doc is not a practice note, and the two indexes must not bleed: a
# row in the practices index would put an initiative one careless read away from
# being cited as a rule.
assert_not_contains "${VAULT}/practices/INDEX.md" 'vendor-migration' \
  "a project doc never appears in the practices index"
assert_not_contains "${VAULT}/projects/INDEX.md" '| Maturity |' \
  "and the projects index has no maturity column — nothing here promotes"

# --- a project is a directory ----------------------------------------------
# The flat doc above stays exactly where it is, and keeps being indexed: it is
# somebody's committed vault content, and an engine upgrade that stopped reading
# it would be this tool deciding to lose a document. The index built from it
# alone must also stay byte-identical to what the previous engine produced —
# same guarantee as the empty projects/ above, one layer in.
cp "${VAULT}/projects/INDEX.md" "${SANDBOX}/projects-flat-only.md"

mkdir -p "${VAULT}/projects/auth-rewrite/features"
cat > "${VAULT}/projects/auth-rewrite/_project.md" <<'EOF'
---
kind: project
status: active
started: 2026-02-01
last-reviewed: 2026-03-10
repos: ["gamma-api"]
tags: []
---

# Auth rewrite

## TL;DR

- Moving off the vendor SDK before the June cutoff [verified]

## Constraints

- The June cutoff is contractual [verified]
EOF
cat > "${VAULT}/projects/auth-rewrite/features/oidc-discovery.md" <<'EOF'
---
kind: feature
status: active
last-reviewed: 2026-03-10
repos: ["gamma-api"]
---

# OIDC discovery

## State

- Waiting on the vendor's discovery endpoint [second-hand]
EOF
cat > "${VAULT}/projects/auth-rewrite/features/token-refresh.md" <<'EOF'
---
kind: feature
status: closed
last-reviewed: 2026-02-20
outcome: done
repos: ["gamma-api"]
---

# Token refresh

## State

- Shipped; the retry loop was the fix [verified]
EOF
"${INDEX}" --vault "${VAULT}" >/dev/null 2>&1

assert_contains "${VAULT}/projects/INDEX.md" 'auth-rewrite/_project' \
  "a directory project is linked by path, not by a bare _project slug"
assert_contains "${VAULT}/projects/INDEX.md" 'Moving off the vendor SDK' \
  "and its TL;DR comes off _project.md"
assert_contains "${VAULT}/projects/INDEX.md" '## Features' \
  "features get their own section once a project has any"
assert_contains "${VAULT}/projects/INDEX.md" 'auth-rewrite/features/oidc-discovery' \
  "each feature is linked at its own path"
assert_contains "${VAULT}/projects/INDEX.md" 'Waiting on the vendor' \
  "with its ## State line, not the project's TL;DR"

# The whole point of the split: the project row says what the thing is, and the
# feature rows say where each slice stands. A closed feature carries its outcome,
# because `closed` alone says the work left the list and nothing about how.
assert_contains "${VAULT}/projects/INDEX.md" 'closed · done' \
  "a closed feature carries its outcome beside the status"

# The flat doc is still there, still a row.
assert_contains "${VAULT}/projects/INDEX.md" '\[\[vendor-migration\]\]' \
  "the flat projects/<name>.md doc keeps its bare wikilink and its row"

# A pipe inside a table cell starts the next column, so the alias separator in a
# path wikilink has to be escaped or every such row silently loses its columns.
assert_contains "${VAULT}/projects/INDEX.md" 'auth-rewrite/_project\\|auth-rewrite' \
  "and the alias pipe is escaped so the table row survives"

# A directory with features and no _project.md is a half-written project. Named,
# not skipped — dropping it would hide the features too.
mkdir -p "${VAULT}/projects/no-overview/features"
printf -- '---\nkind: feature\nstatus: active\nlast-reviewed: 2026-03-11\n---\n\n# Orphan\n\n## State\n- adrift\n' \
  > "${VAULT}/projects/no-overview/features/orphan.md"
out="$("${INDEX}" --vault "${VAULT}" 2>&1)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"no-overview"*"no _project.md"*) pass "a project directory with no _project.md is named" ;;
  *) fail "a project directory with no _project.md is named" "${out}" ;;
esac
assert_contains "${VAULT}/projects/INDEX.md" 'no-overview/features/orphan' \
  "and its features are still indexed rather than hidden with it"

# A closed feature with no outcome is the same gap a bare `- [x]` leaves on a
# follow-up: the work left the list, and nothing says how.
printf -- '---\nkind: feature\nstatus: closed\nlast-reviewed: 2026-03-11\n---\n\n# Orphan\n\n## State\n- adrift\n' \
  > "${VAULT}/projects/no-overview/features/orphan.md"
out="$("${INDEX}" --vault "${VAULT}" 2>&1)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"closed with no outcome"*) pass "a closed feature with no outcome is warned about" ;;
  *) fail "a closed feature with no outcome is warned about" "${out}" ;;
esac

# --- a .md directly inside a project directory is read by nothing -----------
# Either a misplaced feature or somebody reaching for the unsupported
# projects/<repo>/<initiative>.md shape. The file is invisible to the index and
# to project-for, and that silence is indistinguishable from an empty
# directory — so it has to be named.
mkdir -p "${VAULT}/projects/strayed/features"
printf -- '---\nkind: project\nstatus: active\nlast-reviewed: 2026-03-11\n---\n\n# Strayed\n\n## TL;DR\n- overview\n' \
  > "${VAULT}/projects/strayed/_project.md"
printf -- '---\nkind: feature\nstatus: active\nlast-reviewed: 2026-03-11\n---\n\n# Misplaced\n\n## State\n- here\n' \
  > "${VAULT}/projects/strayed/api-migration.md"
out="$("${INDEX}" --vault "${VAULT}" 2>&1)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"strayed/api-migration.md"*"not read"*)
    pass "a .md directly inside a project directory is named as unread" ;;
  *) fail "a stray .md inside a project directory is named" "${out}" ;;
esac
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"move it into features/"*) pass "and the warning says where it should go" ;;
  *) fail "the stray warning says where it should go" "${out}" ;;
esac
# _project.md is the overview, not a stray.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"strayed/_project.md"*"not read"*)
    fail "_project.md is never reported as a stray" "${out}" ;;
  *) pass "_project.md is never reported as a stray" ;;
esac
rm -rf "${VAULT}/projects/strayed"

# --- status: standing, for work that never reaches an end -------------------
# Routine upkeep recurs and never closes. Without it such a duty reads active
# forever and last-reviewed is the only field carrying information.
mkdir -p "${VAULT}/projects/upkeep/features"
printf -- '---\nkind: project\nstatus: standing\nlast-reviewed: 2026-03-11\n---\n\n# Upkeep\n\n## TL;DR\n- recurs, never done\n' \
  > "${VAULT}/projects/upkeep/_project.md"
printf -- '---\nkind: feature\nstatus: standing\nlast-reviewed: 2026-03-11\n---\n\n# Rotation\n\n## State\n- every few weeks\n' \
  > "${VAULT}/projects/upkeep/features/rotation.md"
out="$("${INDEX}" --vault "${VAULT}" 2>&1)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"unknown status: standing"*) fail "standing is a known status" "${out}" ;;
  *) pass "standing is a known status, on a project and on a feature" ;;
esac
# It never closes, so the closed-with-no-outcome check must not reach it.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *rotation*"closed with no outcome"*)
    fail "a standing feature is not asked for an outcome" "${out}" ;;
  *) pass "a standing feature is not asked for an outcome" ;;
esac
TESTS_RUN=$((TESTS_RUN + 1))
case "$(cat "${VAULT}/projects/INDEX.md")" in
  *standing*) pass "standing appears in the generated index" ;;
  *) fail "standing appears in the generated index" "$(cat "${VAULT}/projects/INDEX.md")" ;;
esac
rm -rf "${VAULT}/projects/upkeep"

# --- projects/ with documents but no templates ------------------------------
# Reachable by doing nothing unusual, and invisible because both readers key
# off frontmatter rather than layout. A wrap-up then drafts from templates that
# are not there and reads the vault as flat, entrenching the un-adopted layout.
# This fixture vault has never had _templates/, which is exactly the state.
out="$("${INDEX}" --vault "${VAULT}" 2>&1)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"_templates"*"project.md, feature.md are missing"*)
    pass "missing project templates are named while projects/ holds documents" ;;
  *) fail "missing project templates are named" "${out}" ;;
esac
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"--adopt"*) pass "and the warning names the one command that fixes it" ;;
  *) fail "the template warning names --adopt" "${out}" ;;
esac
# One template present and one absent must still report, in the singular.
mkdir -p "${VAULT}/_templates"
printf '# project template\n' > "${VAULT}/_templates/project.md"
out_one="$("${INDEX}" --vault "${VAULT}" 2>&1)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_one}" in
  *"feature.md is missing"*) pass "one missing template reports in the singular" ;;
  *) fail "one missing template reports in the singular" "${out_one}" ;;
esac
# Both present: silence, or the warning is noise on every healthy vault.
printf '# feature template\n' > "${VAULT}/_templates/feature.md"
out_both="$("${INDEX}" --vault "${VAULT}" 2>&1)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_both}" in
  *"_templates"*missing*) fail "no template warning when both are present" "${out_both}" ;;
  *) pass "no template warning when both are present" ;;
esac

rm -rf "${VAULT}/projects/no-overview" "${VAULT}/projects/auth-rewrite"
"${INDEX}" --vault "${VAULT}" >/dev/null 2>&1
TESTS_RUN=$((TESTS_RUN + 1))
if cmp -s "${SANDBOX}/projects-flat-only.md" "${VAULT}/projects/INDEX.md"; then
  pass "a flat-only projects/ regenerates to the bytes it had before features existed"
else
  fail "a flat-only projects/ regenerates to the bytes it had before features existed" \
    "$(diff "${SANDBOX}/projects-flat-only.md" "${VAULT}/projects/INDEX.md" || true)"
fi

cp "${VAULT}/projects/INDEX.md" "${SANDBOX}/projects-first.md"
"${INDEX}" --vault "${VAULT}" >/dev/null 2>&1
diff -q "${SANDBOX}/projects-first.md" "${VAULT}/projects/INDEX.md" >/dev/null 2>&1
assert_exit 0 $? "two runs produce an identical projects index"

"${INDEX}" --vault "${VAULT}" --check >/dev/null 2>&1
assert_exit 0 $? "--check passes when the projects index is current"
echo "| tampered |" >> "${VAULT}/projects/INDEX.md"
"${INDEX}" --vault "${VAULT}" --check >/dev/null 2>&1
assert_exit 1 $? "--check exits 1 when the projects index is stale"
"${INDEX}" --vault "${VAULT}" >/dev/null 2>&1

# Config resolution, and a missing vault fails with a message not a traceback.
printf 'SBW_VAULT=%s\n' "${VAULT}" > "${SANDBOX}/config"
SBW_CONFIG_FILE="${SANDBOX}/config" "${INDEX}" --check >/dev/null 2>&1
assert_exit 0 $? "resolves vault from config file"

out="$("${INDEX}" --vault "${SANDBOX}/nope" 2>&1)"
rc=$?
assert_exit 1 "${rc}" "missing vault exits 1"
TESTS_RUN=$((TESTS_RUN + 1))
if grep -qi "traceback" <<< "${out}"; then
  fail "missing vault reports cleanly" "${out}"
else
  pass "missing vault reports cleanly"
fi

finish
