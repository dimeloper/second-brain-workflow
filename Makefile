.PHONY: help lint require-shellcheck lint-shell lint-python test vault-index adopt \
        vault-index-check sync-skills fetch-skills skills-for practices-for project-for project-candidates uninstall upgrade explain render repos-check guard doctor audit \
        init \
        verify-claude check release-check

# Resolved by the same code the scripts use, never re-derived in make syntax:
# make cannot read the config file, so a fallback written here would ignore it
# and then win anyway, since these targets pass the result as --vault. Only
# computed when VAULT isn't already set, so `make doctor VAULT=/path` and
# `VAULT=/path make doctor` both still override it. Write $(HOME), not ~, on
# the command line — make does no tilde expansion, and neither does zsh in a
# variable argument.
ENGINE_DIR := $(dir $(lastword $(MAKEFILE_LIST)))
ifeq ($(origin VAULT),undefined)
  VAULT := $(shell $(ENGINE_DIR)scripts/lib/resolve-vault.sh)
endif

SHELL_SOURCES := scripts/sync-rules.sh scripts/sync-skills.sh scripts/init-vault.sh scripts/init.sh \
                 scripts/guard-vault-commit.sh scripts/doctor.sh scripts/verify-claude-load.sh \
                 scripts/lib/config.sh scripts/lib/vault-identity.sh \
                 scripts/lib/registry.sh scripts/upgrade.sh scripts/release-check.sh \
                 scripts/repos-check.sh scripts/with-vault-lock.sh \
                 scripts/lib/resolve-vault.sh scripts/uninstall.sh \
                 scripts/fetch-skill-sources.sh scripts/lib/skill-links.sh \
                 tests/lib.sh $(wildcard tests/test-*.sh)

help:
	@echo "make lint                shellcheck every shell script (needs shellcheck)"
	@echo "make test                run the test suite against fixtures — no extra tools"
	@echo "make vault-index         regenerate <vault>/practices/INDEX.md"
	@echo "make vault-index-check   fail if the index is stale"
	@echo "make sync-skills         install skills into every dir in SKILLS_DIRS"
	@echo "make fetch-skills        preview fetching declared skill sources; YES=1 to act"
	@echo "make skills-for REPO=... which skills apply to a repo, adopted and candidate"
	@echo "make practices-for REPO=... vault notes that govern a repo but were never applied"
	@echo "make project-for REPO=... the vault's context for this repo's initiative"
	@echo "make project-candidates  which long-running initiatives the daily notes evidence"
	@echo "make uninstall           preview removing them; make uninstall YES=1 to act"
	@echo "make upgrade             preview switching to the newest release; YES=1 to act"
	@echo "make adopt               preview turning on the opt-in features; YES=1 to act"
	@echo "make explain             show how each rule resolves per target"
	@echo "make render REPO=...     render rules into one repo (also registers it)"
	@echo "                         LOCAL=1 also excludes them from that repo's git"
	@echo "                         SHARED=1 moves a LOCAL repo back; without either,"
	@echo "                         a re-render keeps the mode the registry recorded"
	@echo "make repos-check         which onboarded repos are behind; reports, never renders"
	@echo "make guard               run the vault commit guard against VAULT"
	@echo "make init              explain this engine, detect the machine, preview a config"
	@echo "                         (make init YES=1 VAULT_ID=... writes it, then runs doctor)"
	@echo "make doctor              report gaps: commit-guard hook, skill parity, submodule drift"
	@echo "make audit               lineage + stale follow-ups + rule budget + note markdown"
	@echo "make verify-claude       prove Claude Code loads rendered rules (3 model calls)"
	@echo "make check               lint + test + non-mutating checks"
	@echo "                         (skips shellcheck if it isn't installed)"
	@echo "make release-check       refuse to cut on a red or pending CI run; WAIT=1 to"
	@echo "                         block, YES=1 to tag, push, and publish the Release"
	@echo ""
	@echo "Render into a repo:  ./scripts/render.py <repo> [--targets ...]"
	@echo "VAULT=$(VAULT)"

# shellcheck is the toolchain's only external dependency, and the two entry
# points want opposite things from it. `make lint` is asked for on purpose, so a
# missing shellcheck is an error there — skipping silently would report success
# for work never done. `make check` is the "is this machine healthy" command, so
# it degrades: a visible skip line, then everything else still runs. Before
# this, a machine without shellcheck got `make: *** [lint] Error 1` and not one
# of the tests executed. CI installs shellcheck, so coverage there is unchanged.
#
# Split three ways so neither entry point duplicates the other's commands, and
# so lint-python — which needs nothing but python3 — runs in both cases.
# Overridable so the degradation path can be tested by naming a binary that
# isn't there, rather than by surgery on PATH: on Linux shellcheck lives in
# /usr/bin, so removing the directory that holds it also removes make, python3,
# sed and everything else — which is why the first version of that test passed
# on macOS and failed on a Linux runner.
SHELLCHECK ?= shellcheck

