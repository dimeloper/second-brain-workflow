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

# --- the Quickstart pins a release ------------------------------------------
# Dropping these lines makes the default path a clone of `main`, and the two
# guard tiers then enforce different code: the pre-commit hook runs whatever
# `main` is while the CI backstop checks out the tag its ENGINE_REF pins. CI
# exists to catch what `--no-verify` skips, so a divergence there is not
# cosmetic. `upgrade.sh` already warns about a vault workflow that pins
# nothing, for exactly this reason — the README must not recommend the thing
# the tooling warns about.
TESTS_RUN=$((TESTS_RUN + 1))
# shellcheck disable=SC2016  # matching the literal text `$latest` in the
# README, which must not expand here — that is the whole assertion.
case "${QS}" in
  *"git tag --sort=-v:refname"*'[ -z "$latest" ] || git checkout "$latest"'*)
    pass "the Quickstart pins the newest release rather than tracking main" ;;
  *) fail "the Quickstart pins the newest release rather than tracking main" "${QS}" ;;
esac

# A tag checkout after --recurse-submodules leaves vendor/obsidian-skills at
# whatever main pinned, so the pin above is only half-applied without this.
TESTS_RUN=$((TESTS_RUN + 1))
case "${QS}" in
  *"git submodule update --init --recursive"*)
    pass "and re-pins the submodule, which a tag checkout does not move" ;;
  *) fail "and re-pins the submodule, which a tag checkout does not move" "${QS}" ;;
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
# CHANGELOG.md is in this list for the cross-file link the restructure created
# outside the docs tree — the one link the checker was extended for that would
# otherwise sit outside it. It can only be here because inline code spans are
# skipped; see the code-span assertions below.
out="$(python3 "${ENGINE}/scripts/lib/doc_links.py" \
  "${ENGINE}/README.md" "${ENGINE}/docs/REFERENCE.md" "${ENGINE}/docs/NEW-MACHINE.md" \
  "${ENGINE}/docs/GUARD.md" "${ENGINE}/docs/AUDIT.md" "${ENGINE}/CHANGELOG.md" 2>&1 || true)"
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

# --- and the same across files ----------------------------------------------
# Cutting the README down to a pitch moved its deep links into REFERENCE.md, so
# the whole "why this doesn't rot" section — the part carrying the trust
# argument — now points at another file. Same-document checking cannot see
# that, and a check that cannot determine something falls through to green.
# Renaming a heading in the target must turn this red.
mkdir -p "${SANDBOX}/xfile/sub"
printf '# Target\n\n## Real Section\n' > "${SANDBOX}/xfile/sub/target.md"
printf '# Source\n\nSee [that](sub/target.md#real-section) and [this](sub/target.md#renamed-away).\n' \
  > "${SANDBOX}/xfile/source.md"
out="$(python3 "${ENGINE}/scripts/lib/doc_links.py" "${SANDBOX}/xfile/source.md" 2>&1 || true)"

TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"link to sub/target.md#renamed-away"*)
    pass "the anchor checker finds a broken cross-file link" ;;
  *) fail "the anchor checker finds a broken cross-file link" "${out}" ;;
esac

# Without this the check above passes just as happily against a checker that
# reports every cross-file link, which would make it useless rather than wrong.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"#real-section"*)
    fail "and leaves a cross-file link that does resolve alone" "${out}" ;;
  *) pass "and leaves a cross-file link that does resolve alone" ;;
esac

# An external link is somebody else's uptime, and a path that does not resolve
# is a different defect this deliberately does not claim to catch. Both must
# stay silent, or the checker cannot be run over docs that link outward.
printf '# S\n\n[a](https://example.com/x#frag) [b](nope/missing.md#frag)\n' \
  > "${SANDBOX}/xfile/quiet.md"
out="$(python3 "${ENGINE}/scripts/lib/doc_links.py" "${SANDBOX}/xfile/quiet.md" 2>&1 || true)"
TESTS_RUN=$((TESTS_RUN + 1))
if [ "${out}" = "clean" ]; then
  pass "an external link and an unresolvable path are both left alone"
else
  fail "an external link and an unresolvable path are both left alone" "${out}"
fi

# --- a link inside backticks is a sample, not a link ------------------------
# CHANGELOG.md cites the original defect verbatim in the entry recording its
# fix. Without this, prose correctly describing a fixed bug reports as the bug,
# and the file cannot be checked at all — which would leave the one cross-file
# link outside the docs tree unwatched, the exact gap this checker exists for.
spans="${SANDBOX}/xfile/spans.md"
# shellcheck disable=SC2016  # the backticks are markdown code spans, which is
# the whole fixture — they must reach the file unexpanded.
printf '# Heading\n\nCited: `[r](#long-gone)`; real: [y](#also-gone); text-is-code: [`x`](#heading).\n' \
  > "${spans}"
out="$(python3 "${ENGINE}/scripts/lib/doc_links.py" "${spans}" 2>&1 || true)"

TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"#long-gone"*) fail "a link inside a code span is not treated as a link" "${out}" ;;
  *) pass "a link inside a code span is not treated as a link" ;;
esac

# Stripping spans must not blind it to real links on the same line, which is
# how an exclusion turns into a hole.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"link to #also-gone"*)
    pass "and a real broken link beside one is still caught" ;;
  *) fail "and a real broken link beside one is still caught" "${out}" ;;
esac

# Only the bracketed text is removed, so a link whose label is code still
# resolves — `[`make doctor`](GUARD.md#make-doctor)` appears throughout the docs.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"#heading"*) fail "and a link whose label is code still resolves" "${out}" ;;
  *) pass "and a link whose label is code still resolves" ;;
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
