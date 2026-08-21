# `corpus/` — a TRACKED corpus for the reachability check

The live corpus this build measures its gold over is `.claude/builds/`, which is **gitignored**
(`git ls-files .claude/builds` → 0). So a clean clone has zero pages, and any check pointed at it
there measures nothing while reporting a confident zero — which is indistinguishable from reporting
that the defect is fixed.

Two ideas were tangled and are now separated:

- the **gold** is measured over the live build folders on a working machine;
- the **check** is regression-tested against these four tracked fixtures.

That is why the check takes an explicit `--corpus <path>`: pointed at these fixtures it must run and
pass; pointed at an absent live corpus it must **ERR**, never PASS.

**These four are chosen to fire all nine destroying paths**, not merely to look representative.
Fixtures chosen by ledger shape alone would leave most of the paths untested while every check
stayed green — the exact failure this build exists to remove.

| dir | what it is for |
| --- | --- |
| `long-ledger` | 30+ ledger rows, most settled — fires `closedRows.slice` |
| `short` | small and clean — the control; most paths must NOT fire here |
| `no-ledger` | no `review-ledger.md` at all — the review view must still render |
| `dup-ids` | two rows sharing an id, and the long-field shapes that fire the `fieldText` paths |
