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

DOCS="README.md docs/REFERENCE.md docs/NEW-MACHINE.md docs/GUARD.md docs/AUDIT.md docs/vault-ci/README.md"

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

# --- the Quickstart offers both vault cases ---------------------------------
# `--adopt` is the correct path for "new machine, vault already exists" — the
# common second-machine case — and it used to be mentioned once, mid-paragraph,
# in GUARD.md's scaffolding prose. The Quickstart, which is what a second
# machine actually follows, said nothing about existing vaults, so following it
# verbatim created a duplicate vault pointing at the existing one's remote.
QS="$(awk '/^## Quickstart/{f=1} f{print} f && /^## /&&!/^## Quickstart/{exit}' "${ENGINE}/README.md")"

TESTS_RUN=$((TESTS_RUN + 1))
case "${QS}" in
  *"--adopt"*) pass "the Quickstart shows --adopt, not only creation" ;;
  *) fail "the Quickstart shows --adopt, not only creation" "no --adopt in the Quickstart" ;;
esac

TESTS_RUN=$((TESTS_RUN + 1))
case "${QS}" in
  *"git clone \"git@github.com:YOUR_ACCOUNT"*)
    pass "and shows cloning the existing vault before adopting it" ;;
  *) fail "and shows cloning the existing vault before adopting it" "${QS}" ;;
esac

# Both branches, not just the adopt command sitting in the same block.
TESTS_RUN=$((TESTS_RUN + 1))
case "${QS}" in
  *"A new vault"*"already exists on a remote"*)
    pass "and labels the two cases as a choice between them" ;;
  *) fail "and labels the two cases as a choice between them" "${QS}" ;;
esac

# --- the placeholder cannot be left alone -----------------------------------
# `YOUR_ACCOUNT` was visibly a placeholder and got substituted; `vault_id=
# personal` looked like a working default and got kept. Readers replace what
# looks unfinished and keep what looks finished, so the value has to look
# unfinished — same convention as YOUR_ACCOUNT, and refused by the script.
TESTS_RUN=$((TESTS_RUN + 1))
case "${QS}" in
  *"vault_id=VAULT_ID"*) pass "the Quickstart's vault_id is a placeholder, not a default" ;;
  *) fail "the Quickstart's vault_id is a placeholder, not a default" "${QS}" ;;
esac

TESTS_RUN=$((TESTS_RUN + 1))
# shellcheck disable=SC2016  # matching the literal text ${vault_id} in the
# README, which must not expand here — that is the whole assertion.
case "${QS}" in
  *'vault_path=~/vaults/${vault_id}-brain'*)
    pass "and vault_path is derived from it, so the two cannot disagree" ;;
  *) fail "and vault_path is derived from it, so the two cannot disagree" "${QS}" ;;
esac

# --- a heading that states a count over a list of another length -------------
# "Three rules worth knowing:" over five bullets. Prose and list drift because
# one grows and the other is a sentence nobody re-reads — four instances across
# two files by the time this was written, including a heading that said "Three
# times now" above four entries in a list *about* wrong counts. Proofreading is
# not the fix; a claim about a list being checkable is.
out="$(python3 "${ENGINE}/scripts/lib/stated_counts.py" \
  "${ENGINE}/README.md" "${ENGINE}/docs/REFERENCE.md" "${ENGINE}/docs/NEW-MACHINE.md" \
  "${ENGINE}/docs/GUARD.md" "${ENGINE}/docs/AUDIT.md" "${ENGINE}/CHANGELOG.md" 2>&1 || true)"
TESTS_RUN=$((TESTS_RUN + 1))
if [ "${out}" = "clean" ]; then
  pass "no heading states a count its list does not have"
else
  fail "no heading states a count its list does not have" "${out}"
fi

# ...and the checker reports something, so the assertion above cannot pass on a
# scanner that never finds anything.
bad_counts="${SANDBOX}/bad-counts.md"
printf 'Three things to know:\n\n- one\n- two\n' > "${bad_counts}"
out="$(python3 "${ENGINE}/scripts/lib/stated_counts.py" "${bad_counts}" 2>&1 || true)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"claims 3, list has 2"*) pass "the stated-count checker finds a real mismatch" ;;
  *) fail "the stated-count checker finds a real mismatch" "${out}" ;;
esac

# --- an anchor link that resolves to no heading -----------------------------
# `[rules/](#the-rules-live-somewhere-else)` pointed at a heading that does not
# exist, in the paragraph explaining why the engine ships no rules of its own. A
# link that silently does nothing is the same class as a heading that states a
# count its list does not have.
out="$(python3 "${ENGINE}/scripts/lib/doc_links.py" \
  "${ENGINE}/README.md" "${ENGINE}/docs/REFERENCE.md" "${ENGINE}/docs/NEW-MACHINE.md" \
  "${ENGINE}/docs/GUARD.md" "${ENGINE}/docs/AUDIT.md" 2>&1 || true)"
TESTS_RUN=$((TESTS_RUN + 1))
if [ "${out}" = "clean" ]; then
  pass "every in-document anchor link resolves to a heading"
else
  fail "every in-document anchor link resolves to a heading" "${out}"
fi
bad_link="${SANDBOX}/bad-link.md"
printf '# Real heading\n\nSee [this](#no-such-heading).\n' > "${bad_link}"
out="$(python3 "${ENGINE}/scripts/lib/doc_links.py" "${bad_link}" 2>&1 || true)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"link to #no-such-heading"*) pass "the anchor checker finds a broken link" ;;
  *) fail "the anchor checker finds a broken link" "${out}" ;;
esac

# --- a command a Major changelog entry tells the reader to run --------------
# upgrade.sh prints ### Major sections verbatim, so a command named there is
# handed to every reader upgrading past that release. v0.20.0's entry named
# `make render`, which did not exist.
out="$(python3 "${ENGINE}/scripts/lib/major_commands.py" 2>&1 || true)"
TESTS_RUN=$((TESTS_RUN + 1))
if [ "${out}" = "clean" ]; then
  pass "every command a Major entry names exists"
else
  fail "every command a Major entry names exists" "${out}"
fi

finish
