#!/usr/bin/env bash
# release-check.sh: the gate that refuses to tag on a red or pending CI run.
#
# Every case here runs against a sandbox clone with a stubbed `gh` on PATH, so
# nothing contacts GitHub and no assertion depends on what the real repo's CI
# happens to be doing. The stub answers from a file the test writes, which is
# what lets "red", "pending" and "green" be three ordinary fixtures rather than
# three states someone has to arrange upstream.
#
# The refusals matter more than the success, and are tested harder: this exists
# because a release was tagged on a red run, and a gate that fails open is worse
# than no gate — it converts "nobody checked" into "something checked and said
# it was fine."
# shellcheck source=tests/lib.sh
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"
setup_sandbox

echo "release-check.sh"

BIN="${SANDBOX}/bin"
REPO="${SANDBOX}/engine"
UPSTREAM="${SANDBOX}/upstream.git"
RUNS="${SANDBOX}/runs.json"
RELEASE="${SANDBOX}/release.args"
export RUNS_FILE="${RUNS}"
export RELEASE_FILE="${RELEASE}"

mkdir -p "${BIN}"

# `gh` stands in for the whole GitHub side. `gh run list` replays whatever the
# current test wrote into RUNS_FILE; auth always succeeds unless GH_UNAUTHED is
# set. Only the two --json shapes the script actually asks for are handled, so a
# query the script starts making without a fixture fails loudly here rather than
# silently returning nothing (which would read as "no run" — a refusal, and so
# an easy way for a broken test to look like a passing one).
#
# `release create` writes its whole argv to RELEASE_FILE instead of publishing.
# That file existing is the only evidence that a Release was published, which is
# what lets "the tag was pushed but no Release followed" — the bug that left
# four releases unpublished — be an assertion rather than something noticed on
# the repo's front page a week later. GH_RELEASE_FAILS makes it exit non-zero.
cat > "${BIN}/gh" <<'STUB'
#!/usr/bin/env bash
case "$1 $2" in
  "auth status")
    [ -n "${GH_UNAUTHED:-}" ] && exit 1
    exit 0 ;;
  "repo view")
    echo "https://github.example/owner/repo"
    exit 0 ;;
  "release create")
    [ -n "${GH_RELEASE_FAILS:-}" ] && exit 1
    printf '%s\n' "$*" > "${RELEASE_FILE}"
    exit 0 ;;
esac
if [ "$1 $2" = "run list" ]; then
  field=""
  for arg in "$@"; do
    case "${arg}" in
      status|conclusion) field="${arg}" ;;
      .\[\].status)      field="status" ;;
      .\[\].conclusion)  field="conclusion" ;;
    esac
  done
  [ -f "${RUNS_FILE}" ] || exit 0
  case "${field}" in
    status)     cut -d' ' -f1 < "${RUNS_FILE}" ;;
    conclusion) cut -d' ' -f2 < "${RUNS_FILE}" ;;
    *)          sed 's/^/    /' < "${RUNS_FILE}" ;;
  esac
  exit 0
fi
exit 0
STUB
chmod +x "${BIN}/gh"

# A bare upstream plus a clone, so `git ls-remote origin HEAD` and the tag push
# are real git operations rather than more stubbing. The push in the --yes case
# has to actually land somewhere, or "it tagged" is untested.
git init -q --bare "${UPSTREAM}"
# Both HEADs set explicitly. `init.defaultBranch` is unset in the sandbox (there
# is no global git config in here by design), so the branch name a bare repo
# picks is whatever the git build defaults to — `main` on this machine, `master`
# on the runners. The script reads `git ls-remote origin HEAD`, which follows
# the *bare* repo's HEAD, so on a runner it resolved to a branch nothing was
# ever pushed to: every case after the first two refused with "cannot read
# origin's HEAD" and the suite failed in CI while passing locally.
git -C "${UPSTREAM}" symbolic-ref HEAD refs/heads/main
git clone -q "${UPSTREAM}" "${REPO}" 2>/dev/null
git -C "${REPO}" symbolic-ref HEAD refs/heads/main
git -C "${REPO}" config user.email "test@example.com"
git -C "${REPO}" config user.name "Test"
mkdir -p "${REPO}/scripts/lib"
cp "${ENGINE}/scripts/release-check.sh" "${REPO}/scripts/"
cp "${ENGINE}/scripts/lib/invocation.sh" "${REPO}/scripts/lib/"
printf '0.99.0\n' > "${REPO}/VERSION"
git -C "${REPO}" add -A
git -C "${REPO}" commit -q -m "release commit"
git -C "${REPO}" push -q -u origin main 2>/dev/null

