#!/usr/bin/env bash
# Every shell snippet in the reader-facing docs must survive a copy-paste into
# a real shell. Three separate paste failures showed up in one first-time
# onboarding, all in commands the docs present as runnable:
#
#   <account>   zsh reads it as a redirection, aborts the whole command before
#               the script runs, and carries on with the next one — a silent
#               partial setup
#   $EDITOR     unset on a fresh machine, so the line expands to a bare path
#               that the shell then tries to execute
#
# Angle brackets are fine in prose and in markdown/yaml fences; they are not
# fine in anything a reader will paste into a shell, which is why this only
# looks inside shell-tagged fences.
#
# skills/**/SKILL.md are deliberately out of scope: those are agent-facing
# instructions, not a surface a human pastes from.
# shellcheck source=tests/lib.sh
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
setup_sandbox

DOCS="README.md docs/NEW-MACHINE.md docs/GUARD.md docs/AUDIT.md docs/vault-ci/README.md"

# Report every paste hazard inside shell-tagged fences of one markdown file.
scan_file() {
  awk '
    /^[ \t]*```/ {
      if (inshell) { inshell = 0; next }
      if ($0 ~ /^[ \t]*```(bash|sh|zsh|shell)[ \t]*$/) inshell = 1
      next
    }
    !inshell { next }
    /<[A-Za-z_]/ {
      printf "%s:%d: angle-bracket placeholder in a shell snippet: %s\n", FILENAME, FNR, $0
    }
    /\$EDITOR/ {
      printf "%s:%d: bare $EDITOR is unset on a fresh machine: %s\n", FILENAME, FNR, $0
    }
  ' "$1"
}

echo "doc snippets"

findings=""
for doc in ${DOCS}; do
  [ -f "${ENGINE}/${doc}" ] || { findings="${findings}${doc}: missing"$'\n'; continue; }
  findings="${findings}$(cd "${ENGINE}" && scan_file "${doc}")"
done
findings="$(printf '%s' "${findings}" | sed '/^$/d')"

TESTS_RUN=$((TESTS_RUN + 1))
if [ -z "${findings}" ]; then
  pass "every shell snippet in the reader docs is paste-safe"
else
  fail "every shell snippet in the reader docs is paste-safe" "${findings}"
fi

# Without this, the assertion above passes just as happily against a scanner
# that never reports anything.
bad="${SANDBOX}/bad.md"
cat > "${bad}" <<'FIXTURE'
Prose may say <account> freely, and so may a non-shell fence:

```markdown
---
paths:
  - "<glob>"
---
```

```bash
git clone git@github.com:<account>/thing.git
$EDITOR ~/.config/second-brain-workflow/config
```
FIXTURE

out="$(scan_file "${bad}")"

TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"angle-bracket placeholder"*) pass "flags an angle-bracket placeholder inside a bash fence" ;;
  *) fail "flags an angle-bracket placeholder inside a bash fence" "${out}" ;;
esac

TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"EDITOR is unset"*) pass "flags a bare EDITOR reference" ;;
  *) fail "flags a bare EDITOR reference" "${out}" ;;
esac

TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"<glob>"*) fail "leaves angle brackets in a non-shell fence alone" "${out}" ;;
  *"Prose may say"*) fail "leaves angle brackets in prose alone" "${out}" ;;
  *) pass "leaves angle brackets in prose and non-shell fences alone" ;;
esac

finish
