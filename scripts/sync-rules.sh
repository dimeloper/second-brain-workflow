#!/usr/bin/env bash
# Thin wrapper around scripts/render.py, kept because skills and muscle memory
# refer to this path. All rendering, provenance and pruning logic lives in
# render.py so there is exactly one implementation.
#
# Usage:
#   ./sync-rules.sh <target-repo> [--targets cursor,claude-code,agents]
#   ./sync-rules.sh --check   <target-repo>
#   ./sync-rules.sh --dry-run <target-repo>
set -euo pipefail
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/render.py" "$@"
