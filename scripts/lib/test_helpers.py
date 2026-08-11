#!/usr/bin/env python3
"""Find a test file calling an assertion helper nothing defines.

The harness's worst failure mode: a test file that calls an undefined helper
prints `command not found` on stderr, the assertion never runs, and the file
still reports `N passed`. A broken test becomes indistinguishable from a passing
one, which undercuts every count the suite prints — and the only thing that
caught it the first time was noticing the assertion total had not moved, which
is a side channel rather than a check.

`set -u` does not help: an undefined *function* is a command, not a variable.
Same move as the config.sh/config.py key-set parity test — one set defined in the
harness, another used by its consumers, and a check that they agree.

Usage: test_helpers.py             -> lines, or "clean". Exit 1 if any.
"""
import re, sys, pathlib

DEF = re.compile(r'^([a-z_][a-z0-9_]*)\s*\(\)\s*\{', re.M)
CALL = re.compile(r'^\s*(assert_[a-z0-9_]+|pass|fail|check)\b')

root = pathlib.Path(__file__).resolve().parent.parent.parent
lib_defs = set(DEF.findall((root / "tests" / "lib.sh").read_text(encoding="utf-8")))

bad = []
for f in sorted((root / "tests").glob("test-*.sh")):
    text = f.read_text(encoding="utf-8")
    known = lib_defs | set(DEF.findall(text))
    for i, line in enumerate(text.splitlines(), 1):
        m = CALL.match(line)
        if m and m.group(1) not in known:
            bad.append("%s:%d: calls undefined helper '%s'"
                       % (f.relative_to(root), i, m.group(1)))

print("\n".join(bad) if bad else "clean")
sys.exit(1 if bad else 0)
