Fixture vault for `#due/` handling in check-followups.py.

Its own vault rather than items added to `repos-vault`, so the due buckets can
be asserted on exact counts without every other assertion in the suite moving
when one is added here.

Read with `--as-of 2026-01-06`, which is why 01-04 is overdue, 01-06 is due
today and 01-09 is neither.
