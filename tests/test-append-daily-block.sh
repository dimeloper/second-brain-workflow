#!/usr/bin/env bash
# append-daily-block.py: the compare-and-swap write path into a daily note.
#
# The defect it exists for: two sessions wrap up at once, both read the note,
# both write the whole file back, and the second write silently drops the
# first one's block. Every test below is either "the merge adds without
# removing" or "a write from a stale read is refused".
# shellcheck source=tests/lib.sh
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
setup_sandbox

APPEND="${ENGINE}/scripts/append-daily-block.py"
VAULT="${SANDBOX}/vault"
DAY="2026-08-24"
NOTE="${VAULT}/${DAY}.md"
mkdir -p "${VAULT}"

stamp() { "${APPEND}" --vault "${VAULT}" --date "${DAY}" --stamp --quiet; }
append() { "${APPEND}" --vault "${VAULT}" --date "${DAY}" "$@"; }

echo "append-daily-block.py"

# --- --stamp ----------------------------------------------------------------
assert_str "absent" "$(stamp)" "--stamp --quiet reports an absent note as 'absent'"

out="$("${APPEND}" --vault "${VAULT}" --date "${DAY}" --stamp)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"date  ${DAY}"*"${NOTE}"*) pass "--stamp names the date and the note it resolved" ;;
  *) fail "--stamp names the date and the note it resolved" "${out}" ;;
esac

# --- --block without --expect is the bug, not a shortcut --------------------
# A caller that skips the hash is doing the read-modify-write this script was
# written to replace, so it is refused at the argument level rather than
# defaulted to "whatever is on disk now".
cat > "${SANDBOX}/echo.md" <<'EOF'
## Built (echo-city-hotel: OG card)
- Shipped `dede9b0`; og:image is absolute now.

## Follow-ups
- [ ] Scrape the Facebook debugger #repo/echo-city-hotel

## Drift / gaps
- A 200 on the asset is not proof the share URL is crawlable.
EOF
append --block "${SANDBOX}/echo.md" >/dev/null 2>&1
assert_exit 2 $? "--block without --expect is rejected"

# --- the first block of the day creates the note ----------------------------
append --expect absent --block "${SANDBOX}/echo.md" >/dev/null 2>&1
assert_exit 0 $? "first block writes the note"
assert_file "${NOTE}" "and the note now exists"
assert_contains "${NOTE}" "# ${DAY}" "titled with the date"
assert_contains "${NOTE}" "Shipped .dede9b0" "carrying the block"

# --- a stale write is refused, not merged and not forced --------------------
cat > "${SANDBOX}/ingestion.md" <<'EOF'
## Built (housemaster-ingestion: Places cost)
- PR #41 caps a run at 150 requests.

## Follow-ups
- [ ] Verify the 00:00 UTC POI run #repo/housemaster-ingestion

## Practices followed
- [[count-the-billed-unit-not-the-loop-iteration]] — requests, not sublocations.
EOF
append --expect absent --block "${SANDBOX}/ingestion.md" >/dev/null 2>&1
assert_exit 3 $? "a write from a stale read is refused"
assert_not_contains "${NOTE}" "PR #41" "and nothing was written"
assert_contains "${NOTE}" "Shipped .dede9b0" "and the note that was there is untouched"

out="$(append --expect absent --block "${SANDBOX}/ingestion.md" 2>&1)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"changed since you read it"*"Re-read the note"*)
    pass "and says what to do about it, not just that it failed" ;;
  *) fail "and says what to do about it, not just that it failed" "${out}" ;;
esac

# --- re-stamping recovers, and both sessions' work survives -----------------
append --expect "$(stamp)" --block "${SANDBOX}/ingestion.md" >/dev/null 2>&1
assert_exit 0 $? "re-stamping and re-running the same block succeeds"
assert_contains "${NOTE}" "Shipped .dede9b0" "the first session's block is still there"
assert_contains "${NOTE}" "PR #41" "and the second session's block landed"