CHECK="${REPO}/scripts/release-check.sh"
run() { PATH="${BIN}:${PATH}" "${CHECK}" "$@" 2>&1; }

green()   { printf 'completed success\n' > "${RUNS}"; }
red()     { printf 'completed failure\n' > "${RUNS}"; }
pending() { printf 'in_progress \n' > "${RUNS}"; }
norun()   { : > "${RUNS}"; }

# --- refusals before CI is consulted at all ------------------------------

GH_UNAUTHED=1 run >/dev/null 2>&1
assert_exit 2 "$?" "an unauthenticated gh is refused, not treated as no findings"

# A PATH of /usr/bin:/bin does NOT remove gh — the Ubuntu runners ship it in
# /usr/bin, so that spelling tested "gh present but unauthenticated" there while
# testing "gh absent" here, and the two produce different messages. A directory
# holding symlinks to exactly the commands the script needs, and nothing named
# gh, is absent-everywhere by construction.
NOGH="${SANDBOX}/nogh"
mkdir -p "${NOGH}"
# bash included deliberately: the shebang is `/usr/bin/env bash`, and env
# resolves bash through PATH — leave it out and the script exits 127 before it
# can refuse anything, which is a pass for the wrong reason.
for tool in bash git dirname tr sed awk cut date sleep grep; do
  ln -sf "$(command -v "${tool}")" "${NOGH}/${tool}"
done
out="$(PATH="${NOGH}" "${CHECK}" 2>&1)"
rc=$?
assert_exit 2 "${rc}" "no gh at all is refused — there is no local substitute"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"local substitute for it"*) pass "and says why a local run would not do instead" ;;
  *) fail "and says why a local run would not do instead" "${out}" ;;
esac

green
printf 'dirty\n' > "${REPO}/scratch.txt"
out="$(run)"
rc=$?
assert_exit 2 "${rc}" "a dirty tree is refused even when CI is green"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"not what you have"*) pass "and says the tag would not name what was tested" ;;
  *) fail "and says the tag would not name what was tested" "${out}" ;;
esac
rm -f "${REPO}/scratch.txt"

# An unpushed release commit is the exact false signal the practice is about:
# there IS a green run, it is just for the commit before this one.
git -C "${REPO}" commit -q --allow-empty -m "unpushed release commit"
out="$(run)"
rc=$?
assert_exit 2 "${rc}" "an unpushed HEAD is refused, however green the branch looks"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"for a different commit"*) pass "and names the reason: the run is not for this commit" ;;
  *) fail "and names the reason: the run is not for this commit" "${out}" ;;
esac
git -C "${REPO}" push -q origin main 2>/dev/null

# --- the three states of the run -----------------------------------------

norun
out="$(run)"
rc=$?
assert_exit 1 "${rc}" "no run for this commit is a refusal, not a pass"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"not distinguishable later"*) pass "and says why silence cannot count as green" ;;
  *) fail "and says why silence cannot count as green" "${out}" ;;
esac

pending
out="$(run)"
rc=$?
assert_exit 1 "${rc}" "a pending run is a refusal — the practice's whole subject"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"--wait"*) pass "and offers the wait rather than leaving you to poll by hand" ;;
  *) fail "and offers the wait rather than leaving you to poll by hand" "${out}" ;;
