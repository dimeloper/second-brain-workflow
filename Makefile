.PHONY: help lint test vault-index vault-index-check sync-skills explain guard doctor audit verify-claude check

VAULT ?= $(if $(SBW_VAULT),$(SBW_VAULT),$(HOME)/vaults/second-brain)
SHELL_SOURCES := scripts/sync-rules.sh scripts/sync-skills.sh scripts/init-vault.sh \
                 scripts/guard-vault-commit.sh scripts/doctor.sh scripts/verify-claude-load.sh \
                 scripts/lib/config.sh scripts/lib/vault-identity.sh tests/lib.sh $(wildcard tests/test-*.sh)

help:
	@echo "make lint                shellcheck every shell script"
	@echo "make test                run the test suite against fixtures"
	@echo "make vault-index         regenerate <vault>/practices/INDEX.md"
	@echo "make vault-index-check   fail if the index is stale"
	@echo "make sync-skills         install skills into every dir in SKILLS_DIRS"
	@echo "make explain             show how each rule resolves per target"
	@echo "make guard               run the vault commit guard against VAULT"
	@echo "make doctor              report gaps: missing commit-guard hook, etc."
	@echo "make audit               lineage: unpromoted/orphaned/stale/thin-evidence rules"
	@echo "make verify-claude       prove Claude Code loads rendered rules (2 model calls)"
	@echo "make check               lint + test + non-mutating checks"
	@echo ""
	@echo "Render into a repo:  ./scripts/render.py <repo> [--targets ...]"
	@echo "VAULT=$(VAULT)"

lint:
	@command -v shellcheck >/dev/null || { \
	  echo "shellcheck not installed — brew install shellcheck"; exit 1; }
	@shellcheck -x $(SHELL_SOURCES) && echo "shellcheck clean"
	@python3 -m py_compile scripts/render.py scripts/build-vault-index.py scripts/check-lineage.py \
	  scripts/lib/config.py scripts/lib/frontmatter.py \
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
# reasoning applies twice over. check-lineage.py's own tests (which run
# against fixtures, like everything else in `make test`) are what CI verifies.
audit:
	@./scripts/check-lineage.py --vault "$(VAULT)"

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

# `render.py --explain` also enforces the scoping invariant: a glob-scoped rule
# must never render into an always-loaded file. Per-repo rule drift is checked
# in that repo's CI via `render.py <repo> --check`.
#
# vault-index-check is deliberately not here: CI has no vault, and a stale index
# is a vault-repo concern. Run `make vault-index-check` locally.
check: lint test
	@./scripts/render.py --explain >/dev/null && echo "rule scoping OK"