# --- one header per section, per day ----------------------------------------
# The rule keep-one-header-per-section-in-daily-notes states, enforced by the
# merge rather than by asking the caller to remember it. Two Built blocks are
# allowed (distinct work streams); one Follow-ups is not negotiable.
n_followups="$(grep -c '^## Follow-ups$' "${NOTE}")"
assert_str "1" "${n_followups}" "two blocks produce one ## Follow-ups, not two"
n_built="$(grep -c '^## Built (' "${NOTE}")"
assert_str "2" "${n_built}" "but two labelled ## Built blocks, one per work stream"
assert_contains "${NOTE}" "Verify the 00:00 UTC POI run" "the second block's follow-up merged in"

# --- canonical order --------------------------------------------------------
# `## Practices followed` arrived in the second block only, so it had to be
# inserted rather than appended — between Follow-ups and Drift / gaps, not at
# the end of the file where the caller happened to write it.
order="$(grep -n '^## ' "${NOTE}" | sed 's/:.*//' | tr '\n' ' ')"
followups_line="$(grep -n '^## Follow-ups$' "${NOTE}" | cut -d: -f1)"
practices_line="$(grep -n '^## Practices followed$' "${NOTE}" | cut -d: -f1)"
drift_line="$(grep -n '^## Drift / gaps$' "${NOTE}" | cut -d: -f1)"
TESTS_RUN=$((TESTS_RUN + 1))
if [ "${followups_line}" -lt "${practices_line}" ] && [ "${practices_line}" -lt "${drift_line}" ]; then
  pass "a new section is inserted in canonical order, not appended"
else
  fail "a new section is inserted in canonical order, not appended" "headers at: ${order}"
fi

# --- concurrency: two writers, same stamp, at the same moment ---------------
# The hash check alone leaves a window between reading and writing. This is the
# test that would catch losing the lock: without it both processes can pass the
# check and the second still clobbers.
RACE_DAY="2026-08-26"
RACE_NOTE="${VAULT}/${RACE_DAY}.md"
printf '# %s\n\n## Built\n- base line\n' "${RACE_DAY}" > "${RACE_NOTE}"
race_stamp="$("${APPEND}" --vault "${VAULT}" --date "${RACE_DAY}" --stamp --quiet)"
printf '## Built\n- from A\n' > "${SANDBOX}/a.md"
printf '## Built\n- from B\n' > "${SANDBOX}/b.md"
( "${APPEND}" --vault "${VAULT}" --date "${RACE_DAY}" --expect "${race_stamp}" \
    --block "${SANDBOX}/a.md" >/dev/null 2>&1; echo $? > "${SANDBOX}/rc-a" ) &
( "${APPEND}" --vault "${VAULT}" --date "${RACE_DAY}" --expect "${race_stamp}" \
    --block "${SANDBOX}/b.md" >/dev/null 2>&1; echo $? > "${SANDBOX}/rc-b" ) &
wait
rc_a="$(cat "${SANDBOX}/rc-a")"
rc_b="$(cat "${SANDBOX}/rc-b")"
TESTS_RUN=$((TESTS_RUN + 1))
if { [ "${rc_a}" = "0" ] && [ "${rc_b}" = "3" ]; } || { [ "${rc_a}" = "3" ] && [ "${rc_b}" = "0" ]; }; then
  pass "two simultaneous writers: exactly one wins, the other is refused"
else
  fail "two simultaneous writers: exactly one wins, the other is refused" "a=${rc_a} b=${rc_b}"
fi
assert_contains "${RACE_NOTE}" "base line" "and the note that was there survived the race"
n_race="$(grep -c '^- from ' "${RACE_NOTE}")"
assert_str "1" "${n_race}" "with exactly one winner's line in it"

# --- the merge never drops a line -------------------------------------------
# Including from a section this script has never heard of. A daily note is
# edited by hand in Obsidian too, and an unknown header is not a licence to
# reformat someone's note out from under them.
HAND_DAY="2026-08-27"
HAND_NOTE="${VAULT}/${HAND_DAY}.md"
cat > "${HAND_NOTE}" <<'EOF'
# 2026-08-27

