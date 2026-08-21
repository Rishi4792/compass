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
