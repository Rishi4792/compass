# honest-fix-reaches-zero — the POSITIVE control

**How it was found.** An independent reviewer simulated an honest fix and measured
**baseline 159 · honest fix 141 · `<template>` cheat 124**. The cheat scored nearly twice as well
as the fix, and exit 0 was unreachable by any honest implementation. Two causes, both now fixed:
probes were raw markdown compared against rendered markdown (1,114 of 2,215 could never match), and
identical remainder text across different rows collapsed onto one control, so the anti-dump rule
killed 62% of honestly-disclosed probes.

**Why it is in the corpus rather than in a comment.** This project shipped v0.31 with a gold no
honest implementation could reach. The lesson recorded then was: ask FIRST whether an honest
implementation reaches the target. This entry asks it on every run, automatically.

**Reproduce.** Render every dropped unit visibly in its own `<details open>`, escaped through the
generator's own helper. Re-measure.

**What must happen.** The figure must reach **zero**. Not "fall" — zero. Anything else means the
check is measuring something an honest fix cannot satisfy.


## CHANGED 2026-08-21 (S6b) — it no longer simulates, and that is the finding

The simulation appended one control per dropped unit at the END of the page. That was a fair
stand-in while the check tied controls to rows by TEXT. It stopped being one when the check learned
to tie them by POSITION — because a pile of controls at the page foot IS an aggregation, and the
check is right to refuse it. A control that simulates a fix the rules correctly reject proves
nothing, so the entry now applies NOTHING and asserts the SHIPPED generator reaches zero.

**Why position, and why it took three attempts.** Text alone cannot bind a control to a row: a page
that dumps every remainder into one box contains every row's text, so it matches every row. Size
alone cannot either — on a small page a dump is small. Both were tried and both let contract §9's
cheat 4 through (89 → 65 and 89 → 65 again). What separates them is that an honest control sits
immediately after the text it discloses. The generator now carries the SHOWN half into the trace so
the check can require exactly that, and a path that does not carry it is UNBINDABLE: counted
unreachable, never credited on a maybe.

**Scope, stated because a scoped assertion that reads as a total one is a lie.** Three of the
thirteen destroying paths carry their shown half today, and this asserts zero over those three.
Ten do not — that is step S7 — and they are named in the check's own output on every run.