## Built
- existing work

## Reading
- a hand-written section this tool does not know
EOF
printf '## Built\n- appended work\n' > "${SANDBOX}/hand.md"
"${APPEND}" --vault "${VAULT}" --date "${HAND_DAY}" \
  --expect "$("${APPEND}" --vault "${VAULT}" --date "${HAND_DAY}" --stamp --quiet)" \
  --block "${SANDBOX}/hand.md" >/dev/null 2>&1
assert_exit 0 $? "appends alongside a hand-written section"
assert_contains "${HAND_NOTE}" "a hand-written section" "which survives untouched"
assert_contains "${HAND_NOTE}" "existing work" "next to the content that was already there"
assert_contains "${HAND_NOTE}" "appended work" "and the new bullet"

# --- template placeholders --------------------------------------------------
# `- ` under a heading is the template's empty bullet, not content. Appending
# replaces it — and the lost-line check has to know that, or replacing one
# reads as losing one and the write is refused.
TPL_DAY="2026-08-28"
TPL_NOTE="${VAULT}/${TPL_DAY}.md"
cat > "${TPL_NOTE}" <<'EOF'
# 2026-08-28

## Built
-

<!-- Add another "## Built (label)" block per distinct work stream if needed. -->

## Follow-ups
- [ ]
EOF
printf '## Built\n- real work\n' > "${SANDBOX}/tpl.md"
"${APPEND}" --vault "${VAULT}" --date "${TPL_DAY}" \
  --expect "$("${APPEND}" --vault "${VAULT}" --date "${TPL_DAY}" --stamp --quiet)" \
  --block "${SANDBOX}/tpl.md" >/dev/null 2>&1
assert_exit 0 $? "appending to a placeholder section is not a lost line"
assert_contains "${TPL_NOTE}" "real work" "the real bullet landed"
TESTS_RUN=$((TESTS_RUN + 1))
if grep -qE '^- *$' "${TPL_NOTE}"; then
  fail "and the empty placeholder bullet is gone" "$(cat "${TPL_NOTE}")"
else
  pass "and the empty placeholder bullet is gone"
fi
assert_contains "${TPL_NOTE}" "Add another" "while the convention comment stays"
# The comment explains the section, so new bullets belong above it — otherwise
# the explanation drifts into the middle of the day's work.
bullet_line="$(grep -n 'real work' "${TPL_NOTE}" | cut -d: -f1)"
comment_line="$(grep -n 'Add another' "${TPL_NOTE}" | cut -d: -f1)"
TESTS_RUN=$((TESTS_RUN + 1))
if [ "${bullet_line}" -lt "${comment_line}" ]; then
  pass "with the bullet above the comment, not after it"
else
  fail "with the bullet above the comment, not after it" "bullet ${bullet_line}, comment ${comment_line}"
fi

# --- the atomic write leaves nothing behind ---------------------------------
# The temp file has to be a sibling of the note (os.replace is only atomic
# within a filesystem), which puts it inside the vault — a path the commit
# guard's allowlist would refuse if one were ever left there.
TESTS_RUN=$((TESTS_RUN + 1))
if [ -n "$(find "${VAULT}" -name '.*.tmp' -print -quit)" ]; then
  fail "no temp files left in the vault" "$(find "${VAULT}" -name '.*.tmp')"
else
  pass "no temp files left in the vault"
fi

# --- --link: the midnight crossing ------------------------------------------
# A session past midnight belongs to two notes, each pointing at the other. The
# line lives above the first header, which a block cannot carry — so without a
# flag for it the convention needs a hand-edit, i.e. the whole-file write, on
# the one night it is most likely to happen.
LINK_DAY="2026-08-29"
LINK_NOTE="${VAULT}/${LINK_DAY}.md"
printf '# %s\n\n## Built\n- late work\n' "${LINK_DAY}" > "${LINK_NOTE}"
link_stamp() { "${APPEND}" --vault "${VAULT}" --date "${LINK_DAY}" --stamp --quiet; }

