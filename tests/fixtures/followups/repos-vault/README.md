# repo-attribution fixtures

A second vault, kept apart from `../vault` so the window/staleness tests there
keep asserting exact counts without every new attribution fixture shifting them.
Everything here exists to exercise one attribution signal each — see
`tests/test-check-followups.sh`.
