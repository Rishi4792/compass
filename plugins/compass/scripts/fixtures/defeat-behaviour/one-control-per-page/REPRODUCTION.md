# one-control-per-page

**How it was found.** Contract §9 cheat 4. It defeats cheat 3's fix (the control is not empty) and
any check that asks only "does this text appear on the page?".

**Reproduce.** Collect every dropped unit into one `<details>` appended to the page.

**What must happen.** The unreachable figure must NOT fall. The check credits at most ONE
destroying event per control; the rest are counted as dumped, and dumped is not reachable.