"${APPEND}" --vault "${VAULT}" --date "${LINK_DAY}" --expect "$(link_stamp)" \
  --link 2026-08-28 >/dev/null 2>&1
assert_exit 0 $? "--link alone (no block) is a valid write"
assert_contains "${LINK_NOTE}" "Continues \[\[2026-08-28\]\]" "an earlier date reads as Continues"
head_line="$(sed -n '3p' "${LINK_NOTE}")"
assert_str "Continues [[2026-08-28]]." "${head_line}" "and sits under the title, above the first header"
assert_contains "${LINK_NOTE}" "late work" "leaving the sections alone"

"${APPEND}" --vault "${VAULT}" --date "${LINK_DAY}" --expect "$(link_stamp)" \
  --link 2026-08-28 >/dev/null 2>&1
n_links="$(grep -c "2026-08-28" "${LINK_NOTE}")"
assert_str "1" "${n_links}" "re-running does not add the link twice"

"${APPEND}" --vault "${VAULT}" --date "${LINK_DAY}" --expect "$(link_stamp)" \
  --link 2026-08-30 >/dev/null 2>&1
assert_contains "${LINK_NOTE}" "Continued in \[\[2026-08-30\]\]" "a later date reads as Continued in"

"${APPEND}" --vault "${VAULT}" --date "${LINK_DAY}" --link 2026-08-28 >/dev/null 2>&1
assert_exit 2 $? "--link without --expect is refused, like --block"

# --- malformed blocks -------------------------------------------------------
printf 'a loose line\n\n## Built\n- work\n' > "${SANDBOX}/loose.md"
append --expect "$(stamp)" --block "${SANDBOX}/loose.md" >/dev/null 2>&1
assert_exit 4 $? "a block with content above its first header is refused"

printf '## Musings\n- not a daily-note section\n' > "${SANDBOX}/unknown.md"
append --expect "$(stamp)" --block "${SANDBOX}/unknown.md" >/dev/null 2>&1
assert_exit 4 $? "a block with an unknown section header is refused"

printf 'no headers at all\n' > "${SANDBOX}/headerless.md"
append --expect "$(stamp)" --block "${SANDBOX}/headerless.md" >/dev/null 2>&1
assert_exit 4 $? "a block with no header at all is refused"

# --- --dry-run writes nothing ----------------------------------------------
before="$(stamp)"
printf '## Built\n- dry run only\n' > "${SANDBOX}/dry.md"
out="$(append --expect "${before}" --block "${SANDBOX}/dry.md" --dry-run)"
assert_str "${before}" "$(stamp)" "--dry-run leaves the note byte-identical"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"dry run only"*) pass "and prints what it would have written" ;;
  *) fail "and prints what it would have written" "${out}" ;;
esac

# --- the date comes off the clock -------------------------------------------
# Not from the caller's context, which is the one thing that is reliably a day
# out on a session that started yesterday. --date exists for tests and for a
# deliberate correction; omitting it must mean today.
TODAY="$(date +%F)"
printf '## Built\n- todays work\n' > "${SANDBOX}/today.md"
"${APPEND}" --vault "${VAULT}" --expect absent --block "${SANDBOX}/today.md" >/dev/null 2>&1
assert_file "${VAULT}/${TODAY}.md" "with no --date, the note is today's, off the clock"

"${APPEND}" --vault "${VAULT}" --date "24-08-2026" --stamp >/dev/null 2>&1
assert_exit 2 $? "a --date that isn't YYYY-MM-DD is rejected"

# --- a vault that isn't there ----------------------------------------------
"${APPEND}" --vault "${SANDBOX}/no-such-vault" --stamp >/dev/null 2>&1
assert_exit 1 $? "a missing vault is an error, not an empty stamp"

# --- --close: ticking an item, with the reason ------------------------------
# The write side of the outcome convention. A bare `- [x]` is an incomplete
# write — a month later it cannot say whether the work was done or abandoned —
# so the outcome is part of the flag rather than something a caller remembers.
CDAY="2026-08-26"
CNOTE="${VAULT}/${CDAY}.md"
cstamp() { "${APPEND}" --vault "${VAULT}" --date "${CDAY}" --stamp --quiet; }
close() { "${APPEND}" --vault "${VAULT}" --date "${CDAY}" "$@"; }