esac

red
out="$(run)"
rc=$?
assert_exit 1 "${rc}" "a red run is refused"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"refusing to tag"*) pass "and says plainly that it will not tag" ;;
  *) fail "and says plainly that it will not tag" "${out}" ;;
esac

# The flake finding, encoded: a re-run is offered as a command to read and type,
# never performed. A gate that retried until green could not refuse.
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"gh run rerun"*) pass "a possible flake gets a re-run command, printed not run" ;;
  *) fail "a possible flake gets a re-run command, printed not run" "${out}" ;;
esac
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"read the log first"*) pass "and is framed as a judgement, not a retry loop" ;;
  *) fail "and is framed as a judgement, not a retry loop" "${out}" ;;
esac

# Nothing above may have tagged anything. This is the assertion that would catch
# a gate that refuses loudly and acts anyway.
TESTS_RUN=$((TESTS_RUN + 1))
if [ -z "$(git -C "${REPO}" tag -l)" ]; then
  pass "no refusal path ever created a tag"
else
  fail "no refusal path ever created a tag" "$(git -C "${REPO}" tag -l)"
fi

# --- green -----------------------------------------------------------------

green
out="$(run)"
rc=$?
assert_exit 0 "${rc}" "a green run passes the gate"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"Nothing tagged"*) pass "but checking is not tagging — YES=1 is a separate act" ;;
  *) fail "but checking is not tagging — YES=1 is a separate act" "${out}" ;;
esac
TESTS_RUN=$((TESTS_RUN + 1))
if [ -z "$(git -C "${REPO}" tag -l)" ]; then
  pass "a plain check leaves the repo untagged"
else
  fail "a plain check leaves the repo untagged" "$(git -C "${REPO}" tag -l)"
fi

# --- the Release, resolved before the tag ------------------------------------
#
# A missing changelog section has to refuse *before* tagging. Afterwards the tag
# is an artefact adopters can already have fetched, and the only thing left to
# discover is a Release whose link 404s.

out="$(run --yes)"
rc=$?
assert_exit 2 "${rc}" "no changelog at all is refused"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"describe itself"*) pass "and says the release would otherwise have to describe itself" ;;
  *) fail "and says the release would otherwise have to describe itself" "${out}" ;;
esac

# The likelier version of that mistake: a changelog that exists, with the bump
# made and the section not yet written.
printf '## [0.98.0] - 2026-01-01\n\n### Added\n- An older thing.\n' > "${REPO}/CHANGELOG.md"
git -C "${REPO}" add -A
git -C "${REPO}" commit -q -m "docs: a changelog with no section for this version"
git -C "${REPO}" push -q origin main 2>/dev/null

out="$(run --yes)"
rc=$?
assert_exit 2 "${rc}" "a changelog with no section for this version is refused"
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"nothing to publish until it is written"*) pass "and says the Release links to that section, not a copy of it" ;;
  *) fail "and says the Release links to that section, not a copy of it" "${out}" ;;
esac
TESTS_RUN=$((TESTS_RUN + 1))
if [ -z "$(git -C "${REPO}" tag -l)" ]; then
  pass "and refuses before tagging, while retyping the command is the only cost"
else
  fail "and refuses before tagging, while retyping the command is the only cost" \
    "$(git -C "${REPO}" tag -l)"
fi

printf '## [0.99.0] - 2026-01-01\n\n### Added\n- A thing.\n' > "${REPO}/CHANGELOG.md"
git -C "${REPO}" add -A
git -C "${REPO}" commit -q -m "docs: cut v0.99.0 — the summary line"
git -C "${REPO}" push -q origin main 2>/dev/null

