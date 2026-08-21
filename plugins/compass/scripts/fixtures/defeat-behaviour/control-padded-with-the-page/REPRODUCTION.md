# control-padded-with-the-page — the entry that PINS the budget ceiling

**How it was found.** The fifth independent review (M-1): deleting the size test
(`if (ctrls[i].text.length > budget) continue;`) changed **no assertion and no corpus entry**.

**What it does.** Leaves the control exactly where an honest build puts it — immediately after its
row, holding that row's own remainder — and pads it with 8,000 characters of the contract.

**What must happen.** The unreachable figure must NOT fall. "Per row" is not only about position;
a control that speaks for one row and also carries the whole document is an aggregation wearing a
correct address.

**What it proves that nothing else does.** Delete the budget ceiling and this entry goes red while
every other entry stays green.


## WHAT THIS ENTRY ACTUALLY PINS, corrected 2026-08-21

It does **not** pin the budget ceiling, and saying it did would have been the comfortable version.

Measured: delete the budget ceiling and this entry still passes — the padded control is refused by
the POSITIONAL rule first, because padding one control pushes the next row's shown text out of the
600-character window before it. Two attempts to isolate the budget both failed the same way.

A second reason a relative rule cannot pin a check: **mutating the CHECK moves the baseline with
it**, so "the figure must not fall" compares two numbers that both dropped. That is why this entry
now carries an absolute `floor=`, and it is worth carrying even though the budget turned out to be
subsumed — the floor is what makes any future check-mutation visible here.

**What it does pin:** that a control in the right place, holding the right remainder plus eight
thousand characters of everything else, is still refused. It goes 65 → 110, the strong form.
