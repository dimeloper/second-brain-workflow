#!/usr/bin/env bash
# check-markdown.py: vault notes that will not render as written, and the
# lib/markdown detector behind both it and the index.
#
# Fixtures only — a real vault would make the finding count depend on whoever
# ran it, and this asserts on exact counts.
# shellcheck source=tests/lib.sh
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
setup_sandbox

CM="${ENGINE}/scripts/check-markdown.py"

echo "check-markdown.py"

# --- fixture vault ----------------------------------------------------------
V="${SANDBOX}/vault"
mkdir -p "${V}/practices/backend" "${V}/projects/proj/features"
git -C "${V}" init -q
printf '{"id":"fixture"}\n' > "${V}/vault.json"

note() {  # note <path> <body-file-content-follows-on-stdin>
  mkdir -p "$(dirname "$1")"
  cat > "$1"
}

# A clean practice note: one-line spans only.
note "${V}/practices/backend/clean.md" <<'EOF'
---
domain: backend
maturity: idea
last-reviewed: 2026-08-01
---

# clean

**Rule:** keep `group: staging-<ns>` and `cancel-in-progress: false` whole.
EOF

# The defect, in a project overview.
note "${V}/projects/proj/_project.md" <<'EOF'
---
kind: project
status: active
last-reviewed: 2026-08-01
---

# proj

## TL;DR

Deploys are serialized (`group:
staging-<ns>`, `cancel-in-progress: false`).
EOF

# The defect again, in a feature file, so both readers are covered.
note "${V}/projects/proj/features/slice.md" <<'EOF'
---
kind: feature
status: active
last-reviewed: 2026-08-01
---

# slice

## State

Moved to `Authorization: Bearer
${TOKEN}` and left it there.
EOF

out="$("${CM}" --vault "${V}" 2>&1)"
assert_exit 1 $? "a wrapped span fails the gate"

TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"Code spans that wrap a line break: 4"*)
    pass "counts both halves of each wrapped span, in both file kinds" ;;
  *) fail "counts both halves of each wrapped span" "${out}" ;;
esac
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"projects/proj/_project.md"*"projects/proj/features/slice.md"*)
    pass "groups findings by file, overview and feature alike" ;;
  *) fail "groups findings by file" "${out}" ;;
esac
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *clean.md*) fail "a note with only one-line spans is not reported" "${out}" ;;
  *) pass "a note with only one-line spans is not reported" ;;
esac
# The reason has to travel with the finding: "code span wraps" alone does not
# tell the reader that the indent is what renders.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"only one leading space is"*"stripped"*)
    pass "states why it renders wrong, not just that it does" ;;
  *) fail "states why it renders wrong" "${out}" ;;
esac

# --- an odd backtick inside a fence is content, not a defect -----------------
rm "${V}/projects/proj/_project.md" "${V}/projects/proj/features/slice.md"
rmdir "${V}/projects/proj/features" "${V}/projects/proj"
note "${V}/practices/backend/fenced.md" <<'EOF'
---
domain: backend
maturity: idea
last-reviewed: 2026-08-01
---

# fenced

**Rule:** fences hold odd backticks.

```bash
echo `date`
```

~~~
a ``` inside a tilde fence stays content
~~~
EOF
out_fenced="$("${CM}" --vault "${V}" 2>&1)"
assert_exit 0 $? "an odd backtick inside a fenced block is content, not a finding"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out_fenced}" in
  *"No wrapped code spans"*) pass "and the clean run says so plainly" ;;
  *) fail "the clean run says so plainly" "${out_fenced}" ;;
esac

# --- daily notes are out of scope, on purpose --------------------------------
# Every note written before this check existed is full of prose nobody is going
# to re-wrap. Same rule as the #outcome/ tags: check what is being written.
cat > "${V}/2026-08-01.md" <<'EOF'
# 2026-08-01

## Built
- Ran (`group:
  staging-<ns>`) by hand.
EOF
"${CM}" --vault "${V}" >/dev/null 2>&1
assert_exit 0 $? "a wrapped span in a daily note is not a finding"

# --- INDEX.md is generated, so it is never a finding -------------------------
note "${V}/practices/INDEX.md" <<'EOF'
# Index

Generated (`group:
  x`).
EOF
"${CM}" --vault "${V}" >/dev/null 2>&1
assert_exit 0 $? "a generated INDEX.md is skipped"
rm "${V}/practices/INDEX.md"

# --- the index reports the same defect, as a warning -------------------------
# Index for the finding, audit for the gate: build-vault-index.py must name it,
# and must NOT start failing for it — its problems are advisory by design.
mkdir -p "${V}/projects/proj2"
note "${V}/projects/proj2/_project.md" <<'EOF'
---
kind: project
status: active
last-reviewed: 2026-08-01
---

# proj2

## TL;DR

A span (`group:
staging-<ns>`) that wraps.
EOF
idx_out="$("${ENGINE}/scripts/build-vault-index.py" --vault "${V}" 2>&1)"
idx_rc=$?
TESTS_RUN=$((TESTS_RUN + 1))
if [ "${idx_rc}" -eq 0 ]; then
  pass "the index still exits 0 — the finding is advisory there, not a gate"
else
  fail "the index still exits 0 for a wrapped span" "rc=${idx_rc}: ${idx_out}"
fi
TESTS_RUN=$((TESTS_RUN + 1))
case "${idx_out}" in
  *"code span wraps"*) pass "and names it as a warning with its line number" ;;
  *) fail "the index names the wrapped span" "${idx_out}" ;;
esac
# The gate must see the very same file the index just warned about, or the two
# halves of this feature disagree about what a defect is.
"${CM}" --vault "${V}" >/dev/null 2>&1
assert_exit 1 $? "and the gate fails on the same file the index warned about"

# --- a missing vault is an error, not a silent pass --------------------------
"${CM}" --vault "${SANDBOX}/no-such-vault" >/dev/null 2>&1
assert_exit 1 $? "a missing vault is an error"

# --- a vault with neither directory is clean, not a crash --------------------
BARE="${SANDBOX}/bare-vault"
mkdir -p "${BARE}"
git -C "${BARE}" init -q
printf '{"id":"bare"}\n' > "${BARE}/vault.json"
"${CM}" --vault "${BARE}" >/dev/null 2>&1
assert_exit 0 $? "a vault with no practices/ or projects/ is clean"

# --- it never writes ---------------------------------------------------------
before="$(find "${V}" -type f -not -path '*/.git/*' | sort | xargs shasum | shasum)"
"${CM}" --vault "${V}" >/dev/null 2>&1
after="$(find "${V}" -type f -not -path '*/.git/*' | sort | xargs shasum | shasum)"
TESTS_RUN=$((TESTS_RUN + 1))
if [ "${before}" = "${after}" ]; then
  pass "reports without touching the vault"
else
  fail "reports without touching the vault" "something changed"
fi

finish