out="$(run --yes)"
rc=$?
assert_exit 0 "${rc}" "--yes on a green run tags and pushes"
TESTS_RUN=$((TESTS_RUN + 1))
case "$(git -C "${REPO}" tag -l)" in
  *v0.99.0*) pass "the tag is created from VERSION" ;;
  *) fail "the tag is created from VERSION" "$(git -C "${REPO}" tag -l)" ;;
esac
TESTS_RUN=$((TESTS_RUN + 1))
if git -C "${UPSTREAM}" rev-parse -q --verify "refs/tags/v0.99.0" >/dev/null 2>&1; then
  pass "and pushed — a local-only tag would gate nothing"
else
  fail "and pushed — a local-only tag would gate nothing" "not on the remote"
fi

# The assertion the missing Releases needed. A tag with no Release is invisible
# on the repo's front page, which goes on reporting the last release anyone
# remembered to publish by hand.
TESTS_RUN=$((TESTS_RUN + 1))
if [ -f "${RELEASE}" ]; then
  pass "and the Release is published in the same act, not left to be remembered"
else
  fail "and the Release is published in the same act, not left to be remembered" \
    "no gh release create"
fi
args="$(cat "${RELEASE}" 2>/dev/null || true)"
TESTS_RUN=$((TESTS_RUN + 1))
case "${args}" in
  *"CHANGELOG.md#0990---2026-01-01"*) pass "the notes link to that version's section by its own anchor" ;;
  *) fail "the notes link to that version's section by its own anchor" "${args}" ;;
esac
TESTS_RUN=$((TESTS_RUN + 1))
case "${args}" in
  *"--title v0.99.0 — the summary line"*) pass "and the title comes from the cut commit, not a hand-typed one" ;;
  *) fail "and the title comes from the cut commit, not a hand-typed one" "${args}" ;;
esac
# --verify-tag, so gh cannot create a tag that skipped this gate entirely.
TESTS_RUN=$((TESTS_RUN + 1))
case "${args}" in
  *"--verify-tag"*) pass "against the tag just pushed, never one gh would create itself" ;;
  *) fail "against the tag just pushed, never one gh would create itself" "${args}" ;;
esac

# Cutting the same release twice is a mistake worth catching, and the tag now
# exists to catch it with.
out="$(run --yes)"
rc=$?
assert_exit 2 "${rc}" "an already-existing tag is refused rather than re-pushed"

# --- the Release failing after the tag is pushed -----------------------------
#
# The tag is gone from this script's control by then, so the only useful thing
# left is to say so plainly and hand over the exact command — a silent success
# here is how the front page went stale for four releases.
printf '0.99.1\n' > "${REPO}/VERSION"
printf '## [0.99.1] - 2026-01-02\n\n### Fixed\n- Another thing.\n' > "${REPO}/CHANGELOG.md"
git -C "${REPO}" add -A
git -C "${REPO}" commit -q -m "docs: cut v0.99.1 — the patch"
git -C "${REPO}" push -q origin main 2>/dev/null
rm -f "${RELEASE}"

out="$(GH_RELEASE_FAILS=1 run --yes)"
rc=$?
assert_exit 1 "${rc}" "a Release that fails to publish is not reported as a clean cut"
TESTS_RUN=$((TESTS_RUN + 1))
if git -C "${UPSTREAM}" rev-parse -q --verify "refs/tags/v0.99.1" >/dev/null 2>&1; then
  pass "the tag stays pushed — it is not this script's to take back"
else
  fail "the tag stays pushed — it is not this script's to take back" "not on the remote"
fi
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"The tag is pushed; the Release is not"*) pass "and the state it left behind is named exactly" ;;
  *) fail "and the state it left behind is named exactly" "${out}" ;;
esac
TESTS_RUN=$((TESTS_RUN + 1))
case "${out}" in
  *"gh release create v0.99.1"*) pass "with the command to finish it by hand" ;;
  *) fail "with the command to finish it by hand" "${out}" ;;
esac

finish
