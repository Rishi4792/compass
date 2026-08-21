# hide-rows

**How it was found.** Contract §9 cheat 2, raised by an independent reviewer who measured it at
340 → 296 on the old marker-based figure. My own first report of "340 → 0, reproduced by me" was
WRONG — my edit was a syntax error that crashed the generator to zero pages, and I recorded that
correction as SELF-3 rather than leaving the better-sounding number standing.

**Reproduce.** `CLOSED_SHOWN = 0`, re-render, re-measure.

**What must happen.** The unreachable figure must NOT fall. Hiding a row means its whole text is
unreachable, so the count should RISE.

**What it proves TODAY, stated honestly.** On the tracked corpus this cheat changes 2 rendered
pages, and source-unreachable goes 100 → 100. That is a PASS under the rule — the cheat bought
nothing — but it is the *weaker* form of the proof: with 100 of 114 source lines already
unreachable, the cheat has almost no room to make things worse. As S6 and S7 land and that figure
falls toward zero, this entry sharpens on its own into the strong form (the cheat makes it rise).
Recorded here rather than left for a reader to infer from a flat number.

**It is judged on SOURCE coverage, not on the probe figure, and that is the finding.** Measured on
the probe figure the cheat WINS: 159 → 130, because hiding a whole row also deletes the field
truncations inside it, so a denominator keyed to what the generator reports dropping shrinks while
the reader loses more. This entry is the reason the second, source-keyed measure exists at all.