lint: require-shellcheck lint-shell lint-python

require-shellcheck:
	@command -v $(SHELLCHECK) >/dev/null || { \
	  echo "shellcheck not installed — brew install shellcheck"; \
	  echo "  (or run 'make test', which needs no extra tools)"; exit 1; }

lint-shell:
	@if command -v $(SHELLCHECK) >/dev/null; then \
	  $(SHELLCHECK) -x $(SHELL_SOURCES) && echo "shellcheck clean"; \
	else \
	  echo "shellcheck: skipped — install shellcheck to enable (brew install shellcheck)"; \
	fi

lint-python:
	@python3 -m py_compile scripts/render.py scripts/build-vault-index.py scripts/check-lineage.py \
	  scripts/append-daily-block.py \
	  scripts/check-followups.py scripts/check-rules.py scripts/rule-budget.py scripts/lib/config.py \
	  scripts/lib/frontmatter.py scripts/lib/registry.py scripts/lib/skill_manifest.py \
	  scripts/lib/repo_match.py scripts/lib/promotion.py scripts/practices-for.py \
	  scripts/lib/followups.py scripts/lib/followup_threads.py scripts/lib/landed.py \
	  scripts/project-candidates.py scripts/project-for.py scripts/lib/projects.py \
  scripts/check-markdown.py scripts/lib/markdown.py \
	  && echo "python syntax OK"

# Tests run entirely against fixtures in $$TMPDIR. They must never touch a real
# repo, vault, ~/.cursor or ~/.claude — SBW_CONFIG_FILE is redirected too, so a
# developer's own config cannot change the result.
test:
	@fail=0; for t in tests/test-*.sh; do "$$t" || fail=1; done; exit $$fail

explain:
	@./scripts/render.py --explain

# Named by v0.20.0's Major entry, which `make upgrade` prints verbatim, so a
# reader upgrading past it is handed this command as the required action. It did
# not exist until then: every other reference was ./scripts/render.py <repo>.
# LOCAL and SHARED both pass through; neither is required for a re-render, which
# keeps whichever mode the registry recorded for that repo. Passing both is
# refused by render.py's parser rather than resolved here — "local and shared" is
# not a state, and a Makefile silently preferring one would be exactly the guess
# the recorded mode exists to remove.
render:
	@if [ -z "$(REPO)" ]; then echo "usage: make render REPO=/path/to/repo" >&2; exit 2; fi
	@./scripts/render.py "$(REPO)" $(if $(LOCAL),--local,) $(if $(SHARED),--shared,)

# The same question `make upgrade` asks in step 7, asked at the other moment it
# matters: after editing a rule, when every rendered copy on the machine has
# just gone stale and nothing says so. Reports; never renders. Not part of
# `make check`: it reads this machine's registry and walks its disk, so CI has
# nothing for it to answer about.
repos-check:
	@./scripts/repos-check.sh $(if $(REGISTRY_ONLY),--registry-only,)

guard:
	@./scripts/guard-vault-commit.sh --vault "$(VAULT)"

# Not part of `make check`: needs a real vault, same reasoning as
# vault-index-check below — CI has none.
init:
	@./scripts/init.sh $(if $(YES),--yes,) \
	  $(if $(VAULT_ID),--vault-id $(VAULT_ID),) $(if $(VAULT),--vault $(VAULT),)

doctor:
	@./scripts/doctor.sh --vault "$(VAULT)"

# Not part of `make check`: needs a real vault AND a real rules directory —
# an even stronger dependency than doctor/vault-index-check, so the same
# reasoning applies twice over. Both scripts' own tests (which run against
# fixtures, like everything else in `make test`) are what CI verifies.
# Runs all four regardless of whether an earlier one fails, so one finding
# doesn't hide another.
audit:
	@fail=0; \
	./scripts/check-lineage.py --vault "$(VAULT)" || fail=1; \
	echo; \
	./scripts/check-followups.py --vault "$(VAULT)" || fail=1; \
	echo; \
	./scripts/check-rules.py || fail=1; \
	echo; \
	./scripts/rule-budget.py || fail=1; \
	echo; \
	./scripts/check-markdown.py --vault "$(VAULT)" || fail=1; \
	exit $$fail

