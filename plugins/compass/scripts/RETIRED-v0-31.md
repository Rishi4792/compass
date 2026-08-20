# Retired in v0.31, and why

These four existed to prove that a number on a LEGACY build's page was RIGHT. Review-1 round 4
established that this cannot be done: for a build whose data was never written down in a structured
form there is no true value to compare against, so every "independent reader" is another heuristic —
wrong in both directions, exactly like the generator it was auditing.

The measurements that settled it:
- `truth-reader.py` was wrong on **8 of 25** ledgers. It reported `findings.closed=0, open=0` on six
  builds holding 164 findings all recorded as fixed; 291 of 693 rows had their status silently
  discarded; severity was read from body prose, so "README-critical" scored a CRITICAL.
- Its `steps.done`/`steps.total` **agreed with `gen.mjs` on all 28 builds**, including the three
  shipped builds reporting 0/19, 0/17 and 0/14 whose own receipts record every wave done. For that
  field it was not independent at all — it laundered the generator's bug into "truth". That
  statistic is the one v0.31 exists to kill.
- Three implementations of "compute a true value" were live at once (this file, plus inline python
  inside `defeat-corpus-check.sh` and `recount-check.sh`) and they **disagreed on 11 of 28 builds**.
- `recount-check.sh`'s headline "6 disagreements" was mostly its own parser: it only understood pipe
  tables, so bullet-shaped ledgers returned 0. The real count was 1. Anyone "fixing" pages to match
  it would have broken five correct ones.
- `visible-provenance.sh` and `one-reader-check.sh` were proxies. The label rule they approximated is
  now scored directly by the gold (`unlabelled`, `unsaid`), against the same auditor the gold uses.

**What replaced them:** `proven-numbers.sh` asks a different question of each build.
A NEW build (carrying the script-written `.compass-format` stamp) declares its numbers in a data
block, and the page must match that block exactly — a comparison against a declared value, with no
reader in the path. A LEGACY build makes no truth claim at all; every number it states must simply be
marked, in words a reader can see, as counted-by-reading-and-possibly-wrong.

## These are NOT retrievable, and that is a real cost

The recovery line that used to sit here was false. Checked:

```
truth-reader.py          commits=0     <- never committed. Gone.
visible-provenance.sh    commits=0     <- never committed. Gone.
one-reader-check.sh      commits=0     <- never committed. Gone.
recount-check.sh         commits=2     <- recoverable from git history
```

Three of the four were written and deleted inside a single working session and were **never
committed**, so `git log --diff-filter=D` returns nothing for them. `truth-reader.py` matters most:
the measurements that justified the entire v4/v5 redesign — "wrong on 8 of 25 ledgers", "agreed with
gen.mjs on all 28 builds" — were taken from that file, and **nobody can re-run or independently check
them today.**

Those measurements are recorded here and in the contract as findings from round 4's review. They
should be read as **recorded, not reproducible**. The conclusion they support (that no reader can
infer a true value for a build whose data was never structured) is also supported by two other
findings that ARE reproducible — three live implementations disagreeing on 11 of 28 builds, and the
step counts matching the generator exactly — but the specific per-ledger figures are not.

Deleting a file before committing it destroys the evidence it produced. Commit first, delete second.
