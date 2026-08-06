.PHONY: help lint require-shellcheck lint-shell lint-python test vault-index \
        vault-index-check sync-skills uninstall explain guard doctor audit verify-claude check

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

SHELL_SOURCES := scripts/sync-rules.sh scripts/sync-skills.sh scripts/init-vault.sh \
                 scripts/guard-vault-commit.sh scripts/doctor.sh scripts/verify-claude-load.sh \
                 scripts/lib/config.sh scripts/lib/vault-identity.sh \
                 scripts/lib/resolve-vault.sh scripts/uninstall.sh \
                 tests/lib.sh $(wildcard tests/test-*.sh)

help:
	@echo "make lint                shellcheck every shell script (needs shellcheck)"
	@echo "make test                run the test suite against fixtures — no extra tools"
	@echo "make vault-index         regenerate <vault>/practices/INDEX.md"
	@echo "make vault-index-check   fail if the index is stale"
	@echo "make sync-skills         install skills into every dir in SKILLS_DIRS"
	@echo "make uninstall           preview removing them; make uninstall YES=1 to act"
	@echo "make explain             show how each rule resolves per target"
	@echo "make guard               run the vault commit guard against VAULT"
	@echo "make doctor              report gaps: commit-guard hook, skill parity, submodule drift"
	@echo "make audit               lineage + stale follow-ups + always-on rule token budget"
	@echo "make verify-claude       prove Claude Code loads rendered rules (2 model calls)"
	@echo "make check               lint + test + non-mutating checks"
	@echo "                         (skips shellcheck if it isn't installed)"
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
lint: require-shellcheck lint-shell lint-python

require-shellcheck:
	@command -v shellcheck >/dev/null || { \
	  echo "shellcheck not installed — brew install shellcheck"; \
	  echo "  (or run 'make test', which needs no extra tools)"; exit 1; }

lint-shell:
	@if command -v shellcheck >/dev/null; then \
	  shellcheck -x $(SHELL_SOURCES) && echo "shellcheck clean"; \
	else \
	  echo "shellcheck: skipped — install shellcheck to enable (brew install shellcheck)"; \
	fi

lint-python:
	@python3 -m py_compile scripts/render.py scripts/build-vault-index.py scripts/check-lineage.py \
	  scripts/check-followups.py scripts/rule-budget.py scripts/lib/config.py scripts/lib/frontmatter.py \
	  && echo "python syntax OK"

# Tests run entirely against fixtures in $$TMPDIR. They must never touch a real
# repo, vault, ~/.cursor or ~/.claude — SBW_CONFIG_FILE is redirected too, so a
# developer's own config cannot change the result.
test:
	@fail=0; for t in tests/test-*.sh; do "$$t" || fail=1; done; exit $$fail

explain:
	@./scripts/render.py --explain

guard:
	@./scripts/guard-vault-commit.sh --vault "$(VAULT)"

# Not part of `make check`: needs a real vault, same reasoning as
# vault-index-check below — CI has none.
doctor:
	@./scripts/doctor.sh --vault "$(VAULT)"

# Not part of `make check`: needs a real vault AND a real rules directory —
# an even stronger dependency than doctor/vault-index-check, so the same
# reasoning applies twice over. Both scripts' own tests (which run against
# fixtures, like everything else in `make test`) are what CI verifies.
# Runs all three regardless of whether an earlier one fails, so one finding
# doesn't hide another.
audit:
	@fail=0; \
	./scripts/check-lineage.py --vault "$(VAULT)" || fail=1; \
	echo; \
	./scripts/check-followups.py --vault "$(VAULT)" || fail=1; \
	echo; \
	./scripts/rule-budget.py || fail=1; \
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

# Preview by default; --yes is the script's own gate, so `make uninstall` can
# never remove anything on its own.
uninstall:
	@./scripts/uninstall.sh $(if $(YES),--yes,)

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