# Not part of `make check`: costs model calls and needs network. Run it once per
# machine, and after any change to how rules are rendered.
verify-claude:
	@./scripts/verify-claude-load.sh

vault-index:
	@./scripts/build-vault-index.py --vault "$(VAULT)"

vault-index-check:
	@./scripts/build-vault-index.py --vault "$(VAULT)" --check

sync-skills:
	@./scripts/sync-skills.sh

# The network step, kept out of sync-skills so `make check` never needs a network
# or credentials. Preview by default, same shape as uninstall and upgrade.
fetch-skills:
	@./scripts/fetch-skill-sources.sh $(if $(YES),--yes,)

# Which adopted skills are scoped to a repo, and which declared candidates are
# worth considering there. Read-only, and the one question the agent host cannot
# answer for itself: it routes to what is installed and knows nothing of what
# is not.
skills-for:
	@if [ -z "$(REPO)" ]; then echo "usage: make skills-for REPO=/path/to/repo" >&2; exit 2; fi
	@python3 ./scripts/lib/skill_manifest.py relevant --repo "$(REPO)"

# Which vault notes govern a repo and have never been applied there, and which of
# those one deliberate application would promote. Read-only, and deliberately not
# an applier: the vault's bar counts deliberate re-application, so a batch would
# manufacture the evidence it exists to measure.
practices-for:
	@if [ -z "$(REPO)" ]; then echo "usage: make practices-for REPO=/path/to/repo" >&2; exit 2; fi
	@./scripts/practices-for.py --repo "$(REPO)" --vault "$(VAULT)"

# The read path for projects/, and practices-for's sibling: what the vault
# already knows about this repo's initiative, so a session does not re-derive
# six weeks of daily notes. Read-only, and a repo with no project doc is a clean
# "nothing here" at exit 0 — most repos have none and never will, so a non-zero
# exit would make the ordinary answer look like a failure.
project-for:
	@if [ -z "$(REPO)" ]; then echo "usage: make project-for REPO=/path/to/repo" >&2; exit 2; fi
	@./scripts/project-for.py --repo "$(REPO)" --vault "$(VAULT)"

# Which long-running initiatives the daily notes already evidence, and which of
# those have no project doc. Read-only, and deliberately not a writer: drafting
# one is update-second-brain's backfill mode, which shows every draft and writes
# only what is approved. Not part of `make audit` — a missing project doc is a
# thing you might want, not drift.
project-candidates:
	@./scripts/project-candidates.py --vault "$(VAULT)" \
	  $(if $(NOTES),--notes $(NOTES),) $(if $(ALL),--all,)

# The gate the release practice was missing. Deliberately NOT part of `make
# check`: this one reads the network and asks about a specific commit, and it is
# run once per cut rather than on every edit. Preview unless YES=1, the same
# shape as uninstall and upgrade — so the tag is something you opt into, and the
# wait between pushing main and pushing the tag is a command rather than a thing
# to remember not to chain with &&. YES=1 publishes the GitHub Release in the
# same act: leaving that to be remembered separately lost four of them.
adopt:
	@./scripts/adopt.sh $(if $(YES),--yes,) $(if $(VAULT),--vault $(VAULT),)

release-check:
	@./scripts/release-check.sh $(if $(YES),--yes,) $(if $(WAIT),--wait,) \
	  $(if $(RELEASE_VERSION),--version $(RELEASE_VERSION),)

# Preview by default; --yes is the script's own gate, so `make uninstall` can
# never remove anything on its own.
uninstall:
	@./scripts/uninstall.sh $(if $(YES),--yes,)

# Same shape as uninstall: preview unless YES=1. Takes VAULT like every other
# vault-touching target, and passes REF/NO_FETCH through for the offline case.
upgrade:
	@./scripts/upgrade.sh --vault "$(VAULT)" $(if $(YES),--yes,) \
	  $(if $(REF),--ref $(REF),) $(if $(NO_FETCH),--no-fetch,)

# `render.py --explain` also enforces the scoping invariant: a glob-scoped rule
# must never render into an always-loaded file. Per-repo rule drift is checked
# in that repo's CI via `render.py <repo> --check`.
#
# vault-index-check is deliberately not here: CI has no vault, and a stale index
# is a vault-repo concern. Run `make vault-index-check` locally.
#
# lint-shell rather than lint: without shellcheck this reports the skip and
# carries on, so the exit status comes from the tests. With it, a shellcheck
# finding still fails the run exactly as before.
check: lint-shell lint-python test
	@./scripts/render.py --explain >/dev/null && echo "rule scoping OK"
