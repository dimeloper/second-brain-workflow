"""Shared classification of a vault path, for the Python consumers.

    from lib.vault_state import classify
    state, message = classify(vault, origin)

The Python mirror of lib/vault-state.sh — same four states, same wording, so a
reader who sees a path described one way by `make doctor` sees it described
identically by `make audit` or `make vault-index`. tests/test-vault-state.sh
asserts the two implementations produce byte-identical messages, since two
copies of a message is exactly the kind of thing that drifts.

Before this existed the Python scripts reported "No practices/ directory in
<path>" for a path that was not a vault at all, and for one that did not exist
they said "Vault not found" without saying which knob produced the path.

States: missing | not-a-repo | no-vault-json | ready
"""

INIT_HINT = "./scripts/init-vault.sh --path {vault} --id VAULT_ID"


def classify(vault, origin=""):
    """Return (state, message) for a vault path. Stats only; writes nothing."""
    from_clause = f" — it came from {origin}" if origin else ""

    if not vault.exists():
        return (
            "missing",
            f"no such path: {vault}{from_clause}. Either the path is wrong or "
            f"the vault was never created ({INIT_HINT.format(vault=vault)}).",
        )

    if not vault.is_dir():
        return "missing", f"not a directory: {vault}{from_clause}."

    if not (vault / ".git").is_dir():
        return (
            "not-a-repo",
            f"{vault} exists but is not a git repo — setup is unfinished, not "
            f"misconfigured: {INIT_HINT.format(vault=vault)} --adopt",
        )

    if not (vault / "vault.json").is_file():
        return (
            "no-vault-json",
            f"{vault} is a git repo with no vault.json — nothing identifies it "
            f"as a vault, so the identity check has nothing to compare "
            f"against: {INIT_HINT.format(vault=vault)} --adopt",
        )

    return "ready", f"{vault} is a git repo with a vault.json"
