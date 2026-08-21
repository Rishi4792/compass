# shared-shown-half — the generator names the row, so the generator can make every row the same row

reachable-argument.mjs binds a control to a row through `shown = normalise(r.shownProbe).slice(0,30)`,
a string the GENERATOR supplies. Three rules key on it:

* `isDump(ci)` = `new Set(events.map(ev => evShown.get(ev))).size > 1` — distinct SHOWN halves;
* `claimed.get(i) === shown` — a control may be re-claimed by the same shown half;
* `rowChars.get(shown)` — the budget, summed over every event carrying that shown half.

Hand every event one 16-character constant and all three collapse together. The budget becomes the
whole page's dropped characters; ownership lets one box serve every row; the dump test sees one row.
Only the POSITIONAL rule survives, and it is satisfied by printing the constant once before each box.

The constant is 16 normalised characters on purpose: `>= 12` clears the S7b UNBINDABLE guard, and
`< 20` skips the NOT RENDERED test entirely.

Measured on the tracked corpus, honest tree vs cheat:

    dropped units 172 / 172 · probed 135 / 135 · NOT RENDERED 35 / 35
    REACHABLE 135 / 135 · UNBINDABLE 0 of 13 / 0 of 13 · UNREACHABLE 0 / 0
    SOURCE LINES 108 / 108 · SOURCE UNREACHABLE 66 / 66
    COMPASS-GATE: PASS / PASS

and on the page (long-ledger/review):

    honest  25 controls, one per row, first at 38% of the body, last at 76%
    cheat    8 controls, all labelled "Everything that was shortened", last at 98%

Suite battery on the cheat, against the same non-git baseline copy: smoke 804/5 (identical failure
set), selftest 556/5 (identical), behaviour-corpus 11 entries 0 failing, declared 3/0,
defeat-corpus 2/0, redfirst 4/0. Nothing moves.