seed_closable() {
  cat > "${CNOTE}" <<'EOF'
# 2026-08-26

## Follow-ups
- [ ] Merge the barcode PR and ship a build #repo/acme-app
- [ ] Merge the docs PR #repo/acme-app
- [ ] Rotate the CRM key #repo/acme-backend
- [ ] Rewrite the importer in Rust — nobody has measured the CSV path,
      and it may already be fast enough. #repo/globex-web
EOF
}

seed_closable
lines_before="$(wc -l < "${CNOTE}")"
close --expect "$(cstamp)" \
  --close 'done :: barcode PR' \
  --close 'handed-off/ops-team :: Rotate the CRM key' \
  --close 'dropped :: Rewrite the importer :: the CSV path was fast enough' >/dev/null 2>&1
assert_exit 0 $? "several items close against one hash"
assert_contains "${CNOTE}" '\- \[x\] Merge the barcode PR and ship a build #repo/acme-app #outcome/done' \
  "the tick keeps the item's own text and its #repo/ tag, and appends the outcome"
assert_contains "${CNOTE}" '#outcome/handed-off #owner/ops-team' \
  "handed-off records the owner beside the outcome"
assert_contains "${CNOTE}" '#outcome/dropped — the CSV path was fast enough' \
  "the reason is written while it is still known"
assert_contains "${CNOTE}" '\- \[ \] Merge the docs PR' \
  "an item nobody closed is left alone"
assert_str "${lines_before}" "$(wc -l < "${CNOTE}")" \
  "closing changes no line count — it substitutes, it never adds"

# A wrapped item is one item: the checkbox is on its first line and the outcome
# belongs at the end of its last, or the tags land in the middle of a sentence.
assert_contains "${CNOTE}" '\- \[x\] Rewrite the importer in Rust' \
  "a wrapped item is ticked on its first line"
assert_contains "${CNOTE}" 'fast enough\. #repo/globex-web #outcome/dropped' \
  "and tagged at the end of its last, not mid-sentence"

# --- --close refuses to guess ------------------------------------------------
# The wrong item ticked reads exactly like the right one, and the item that was
# actually finished stays on the list looking undone. So ambiguity is an error.
seed_closable
h="$(cstamp)"
out="$(close --expect "${h}" --close 'done :: Merge the' 2>&1)"
assert_exit 6 $? "a match hitting two items is refused"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"Merge the barcode PR"*"Merge the docs PR"*) pass "and prints both candidates" ;;
  *) fail "and prints both candidates" "${out}" ;;
esac
assert_str "${h}" "$(cstamp)" "and writes nothing"

out="$(close --expect "$(cstamp)" --close 'done :: no such item' 2>&1)"
assert_exit 6 $? "a match hitting nothing is refused"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"Open in this note"*"Merge the docs PR"*) pass "and lists what is open, so the typo is visible" ;;
  *) fail "and lists what is open, so the typo is visible" "${out}" ;;
esac

close --expect "$(cstamp)" --close 'done :: docs PR' --close 'dropped :: docs PR' >/dev/null 2>&1
assert_exit 6 $? "two specs matching the same item are refused, not applied twice"

close --vault "${VAULT}" --date "2026-12-31" --expect absent --close 'done :: anything' >/dev/null 2>&1
assert_exit 6 $? "--close on a note that does not exist is an error, not a created note"

# --- the outcome is not optional, and not free-form -------------------------
close --expect "$(cstamp)" --close 'finished :: docs PR' >/dev/null 2>&1
assert_exit 2 $? "an outcome outside the four is a usage error"
close --expect "$(cstamp)" --close 'docs PR' >/dev/null 2>&1
assert_exit 2 $? "a --close with no outcome field is a usage error"
close --expect "$(cstamp)" --close 'done/bob :: docs PR' >/dev/null 2>&1
assert_exit 2 $? "#owner/ on an outcome that cannot have one is a usage error"
close --close 'done :: docs PR' >/dev/null 2>&1
assert_exit 2 $? "--close without --expect is the read-modify-write, and is refused"

