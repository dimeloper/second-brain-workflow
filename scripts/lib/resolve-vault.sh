#!/usr/bin/env bash
# Print the vault path this machine resolves to, by the same path every script
# taking --vault uses: environment > config file > default.
#
#   VAULT := $(shell ./scripts/lib/resolve-vault.sh)
#
# This exists because `make` cannot read the config file. Expressing the
# fallback in make syntax instead — `$(if $(SBW_VAULT),...,$(HOME)/vaults/...)`
# — reads only the *environment variable*, so a machine configured purely
# through the config file got the built-in default from every make target while
# the scripts those targets wrap resolved correctly. Since the Makefile then
# passes the result on as `--vault`, the highest-precedence input, its wrong
# answer silently won: `make doctor` reported a confident "ok" about the
# personal vault on a machine whose config named the work one.
#
# So: one resolver, shared. Unlike the scripts, this takes no --vault flag —
# a caller who wants to override passes `make doctor VAULT=...`, which stops
# this from being consulted at all.
set -euo pipefail

# shellcheck source=scripts/lib/config.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/config.sh"
ds_config_load

printf '%s\n' "${SBW_VAULT}"
