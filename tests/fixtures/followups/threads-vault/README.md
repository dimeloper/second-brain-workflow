# threads-vault

Fixture for the carried-forward threading in `lib/followup_threads.py`. Its own
vault, not shared with `vault/` or `repos-vault/`, because every assertion here
is a *count* — how many threads, how many items — and adding one item to a
shared vault silently rewrites every count in every other test that reads it.
That has already cost two rounds of updates on `repos-vault`.

Every item is tagged `#repo/…` except where being untagged is the point, so
nothing here depends on inference and a change to attribution cannot quietly
change what this file is testing.

The shape being tested, note by note:

- **2026-01-02** — three tasks that will be restated later, two `Smoke check:`
  items sharing a leading clause **in the same note** (they must stay apart:
  two tasks written side by side are two tasks), and a key to rotate.
- **2026-01-04** — the restatements, reworded. The barcode item's version moves
  and its branch appears; the `Device retest:` body is rewritten wholesale and
  survives only on its leading clause; the console item is restated *shorter*,
  which is what Jaccard alone gets wrong and containment gets right. Plus two
  decoys: the same barcode sentence under a different repo, and an untagged
  copy of the rotate item.
- **2026-01-06** — the barcode item once more, and the rotate item finally
  ticked off, closing a thread whose older note still shows it unchecked.

Expected, as of 2026-01-06 with `--recent 3`: **11 items in 7 threads**, one
thread ticked off in a newer note, and 12 items with `--no-threads`.