# handed-off with nobody named is legal — the reader reports it as an item
# nobody is watching, which is a finding — but it is said out loud on the way in.
err="$(close --expect "$(cstamp)" --dry-run --close 'handed-off :: docs PR' 2>&1 >/dev/null)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${err}" in
  *"no #owner/"*) pass "handed-off with no owner writes, but warns" ;;
  *) fail "handed-off with no owner writes, but warns" "${err}" ;;
esac

# --- WHY is the rest of the string, separators and all ----------------------
# The reason field was the one place that could not contain the delimiter, found
# writing the changelog entry for --close itself: its reason quoted the flag's
# own syntax and the spec was refused as four fields.
seed_closable
close --expect "$(cstamp)" \
  --close 'done :: Merge the docs PR :: shipped as --close OUTCOME[/OWNER] :: MATCH [:: WHY]' >/dev/null 2>&1
assert_exit 0 $? "a WHY containing the separator is accepted, not refused as extra fields"
assert_contains "${CNOTE}" 'MATCH \[:: WHY\]' \
  "and the reason is written through verbatim, separators intact"

# The outcome and the match are still fields, so a spec with neither is refused.
close --expect "$(cstamp)" --close 'just some text' >/dev/null 2>&1
assert_exit 2 $? "a --close with no separator at all is still a usage error"

# --- --close is compare-and-swap too ----------------------------------------
seed_closable
close --expect deadbeef --close 'done :: docs PR' >/dev/null 2>&1
assert_exit 3 $? "a close from a stale read is refused like any other write"

before="$(cstamp)"
close --expect "${before}" --dry-run --close 'done :: docs PR' >/dev/null 2>&1
assert_str "${before}" "$(cstamp)" "--dry-run closes nothing"

# --- a block and a close ride one hash --------------------------------------
# The point of the flag: ticking six items one at a time means six stamps, and
# the read-modify-write this script exists to replace returns by the back door.
printf '## Follow-ups\n- [ ] An item this very block added\n' > "${SANDBOX}/newitem.md"
close --expect "$(cstamp)" --block "${SANDBOX}/newitem.md" \
  --close 'superseded :: Merge the docs PR :: folded into the barcode PR' \
  --close 'done :: this very block added' >/dev/null 2>&1
assert_exit 0 $? "a block and two closes write together, against one hash"
assert_contains "${CNOTE}" '#outcome/superseded — folded into the barcode PR' \
  "the existing item closed"
assert_contains "${CNOTE}" '\- \[x\] An item this very block added #outcome/done' \
  "and an item the block itself added closes in the same call"

# --- the reader agrees with the writer --------------------------------------
# One parser, two sides. If they disagree about what an item is, an item ticked
# here reads as open there — which is the whole failure this convention closes.
seed_closable
close --expect "$(cstamp)" \
  --close 'done :: barcode PR' \
  --close 'handed-off/ops-team :: Rotate the CRM key' >/dev/null 2>&1
# A vault of its own: the sandbox above has newer notes from earlier tests, and
# --recent reads the four most recent, which would drop this one out of the
# window and pass the assertions below on an empty report.
RVAULT="${SANDBOX}/reader-vault"
mkdir -p "${RVAULT}"
cp "${CNOTE}" "${RVAULT}/"
out="$(SBW_VAULT="${RVAULT}" "${ENGINE}/scripts/check-followups.py" --recent --no-landed 2>&1)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"barcode PR"*) fail "an item closed #outcome/done leaves the open list" "${out}" ;;
  *) pass "an item closed #outcome/done leaves the open list" ;;
esac
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"handed off → ops-team"*) pass "and a handed-off one is reported with its owner" ;;
  *) fail "and a handed-off one is reported with its owner" "${out}" ;;
esac

finish
