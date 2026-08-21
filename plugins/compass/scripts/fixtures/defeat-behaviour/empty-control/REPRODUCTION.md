# empty-control

**How it was found.** Contract §9 cheat 3. It is the obvious way to pass a check written as "does
this row have a disclosure control?" — the shape v1 of this contract very nearly specified.

**Reproduce.** Append one empty `<details>` per shortened row; re-render; re-measure.

**What must happen.** The unreachable figure must NOT fall. The check looks for THIS unit's own
text inside the control, not for the control.
