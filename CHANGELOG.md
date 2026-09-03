# Changelog

All notable changes to Compass are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/); versioning is [SemVer](https://semver.org/).

## [0.34.0] — 2026-09-02

Pages a stranger can read, and the checks that prove it.

Every page Compass renders was the spec re-arranged: internal codes visible to the reader,
sentences stopping mid-thought, and plain words that reached one view and not the others. This
release changes what the generator EXTRACTS, so a person's own words reach the page.

- **`compass-reader-copy`** — eight keys of plain English that override the spec text on every
  in-scope view, checked at the moment a contract locks.
- **`readable-pages-check.sh`** — renders a capped, authored fixture corpus through four views and
  reports six metrics beside their populations. Four control fixtures must FAIL the class each one
  NAMES, so a detector cannot be deleted while the run still reports health.
- **`gold-diff-check.sh`** — the contract's published figures are diffed value by value against the
  producer that made them.
- **`copy-reaches-check.sh`** — the thesis tested behaviourally, by marking the block and requiring
  the mark in the page's visible text.
- **`argshift-check.sh`** — a flag that takes a value must refuse to be given none rather than spin
  forever. Twenty-four call sites were unguarded; two of them hung a real command.
- The mechanical suite now verifies its own child list, so it can no longer report every check clean
  after one has been unwired.

**Fixed:** a fixture corpus that shipped an absolute home path in four hook-payload files.

**The exposure window, counted rather than estimated.** This entry first said "since at least
v0.33.5". That was wrong by fourteen releases. Walking every tag and counting the files that contain
the path gives: clean through v0.27.0, then **four files in every one of the 15 tagged releases from
v0.28.0 to v0.33.5**, then clean again at v0.34.0. The path is still present in public git history
and in the v0.33.5 tag on the remote, so the remediation here is forward-only — v0.34.0 onward does
not carry it, and earlier tags still do.

**Shipped un-converged.** review-contract rounds 1-3 carry no valid nonce: that rule was adopted
mid-build and back-filling one would forge the single field that makes evidence unforgeable. The
evidence gate remains armed and RED. Signed by Rishi Kapoor, 2026-09-02.

**Speed:** +5.2s against an 8s budget, measured on fresh clones. The 61s ceiling was never raised.

## [0.33.5] — 2026-08-25

**A gate signed off with a finding it never made.**

`engine-gate`'s passing message ended with the words `Skill found at $skilldir.` — unconditionally.
That variable is **empty** whenever no `long-build` skill is installed, which is every installation
but its author's. So the gate whose entire job is to make the engine decision honest printed:

```
PASS — engine armed and BOUNDED — cap=40, counter at 0, recorded in progress.md
and stamped on a receipt. Skill found at .
```

**The decision was right and is unchanged.** v0.33.0 removed the skill dependency on purpose,
because Compass now ships the doctrine at `shared/engine.md` and what the gate asks for is a
*recorded decision*, not an installed file — `engine: none · reason=driven by hand` is answerable
with nothing installed at all. It was the **sentence** that lied, claiming a finding the gate had,
one line earlier, failed to make.

Now the pass says which case it is, the same rule the N/A branches already had to follow because a
bare N/A reads as "armed":

- skill present → `Skill found at <the real path>.`
- skill absent → `No long-build skill is installed here — this build is held to the engine doctrine
  at shared/engine.md, which is what the decision was always about.`

**Proven able to fail before it was trusted green.** Three assertions were written and run against
the *old* code first. The two naming the defect went red (`got 1 want 0`, `got 0 want 1`); the
control — an armed, bounded build passes with no skill installed — was green throughout, so the fix
could not have been a quiet weakening of the gate. A fourth, that the message names a real path when
the skill *is* there, was green before and after.

**The class, recorded honestly rather than claimed.** `unwired-gate-check` counts whether a gate is
*reached*. Nothing counts whether a gate's *words* match what it found. The registry now carries that
class with the owner **"not yet owned"**, because guard-first says a line scan cannot have it: the
nearest mechanical shape returns ~90 hits on this tree and about nine in ten are noise, since a line
scan does not track function scope — one `local s` matches every later message in the file. Stating
the gap is worth more than a check that fires on correct code.

**Suites:** smoke **1007 passed / 0 failed** (up 3) · selftest **561 / 0** · recon **PASS** ·
mechanical-suite **9 of 9**.

## [0.33.4] — 2026-08-24

**The last dormant thing turns out never to have existed.**

`cockpit-gate`'s "plain-words half" probed for a `feynman-walkthrough` directory and, on finding
none, printed an honest-looking N/A. **That is all it did.** There was no check on either branch —
nothing counted, nothing compared, no way for it to fail. It was not a dormant rule; it was **a rule
that never existed, wearing an N/A**. And it could never have worked as designed: it keyed on a
user-level skill this plugin has never shipped, so every installation but its author's took the N/A
branch.

**Now it is a real check.** v0.33 moved the teaching method into `shared/walkthrough.md`, so the
standard is in the plugin and the check needs nothing installed. The stage-end block is what a
person reads to decide what happens next, so it may not carry internal codes — same rule and same
fixture as `copy-gate`, one source for what counts as jargon. Blast radius measured before wiring:
**32 folders, 0 refused.** Proven able to fail: a block containing `cmd_gate` and `INV-COCKPIT` is
refused by name.

**Three of my own bugs on the way in, and they are the useful part of this entry.**

1. **A shell-quoting error made the gate refuse 31 of 32 folders while never running.** The
   `'\''`-escape idiom only works inside a single-quoted string; inside `"$( )"` those quotes
   terminate the outer quote.
2. **Then an unguarded `grep` under `set -e` did the same thing again.** grep exits 1 when it finds
   **nothing** — the *passing* case — so the clean path killed the function silently: exit 1, no
   stdout, no stderr. **That is T2 in this release's own shell-trap catalogue, committed by the
   author of the catalogue.** And `shell-trap-check` did **not** catch it: T2 scans for a bare
   `read`, and this was `x="$(… grep …)"`. A new **T2b** now counts that shape — 47 on the tree, all
   reported and none failed, because most sit in an `if`, `while` or `||` chain where a non-zero
   status is tolerated and telling which is judgment.
3. **A `\n"` where a `\n'` belonged** broke the summary block and made the checker exit 2 while
   still printing its output. Third occurrence of that same over-escape this release.

Every one was found by **running the thing**, never by re-reading the diff.

**KNOWN-OPEN and directory-probes are both zero.** `unwired-gate-check`: *0 unwired of 106
dispatchable commands, 8 human-typed, 0 KNOWN-OPEN, 0 directory-probes.*

Gates: smoke **1003 passed / 0 failed** · selftest **561 / 0** · recon PASS · mechanical-suite 9 of 9
· canary 387 calls over 32 folders, **0 newly refused**.

## [0.33.3] — 2026-08-24

**Everything v0.33.0 shipped as "known open" is now closed.**

**The perf budget has margin again — 48s against the 53s ceiling, up from 53s with none.** The
release suite had been running the mechanical suite **twice**: once normally and once with
`COMPASS_V32_STRICT=0`, purely to prove the flag cannot move a verdict. That comparison cost ~6s of
a 15s allowance to prove a property of *printing*, not of measurement. The suite now emits both
verdicts from a single pass and the assertion compares them. Same claim, one execution, **5 seconds
of headroom recovered**.

**`drift-check` runs at last.** It re-runs a shipped build's recorded observation command, it has
existed since v0.23, and *nothing invoked it* — so nothing detected drift after any release. It is
now called from the post-ship loop, the only thing that runs after a release.

**Reported, never enforced, and the measurement decided that.** Over the 14 build folders that
actually carry a post-ship loop, drift-check refuses **10**. The refusals are `exit 127` — a
recorded command that no longer resolves. That is environment rot in a historical build, not a
product regression, and hard-failing a round on it would have broken the loop for most builds that
have one. Telling rot from regression means reading the command, which is judgment. So the round
runs it, prints its verdict, and carries on: a drift that matters is visible every round instead of
invisible forever.

**`cockpit-gate` runs at last too — and this one needed the no-touch lifted.** It validates a block
the model *prints* at a stage transition, so its only correct home is the stage skills' gate block —
which `INV-7` pins byte-identical across seven skills from `shared/gate.md`, a file under a standing
no-touch order. Two earlier attempts to wire it elsewhere were abandoned rather than widen the gate
into inertness. With the no-touch lifted it is wired into the canonical block and all seven copies
at once; **INV-7 still reports 7 of 7 byte-identical**, and the canary reports **0 newly refused**.

**KNOWN-OPEN is now zero.** `unwired-gate-check`: *0 unwired of 106 dispatchable commands, 8
human-typed, 0 KNOWN-OPEN.*

**And wiring it exposed one more unbounded pattern**, the third this release has found. The
assertion counting the cockpit push read `compass.sh cockpit` with no boundary — so
`compass.sh cockpit-gate` matched it and the count went to 2. Exactly the shape of the
`min-width`/`width` bug in the clip detector two releases ago. The push and the gate now have
separate assertions so neither can go missing unnoticed.

Gates: smoke **1002 passed / 0 failed** · selftest **561 / 0** · recon PASS · mechanical-suite 9 of 9
(both verdicts, one pass) · canary 387 calls over 32 folders, **0 newly refused** · perf 48s of 53s.

## [0.33.2] — 2026-08-24

**The last two things the cold readers found.**

**A disclosure was repeating itself four times.** `noteDropped()` appended a remainder every time a
field passed through a helper, and several fields pass through more than one. A reader measured the
card carrying this plan's whole rationale in a browser: **8,190 characters of which ~2,050 were
unique** — the same block four times. Their verdict was that a reader would hit the repeat and
conclude the page was broken, *worse than not disclosing at all, because they had already chosen to
click*. A remainder is a fact about a field, not a running log, so it is stored once. Genuinely
different remainders for the same field still accumulate.

```
longest disclosure : 8,123 chars, opening block 4×   →   2,030 chars, 1×
```

**And two of the four fact cards were 111 pixels wide.** A grid track's implicit minimum is `auto`,
so the card holding a long unbreakable file path refused to shrink and took the space from its
neighbours — about three words per line, eleven screens tall when opened. `minmax(0, 1fr)` lets every
track shrink to its share.

**Fixing that layout exposed a false positive in v0.32's own clip detector**, and this is the part
worth reading. The rule `(?:width|height)\s*:\s*0` had **no word boundary**, so it matched the
`width:0` inside **`min-width:0`** — the standard grid idiom for letting a track shrink. A card
styled with it had its entire subtree read as CLIPPED and its text counted unreachable: **eight
assertions moved on a page that was perfectly readable.** `max-height:0` keeps its own dedicated
rule and still catches real clipping; what is now excluded is a *prefixed* property, which is a
different declaration meaning something else.

Bisected rather than guessed: CSS reverted → 999/0; grid alone → 999/0; grid plus `min-width:0` →
991/8. The boundary fix makes all three green.

Both fixes carry a regression test. Gates: smoke **1001 passed / 0 failed** · selftest **561 / 0** ·
recon PASS · mechanical-suite 9 of 9 · canary 387 calls over 32 folders, **0 newly refused**.

**Now closed:** every defect the two independent cold readers found in v0.33.0 — the five unreachable
rows (0.33.1), the repeating disclosure, and the 111px column. **Still open:** the perf budget is
spent exactly, 53s of a 53s ceiling with zero margin, and two gates remain KNOWN-OPEN
(`drift-check`, `cockpit-gate`).

## [0.33.1] — 2026-08-24

**The sentences that stopped now finish.**

v0.33.0 shipped with one Critical named on the label: text on a page a reader could not get to.
Two independent cold readers had hit it five times. This is that fix.

**The cause was one function, and it lost text silently.** `bullets()` split the source on newlines
and kept only the lines that matched a bullet — so a markdown bullet **wrapped onto a second line
ended at the wrap**, and everything after it vanished. No `(continues)` marker, no disclosure,
nothing downstream able to restore it: the renderer believed the item had ended, so there was no
"rest" for it to put in a control.

Measured over the fixture corpus and this build's own plan: **8 of 108 top-level bullets are
wrapped, and every one was losing its tail.**

```
the page two cold readers read : 5 unreachable of 13   →   0 unreachable of 10
the pinned corpus              : already 0 of 21       →   0 of 21
```

**`INV-OUTSIDE-IN` is now MET.** The row the readers named — *"…there is no read-modify-write on"* —
renders whole, through to its full stop. The next one is shortened properly, with a "Show the rest"
that opens onto the remainder.

**And it has a test that would have caught it.** A fixture carries a sentinel word in the second
line of a wrapped bullet. Rendered with the bug the sentinel is absent; with the fix it is present.
Proven both directions before the fix was trusted.

**One thing the canary caught on the way in**, worth recording because it is this project's own
lesson: the new fixture declared the v0.30 contract format, which obliges a reader-copy block, so
`copy-gate` refused it — 1 newly refused historical build. A fixture should exercise one rule, not
accidentally opt into all of them. The claim was dropped and the reason written into the fixture.
Canary back to **0 newly refused**.

Gates: smoke **998 passed / 0 failed** · selftest **561 / 0** · recon PASS · mechanical-suite 9 of 9.

**Still open from 0.33.0, unchanged:** the perf budget is spent exactly (53s of a 53s ceiling, zero
margin) · two gates KNOWN-OPEN (`drift-check`, `cockpit-gate`) · three artefact defects the cold
readers found that are not this fix (a disclosure repeating its content four times in a 111px
column, a dangling "see below", and 61 vs 59 unreconciled on one page).

## [0.33.0] — 2026-08-24

**Stop paying reviewers to do a linter's job — and find out how much of the job is actually a
linter's.**

The last release ran six independent adversarial reviews. They found 59 recorded defects, and this
release began by counting how many needed judgment at all. The answer is committed to the repository
rather than asserted in a commit message:

| | count | share |
| --- | --- | --- |
| **mechanical** — a script could have caught it | **32** | 54% |
| **judgment** — someone had to decide true from misleading | 27 | 46% |

Just over half of what six adversarial reviews found needed no reviewer. Nine checks now find that
class in about six seconds, for no tokens, and they run **before** any reviewer is spawned.

**But the honest finding of this release cuts the other way**, and it is on the tin: *"mechanical"
means a script could catch it IN PRINCIPLE, not that a line scanner catches it soundly.* Of five
shell-trap classes, exactly **one** could be made to fail correctly without also failing on correct
code — three separate rules for the awk-apostrophe trap each fired on working shell, and the first
never fired at all. So every check now states whether it **MEASURES** (fails a run) or **REPORTS**
(prints and never fails), and the suite reports far more than it fails.

**Both outside skills Compass was quietly depending on are now inside it.**

- `shared/engine.md` carries the non-stop-build doctrine: long batched turns, slow work detached
  rather than polled, state on disk that outranks the conversation, and five safety fences. **What
  it deliberately does NOT ship is the self-re-arming loop.** Compass's `--auto` still stops after a
  step; this release makes that stop *legible* rather than silent. The keystroke that continues a
  run is the fence, not an oversight.
- `shared/walkthrough.md` carries the teaching method, so `/compass:explain` works with nothing
  installed. It had pointed at a skill Compass has never shipped, with no fallback, for three
  releases — working on exactly one machine.

**Three checks that had never run on any installation, found by a script in seconds.**
`cockpit-gate` and `stage-end-gate` were built by v0.32 to fire at every stage end and were invoked
by nothing. `engine-gate` excused itself whenever a user-level skill was absent — its own message
said *"for most installs this gate is inert BY DESIGN"*. `shared/feynman.md` opened with *"Loaded by
the contract, plan and ship stages"* while zero stages loaded it.

**C-1 is closed structurally.** v0.32's reachability check ran inside the generator's own process and
read a trace the generator wrote about itself. The new one renders as a subprocess and reads only the
page and the tracked source. Proven by making the generator lie — `lossy()` turned into a no-op so
its trace reported destroying nothing — and the figure was byte-identical.

**Under the hood.** Suite 997 passed / 0 failed. Nine mechanical checks, a class registry so the
suite grows, a recorded-override path so a cap bounds drift rather than the person who owns the
build, and evidence for `INV-COLD-READER` for the first time since v0.32 — two independent readers
and a grading, on file.

### Known open, and named on purpose

- **`INV-OUTSIDE-IN` is NOT met, and the number says how badly.** Two independent cold readers found
  rows they could not finish on a page the reachability check called clean. The check was blind four
  ways: it knew one marker form of three, could not see rows cut with no marker at all, missed a
  truncation nested *inside* a disclosure, and kept its verdict in two code paths that had drifted
  apart. Fixed — and the figure rose from **0 unreachable of 5 to 9 of 13** on that page, and 0 of 5
  to 3 of 21 on the pinned corpus. **It was not tuned back down.** The remaining defect is real and
  in `gen.mjs`: it destroys text a reader cannot reach.
- **The perf budget is spent exactly.** A fresh clone measures **53s against the 53s ceiling** — the
  entire 15s allowance, to the second, with runs of 53 / 52 / 53. Ordinary variance decides the
  verdict and a slower machine is already over. **The ceiling was not raised to buy margin.**
- **Two gates remain KNOWN-OPEN**, printed on every run so they cannot quietly become permanent:
  `drift-check` (a post-ship monitor nothing invokes, so nothing detects drift after a release) and
  `cockpit-gate` (its proper home is pinned byte-identical across seven skills from a no-touch file;
  two attempts to wire it elsewhere were made and abandoned rather than widening it into inertness).
- **Four defects the cold readers found in the artefacts** and this release did not fix: a
  disclosure that delivers ~2,050 unique characters as 8,190 — the same block four times — in a
  111px column eleven screens tall; a dangling "see below" with no below; and two figures on one
  page (61 and 59) left unreconciled.
- **The build's own review never converged.** Review-1 took four rounds against a cap of two;
  Review-2 took four against a cap of three and reached one clean round where the rule wants two.
  Both cap raises are recorded with who decided and when. Accepted un-converged on a signed waiver.

### The thing this release keeps proving against itself

Every check in it caught a defect in another check, and the cold read caught what no check could.
A vacuous class shipped green five times because its pattern had two words reversed, and was found
only by trying to plant its red. A baseline was corrected twice — once for false provenance, once
for measuring the wrong population. **A check's blindness is usually in what it counts, not in how it
counts**, and the only reliable way to find that is to run it against something that disagrees.

## [0.32.0] — 2026-08-24

**Compass stops saying things it cannot back up.**

Compass has always stated a lot: that a review ran with independent adversaries, that a page shows
you everything, that a performance budget was measured. This release makes it prove those, and —
where a thing cannot be proven — say so on the page instead of implying otherwise.

**What you will notice**

- **Shortened text is finishable.** When a page shortens a long field it now leaves the rest behind a
  control you can open, and a check proves every dropped unit is reachable on its own page. Measured
  over the pinned corpus: 152 of 152 reachable, 0 unreachable.
- **A review that claims six streams ran must show six.** The denominator comes from the review
  skill's own machine-readable stream list, never from the receipt's claim about itself. Before this,
  20 receipts said "all streams run" and exactly one build folder held any evidence at all.
- **Every review page says: "This review was NOT independently verified."** Because it cannot be.
  A reviewer forged a subagent transcript pair in four shell lines with zero agent calls, so the
  invariant that tried to prove independence was deleted and replaced with a sentence that is true.
- **A performance budget needs a measurement behind it.** Not the word "measured" — a run series
  whose figures reconcile arithmetically with the bound they support.
- **Pages stop claiming certainty they do not have.** Statuses fall into settled, open, or unreadable
  by the contract's own lists; unreadable is never folded into settled; and when any row is
  unreadable the page states an honest range rather than a single figure.

**Known open, and named on purpose**

- **C-1 — one cheat this release cannot see.** The reachability check runs inside the generator's own
  process, so a generator that lies about its own trace cannot be caught from inside it. Six rules
  were tried, each measured and rejected; all six are recorded in the code with their numbers. The
  check prints what it is blind to beside every verdict, passing or failing. The fix is structural —
  measure from outside the generator — and it is the next contract.
- **Two evidence records are incomplete.** The cold-read harness ships and self-checks, but the two
  reader transcripts the contract asks for were not run. And 4 recorded RED proofs stand against
  roughly 15 gates added — each was mutation-proved during the build, but in commit messages rather
  than in the evidence file. Both are carried to the next build rather than waived quietly.
- **§17-15**: `gen.mjs`'s `cockpit()` render function is unreachable dead code. MINOR, carried.

**Cut before shipping**

The long-build wakeup counter was built, reviewed three times, and removed. It counted per directory
when a loop is per build, two sessions halved it, its stall detector could not be made to work by
that approach, and it had never once fired in the repo it was written in. It bought a bound on a loop
a human can close by hand and cost a script running on every prompt in every project. `engine-gate`
survives: a build must record its engine and cap, and an armed loop with no stated bound is refused.

**Under the hood**

Nine new checking scripts and six new gates, all wired into `compass.sh gate` — because a gate
nothing calls is not a gate, which this release learned twice. Six independent adversarial reviews
found 61 real defects; every mutation those reviewers applied now turns the suite red.

## [0.31.0] — 2026-08-20

**Every number says where it came from.**

Compass pages state a lot of numbers: how many findings a review caught, how many steps a plan has,
how many are done. Until now every one of those was worked out by reading hand-written markdown with
about ninety ad-hoc regular expressions — and when that guessing was wrong, the page stated the wrong
number with exactly as much confidence as when it was right. Three shipped builds reported "0 of 17
steps done" over plans that were finished.

**Now every number on a page carries a marker saying what it is**, written at the moment the
generator prints it:

- **declared** — the build wrote this number down as data, and a gate holds the page to it.
- **counted** — the generator worked it out by reading the files, so it may be wrong.
- **quoted** — copied from what someone wrote in the build's files; as reliable as that file.
- **literal** — a version, a date, an id. It claims nothing about this build's data.

A gate checks the whole thing: **8,516 numbers across 140 pages, every one accounted for**, with 50
positive controls that fail if the auditor is broken. It rides the review-build seam, so it gates
rather than being something someone remembered to run.

**Every page now also says, in words a reader can act on, which of its numbers were not checked** —
and the disclosure covers the numbers a reader *cannot* verify, not just the ones they can. That
correction came from a stranger reading the pages cold; the first version covered 2,358 numbers and
left 6,158 bare.

### Also
- `gold-numbers-gate` audits the build it is handed. It used to run over 28 other build dirs and
  report PASS while the build being gated declared 999 steps over a 16-checkbox plan.
- `artefact-audit` can fail. It called its own gate with no source and no copy checks, collapsed
  every problem into one line with `tail -1`, and returned 0 regardless.
- Numbers the generator invents — a step number where the plan line had none, the "and N more" of a
  truncated field — now say they were counted. 248 of them across 21 of 28 builds used to claim
  someone had written them in a file.
- Each view names itself. A Review page, a Plan Map and a Release Card all used to be titled
  "Contract" in the browser tab and in the published gallery.
- The review page stopped counting a second table's header row as a finding (it reported 3 findings
  over 2 real rows, and named one of them "ID").

### What this does not claim
For the 27 builds that predate the data block there is no true number to check against — their data
was never written down in a structured form, so any "independent reader" is another guess. Those
pages make no correctness claim at all; they tell you the number was not checked against anything.
That is the honest position, and it took four rejected designs to arrive at it.

**The gold proves a disclosure is present, not that it is true.** A sentence containing the required
phrase while asserting its opposite still scores clean — reaching that state takes an edit to the
generator plus a re-pin of a hash in a tracked file, a visible diff rather than an accident, but it is
a real limit. It is written into the build's contract with its reproduction, and it is v0.32's work.
**This release shipped un-converged, under a user-signed waiver, with its open findings named.**

## [0.30.0] — 2026-08-20

**The artefact layer, rebuilt around the reader.** Three complaints started this: the decision
question had stopped appearing, the progress line never showed, and the artefacts were "not thought
out, and very random".

**For you**
- **Decisions are buttons.** The typed lock phrase is gone from the whole plugin, so the question
  actually gets asked instead of being typed past. The mode question comes before the render.
- **One link, not a pile.** An artefact publishes to a single Artifact URL stored in build state;
  regenerating updates the same link. macOS-only `open`, `~/Downloads` and the peer-to-peer send are
  deleted — nothing requires a particular machine.
- **A terminal block that renders** — a left-rail ASCII block printed in the response, with a
  one-line hook backstop. No hook can render a multi-line box (every line gets a prefix), which also
  means v0.28's 11-line orient block was mangled in production and is now fixed.
- **Pages written for a person.** The model writes plain-language copy into a declared block; the
  generator only lays it out, from one pinned design system, deterministically.
- **Five views** — Contract Brief, Plan Map, Release Card, and a review artefact reporting what the
  reviews caught.

**Under the pages**
- **INV-0 (RED-FIRST)** — no promise counts until its check has been run against the old code and
  watched to fail. **INV-0b (POSITIVE-CONTROL)** — every pattern check carries a known-bad input it
  must keep matching, so a rotted pattern reports an error instead of a pass.
- The evidence record requires the checker's own output plus a code-version stamp resolving to a
  real commit; typed prose no longer passes as a measurement.
- Nine adversarial rounds fixed **107** reader-visible defects; every fix carries a test replaying
  the attack. Suite **578 → 682**.
- New: `compass.sh converge-waiver` — Compass can now record "shipped with known open findings"
  instead of forcing a false checkbox. It requires a user-signed line and prints what is unmet every
  time. It sits outside `cmd_gate` on purpose: v0.28's INV-NO-LIFECYCLE-CHANGE freezes that
  function byte-for-byte and caught the first attempt to put it there.

**Shipped un-converged, deliberately.** The review did not reach two clean rounds; it ran nine and
each found real defects at a similar rate, because `gen.mjs` reads hand-written markdown and every
reader of that is a judgement that can be wrong both ways. Everything found is fixed; the CAUSE is
not. **An unusually formatted ledger can still make a review page state a wrong count.** Accepted by
an explicit user-signed waiver. The cause is v0.31's work: the model writes findings and steps as
structured data and the generator stops parsing prose.

**The lesson.** The suites were green through all nine rounds and caught **none** of the 107
findings. A suite written by the same author, in the same session, as the code it tests converges on
agreeing with that code. Compass knew a check must be proven able to fail; it lacked the other half —
the proof must come from somewhere the author does not control.

## [0.29.2] — 2026-08-17

**The Release Card said "0 changes" for every standard contract.** It read shipped items only from a `### NOW` section of numbered items, but the ladder the contract skill actually writes is `## Scope ladder` with `- NOW:` bullets — so a release card advertised that nothing had shipped. Now read from the canonical ladder (which already separates NOW from LATER/NEVER, so the v0.24 guard against advertising deferred items as shipped is preserved), with the numbered form kept as a fallback. The hero also names the release rather than repeating the contract's document title.

Found by generating a sample artefact and looking at it — not by a test. A regression assert now covers it, and was proven to bite.

smoke 556 → 557. All green.

## [0.29.1] — 2026-08-17

**Patch, found by v0.29.0's own post-ship loop — the "fourth redesign" failure it was seeded to catch.**

v0.29.0 routed the fields it knew about through the fence-blind parser and left **five others reading raw markdown**: the security sub-section reader, and the Release Card's version, goal and NOW-scope extraction. A `### never-show` or a version string inside a fenced example would have been read as data — the same bug in a different field, which is precisely the regression the critique target names. All are now fence-blind. The only remaining raw read is the document title, a top-level `# ` heading that cannot sit inside a fence without breaking the fence.

smoke 556, selftest 561, recon 130 pinned groups. All green.

## [0.29.0] — 2026-08-17

**The artefacts are rebuilt around the reader.** The Contract Brief and Plan Map were the most visible thing Compass produces and the least usable — so this release rebuilds all four generated views on one decision-first skeleton, and turns "it looks messy" into a set of commands that can fail.

**The headline defect, and its actual cause.** The shipped Brief printed the literal token `<goal from INDEX>` **four times**, including in "Done means". The field parser scanned raw markdown for `Key:` lines and never skipped fenced code blocks — so it read `Goal: <goal from INDEX>` out of an **ASCII mockup inside the Design Spec** and used a drawing as data. The same blindness inflated plan step counts, because `- [x]` lines inside fenced receipt templates were counted as real steps.

- **Four bands, same order, every decision artefact** — the decision you're being asked to make, the 4 facts needed to make it, the logic block, then detail. Asserted positionally, so the order is a test rather than a preference.
- **A real diagram on every view** — inline SVG generated from the contract's own logic map (or the build's structure), laid out in reading order. No runtime, no network, and counted structurally (≥3 rect, ≥2 path, ≥3 text) so a decorative icon cannot pass.
- **Every plan step now shows the command that proves it.** The `VERIFY:` line was previously parsed and discarded.
- **The plan artefact is a plan** — approach and rejected alternatives, what could break, how we know it works, going live. Anything absent renders `N/A — reason` rather than vanishing.
- **It refuses rather than lying.** An unresolved required field exits non-zero and writes nothing, naming the field. A blank where the headline should be is quieter than a placeholder, and worse.
- **Local delivery** — the artefact is written, gated, copied to `~/Downloads`, opened on the machine Compass is running on, and Taildropped to your other Mac. `COMPASS_NO_OPEN=1` reduces it to writing the file and printing the path.
- **A structural gate with no browser** (`compass.sh artefact-gate`) — tokens, band order, diagram shape, self-containment, counts-vs-source, and freshness. A page older than its source now fails.
- **The palette is read from the theme file**, not hand-copied, so a theme edit can no longer drift the artefacts while the anti-drift gate keeps passing against stale values. One deliberate addition: a `fontMono` token.

**Honest note on the two previous attempts.** v0.26.0 and v0.27.0 both claimed to redesign these views to a "builder mental model", and both regressed — because neither pinned a binding mockup or a testable definition of "good". This time the accepted wireframe *is* the spec, and 11 mutation recipes prove each new test goes red when its behaviour breaks.

Suites: **smoke 517 → 556**, selftest 561, recon 130 pinned invariant groups. All green.

## [0.28.1] — 2026-08-17

**Patch: v0.28.0 shipped with a bug in its own headline feature, and shipped it in a way users could not have received the fix.**

- **Fix (from the v0.28.0 post-ship loop):** with **no build in flight**, `orient` emitted nothing at all. `cmd_active_builds` prints a human `0 active builds.` status line, which the row parser counted as a build; the renderer then tried `--where <state-root>/COMPASS-GATE:` and died. That is the single most important case in the release — a new user with no builds is exactly who the NEW-BUILD block exists for. All four parse sites now route through one guarded helper, with two hermetic regression asserts.
- **Why this is a version bump and not just a commit:** plugin version drives update detection — if the resolved version matches what a user already has, `/plugin update` and auto-update **skip the plugin**. The fix landed on `main` without a version bump, so anyone who installed `0.28.0` in the window between the release and the fix would have been pinned to the broken build forever. Bumping to 0.28.1 is what actually delivers it.
- The `v0.28.0` tag is left where it is (published tags don't move); `v0.28.1` is the tag that contains the fix.

smoke 517 · selftest 561 · recon PASS.

## [0.28.0] — 2026-08-17

**Compass now always tells you where you are — and this release starts by admitting it didn't.** The welcome block had sat in `commands/go.md` since v0.15.0 with tests that only checked the words existed in the file. Measured across real session transcripts, it printed **0 times in 30 `/compass:go` invocations** over twelve versions. A guard that reports coverage it doesn't have is worse than no guard, so this release replaces byte-presence tests with behaviour tests, everywhere it mattered.

- **Orientation, always.** `compass.sh orient` renders the block from your actual state — the mental model when nothing is in flight, a where-you-are block when a build is running (never the long intro twice). A tightly-scoped `UserPromptSubmit` hook delivers it via `systemMessage`, the one channel Claude Code actually shows the user; plain hook stdout is context-only and would have reproduced the original failure exactly. The hook is silent in projects with no `.claude/builds`, exits 0 on every path including malformed input (exit 2 would erase your prompt), and costs **6.3 ms** on the no-match path that >99% of prompts take.
- **Progress, always.** `compass.sh progress-card` prints an itemised planned-vs-done card at **every build step**, and the step's own gate refuses to advance until that card is on the receipt. It cannot flatter: a box ticked without a recorded verify renders `box-only`, never `verified`. Plans over 12 steps collapse the finished ones and window around the current step, so a long plan never becomes a wall.
- **Run-mode is always asked and always shown.** Compass may no longer infer whether you want Human-gated or Autonomous — it must ask, and record `asked=yes · answer=… · source=…`. `mode-gate` rides the contract seam, driven by a `mode-asked: required` contract header so every pre-existing build stays unaffected. This exists because it went wrong *during this build's own session*: the mode was inferred from an unrelated answer and written as if chosen. That exact string is now a failing test fixture.
- **One renderer, three doors.** `/compass:go`, `/compass:status` and `/compass:resume` all call the same renderer; the hand-written welcome prose is deleted, so a second copy can't drift.
- **Opt-in status line.** `compass.sh statusline-install` (with `--dry-run`) adds a permanent `slug · stage · step k/n · mode · next` line, after backing up your settings. **The release never edits an installer's global config by itself.**

**Two pre-existing bugs found while building this, both user-visible:**
- `last_block` matched receipt headers with bracket expressions holding multibyte characters (`[—-]`, `[·|]`). Under `LC_ALL=C` those are invalid byte ranges, so **every receipt lookup returned empty and every gate reported "no receipt"** — Compass was quietly broken in CI, cron, and minimal containers. Now explicit alternation, with a locale-varying test that would have caught it.
- `is_terminal` was case-sensitive while `ship` writes `status=shipped` in lowercase, so **every finished build was reported as still in flight, forever**: `active-builds` listed 12 shipped builds as active and `/compass:go` kept offering to resume long-finished work.

**Guard quality, not just guard count.** All 15 new invariants ship with mutation recipes proving each test goes red when its behaviour is broken (`mutation-check` → 15/15 bite). The anti-self-edit floors were pinned at 222/406 against actual counts of 465/546 — loose enough that half the smoke suite could be deleted unnoticed; they're now pinned at actual−5 and proven to bite. `INV-NO-LIFECYCLE-CHANGE` was narrowed with explicit sign-off: `cmd_gate`'s core decision logic stays byte-identical to v0.23.0, and every seam call must now be `type`-guarded — a stronger pin than the blanket freeze it replaces.

Suites: **smoke 465 → 514**, **selftest 546 → 561**, recon 119 pinned invariant groups. All green.

## [0.27.0] — 2026-08-04

**The other three milestone artifacts now read like a decision, not a spec dump — matching the Brief.** v0.26 redesigned the Contract Brief to the builder's mental model; v0.27 gives the **Plan Map**, **Release Card**, and **Program Cockpit** the same treatment. Layout-only — no change to what they read or how they're delivered.

- **Plan Map** — leads with the goal + a progress hero (`k/n steps · W waves`), then the steps grouped by wave.
- **Release Card** — a prominent `vX.Y.Z` SHIPPED hero, then what changed (**NOW-scope items only** — the v0.24 no-LATER/NEVER guard is now a biting test), then a proof + rollback row.
- **Program Cockpit** — a two-altitude timeline (program phases + contracts-per-phase) above the current build's 7-stage strip.

Built + reviewed on Compass in `--auto`. review-contract caught that the test fixture wouldn't populate the views (PROGRAM.md is read from the parent dir; contract.md is mandatory) and that the NOW-only guard was unguarded; review-plan caught a fake-green trap (the shared house `<style>` already defines `.stat`/`.flow`, so tests must grep the new `class="…"` attribute, not bare tokens). New invariants **INV-VIEW-IA / INV-VIEW-DETERMINISTIC / INV-VIEW-GATES** (each view populated · byte-identical · passes anti-drift + compose), driven by a committed fixture. Suites: **selftest 546 · smoke 455→~465 · recon 101→104 pinned INV groups**; floors held (406/222). `INV-NO-LIFECYCLE-CHANGE` holds — no `compass.sh` change at all (only `gen.mjs` + tests + manifests).

## [0.26.0] — 2026-08-04

**The Contract Brief is now correct, redesigned around how a builder thinks, and actually delivered — not just written to a folder.** This release closes a real "the check passed but the outcome didn't happen" gap: the milestone invariant only checked that an HTML file existed on disk, so a Brief could be garbled, never rendered, and never shown — and the gate still went green.

- **Fixed the generator's section-parsing bug.** `gen.mjs`'s `sec()` did a loose substring match, so `"Non-goals".includes("goal")` made it render the Non-goals as the goal; and it read the goal from a `## Goal` heading that real contracts don't have. Now `sec()` is **anchored-at-start** (after an optional `N.` prefix — so `## 4. Security` / `## 2. Scope ladder` still resolve, `Non-goals` doesn't), the goal reads the `**Goal:**` inline, and `scope()` parses the real `### NOW/LATER/NEVER` format (it was returning empty).
- **Redesigned the Brief to the builder's mental model.** Problem → picture-of-done (a **before→after**) → the one proof → the moves (a flow) → guardrails → a details fold — instead of a flat spec dump. It generalizes to any contract (a data-pipeline fixture proves it), stays leak-safe on `--shareable`, and passes the house anti-drift + compose gates.
- **A real `compass.sh render`** — headless-Chrome screenshot, watchdog-bounded, fail-closed. So `png=N/A` can only be written **after a genuine failed attempt**, never faked.
- **Milestone = delivery.** `compass.sh milestone-gate` now requires a delivered milestone's receipt to carry `render=<html>` + `png=<png|N/A — reason>` + `artifact=<url|N/A — reason>` — a bare `N/A` fails closed — and the contract/plan/ship skills **render → show inline → publish via the Artifact tool → then gate**. Guard-first, so legacy receipts (no `artifact=` token) still pass. A Brief on disk that was never shown or published is no longer "done."

Built + reviewed on Compass in `--auto`. review-contract (2 critics) caught that milestone-gate never ran on the Brief + the receipt-grammar/leak-gate risks; review-plan (2 critics) caught that `scope()` returned empty on real contracts (blank Brief) + several vacuous tests. Suites: **selftest 546 · smoke 429→~445 · recon 96→101 pinned INV groups**; floors held (406/222). `INV-NO-LIFECYCLE-CHANGE` holds — the engine (`cmd_gate`/`LIFECYCLE`/prod-safety) is byte-identical to v0.23.0; the changes are `gen.mjs`, a new `cmd_render`, and the standalone `cmd_milestone_gate`.

## [0.25.0] — 2026-08-04

**Trim the `/` menu to three — for real.** v0.24 marked nine commands `tier: advanced`, but Claude Code's `/` autocomplete ignores `tier:` and still listed all twelve. v0.25 makes the menu actually show three doors — `/compass:go`, `/compass:status`, `/compass:resume` — via the documented mechanism, with nothing losing the ability to run.

- **The real lever: `user-invocable: false`.** The `/` menu is populated by BOTH command files AND skills, so demotion-by-`tier:` could never shrink it. Every Compass skill (the 7 stages + the 2 migrated helpers + the 3 bundled design skills = 12) now carries `user-invocable: false` — hidden from the menu, still fully invocable by Claude. Only `go`/`status`/`resume` remain as command files, so `/compass:` shows exactly three.
- **`start` and `explain` migrated to skills.** The 15 KB `start.md` orchestrator (the graph, file-based state, parallel-build/worktree keystone, the `--auto` two-gate loop + self-spawn, the pipeline) and `explain.md` are now real skills (`skills/start`, `skills/explain`) so `/compass:go` still drives the whole lifecycle. The nine redundant command files (7 stage wrappers + `start` + `explain`) were removed.
- **The byte-locked gate footer points at `/compass:go`.** The one-line transition footer now sends you to the front door (which reads state and routes on), and the gate block body no longer names any per-stage command. The block stays byte-identical across the 7 stage skills (`g7==7`; `shared/gate.md` is the canonical source).
- **Every dead `/compass:<stage>` reference scrubbed.** A new `INV-NO-DEAD-REF` invariant proves no shippable surface — the README stage table, ROADMAP, `compass.sh`'s auto-start banner, the gate block, `go.md`, and every skill — points at a command that no longer exists (CHANGELOG history exempt).

Built + reviewed on Compass itself in `--auto`. review-contract (3 critics) caught the premise error — deleting command files alone can't shrink the menu, because skills surface in `/` too (verified against the Claude Code docs) — and the fresh dead-`/compass:*` surface the hide mechanism creates inside `skills/*/SKILL.md`; review-plan (2 critics) hardened the tests (value-aware `user-invocable` check; re-authored the pinned README phrase). Suites: **selftest 546 · smoke 410→~430 · recon 90→96 pinned INV groups**; floors held (406/222). `INV-NO-LIFECYCLE-CHANGE` proves the stage graph, gate exit-codes, and prod-safety functions are byte-identical to v0.23.0 (the one `compass.sh` edit is a user-facing banner string, outside every frozen range).

## [0.24.0] — 2026-08-04

**Clarity + simplicity: one front door, progress that pushes itself, and a program cockpit for multi-phase / multi-contract builds.** The tool now shows you where you are without being asked — including across phases and the multiple contracts within a phase — and the surface is three commands, not twelve.

- **One front door (by tier).** `/compass:go` is the single entry — it starts or resumes, drives the lifecycle, and pushes progress. A `tier:` frontmatter key marks exactly three commands **primary** (`go` · `status` · `resume`); the other nine become **advanced** — still fully functional, just off the welcome. No command was removed (deleting them would dangle the byte-locked gate footer across 8 consumers), so nothing breaks.
- **The pushed Cockpit — a real command.** New `compass.sh cockpit <dir>` (pure bash, git-free, ~60 ms): the 7-stage pipeline with your position, step k/n, and next action. Its call is wired into the byte-locked gate block (identical across all 8 consumers), so **every stage transition prints it with zero typing — and so does resume / a fresh terminal**. Silence between stages is now a defect a test catches.
- **Program Cockpit — two altitudes, contracts-per-phase.** A backward-compatible ledger format adds optional `contract:` child rows under a phase, so the cockpit shows Phase K/N **and each contract in the phase** (done ✓ / current ◉ / left ○) above the current build — the answer to "how many phases, how many contracts, what's done, what's left" at a glance. Suppressed when there is no program; single-contract ledgers render unchanged.
- **Mandatory house-styled milestone artifacts.** New `compass-visual` views — `plan-map`, `program-cockpit`, `release-card` (joining `brief`) — render an rk-house-style HTML body at contract-lock / plan-lock / phase-boundary / ship. The HTML body is **mandatory** (node, no browser) and recorded as a `MILESTONE:` receipt line; the contract/plan milestones are enforced for free by the frozen receipt gate, ship/phase by a new `compass.sh milestone-gate`. The PNG is best-effort — a Chrome-less machine degrades to an `N/A` receipt, never a block.
- **Mode-choice pinned to one point.** The Auto-vs-gated question is asked only at contract lock (G1); the two docs that disagreed are reconciled.

Built + reviewed on Compass itself in `--auto`: contract (3-critic review-contract: 5C+5M reshaped the design — tier-demotion, the real cockpit command, ledger child-rows, HTML-mandatory/PNG-best-effort) → plan (2-critic review-plan) → build (spine → renderers → 12 new invariants across the coupled triple) → review-build. Suites: **selftest 546 · smoke 377→409 · recon 78→90 pinned INV groups**; floors held (406/222). INV-NO-LIFECYCLE-CHANGE proves the stage graph, gate exit-codes, and prod-safety functions are byte-identical to v0.23.0.

## [0.23.0] — 2026-08-04

**Phase-3 finisher: operability + test-rigor + durability (completes the compass-3-phase program).** Four features, each byte-inert or additive-only until a build opts in — legacy builds are unaffected.

- **DORA operability ledger.** `dora-record` appends one metadata row (outcome · stages · review rounds · build `cycle` · sig · ts) to a gitignored `.claude/builds/DORA.md` on every terminal exit — wired into `close` + ship through a subshell so it can NEVER fail or change an existing terminal write (additive). `dora-ledger` renders the records + count + ship-rate (0 rows → NA; a malformed row → fail-closed FLAG). The dup-check is per `(slug, outcome, sig)` under a mutex.
- **Opt-in drift monitor.** `drift-check` re-runs a shipped build's recorded verification command (the ship receipt's `RECON-CMD:`, or the contract's `observation-channel:` with its `<facet> = ` prefix stripped) from the repo root and FLAGs if it is no longer green. On-demand only — no autonomous loop.
- **Hermetic-test review method.** A new HERMETIC review island — byte-identical across `review-plan` and `review-build` (like RBACSTRIDE/EDGERACE/PERFFMEA) — makes a web/time/network build's tests pin the clock + timezone, stub the network, and be run-twice deterministic; a non-hermetic suite blocks CLOSED. Byte-inert for builds with no time/network surface. Completes the correctness-rigor trio with v0.22's mutation-check + red-green.
- **Durability contract nits.** Every contract now seeds a `## Glossary`, an `alternatives-considered:` (ADR) line, `one-way-door:` irreversibility labels, and a `RACI:` owner line (template-presence, no rejection gate).

## [0.22.0] — 2026-08-03

**Program-continuity ledger + test-rigor gates (Phase 3, contract 7a).** A multi-build program can now track its own phases in a durable, tamper-evident ledger, and two new test-rigor gates prove that a build's tests actually bite. All five surfaces are **byte-inert (N/A-pass) until a build opts in**, so legacy builds are unaffected.

- **Program ledger.** `program-init` / `program-ledger` / `program-next` / `program-advance` manage `.claude/builds/PROGRAM.md` (a gitignored, per-repo ledger of a program's phases). `program-advance` marks a phase shipped and moves the `current:` pointer, but only behind a **real-tag + tag→build-binding guard**: the phase's recorded tag must be a REAL git tag (rejects `HEAD`/a branch/a bare SHA) whose committed `plugin.json` version equals the tag with its leading `v` stripped, must not be borrowed from another shipped row, and — when the build dir is present — must also pass `lifecycle-audit SHIPPED`. The guard runs entirely OUTSIDE the ledger lock (never leaks the mutex), and the ledger is byte-unchanged unless the whole guard passes.
- **Staleness + structural cross-check.** `program-ledger` FLAGS a `status=shipped` row whose tag is missing/forged/stale, a tag reused across shipped rows, and structural breaks (duplicate slug · `current:` ≠ first-non-shipped · >1 in-flight · declared phase total ≠ actual row count) — so a lying ledger by any vector is caught, fail-closed.
- **Executable mutation gate.** `mutation-check` RUNS each `mutation:` recipe from a build's receipts.md in an ephemeral sandbox: red must PASS on a pristine copy (control) then FAIL after the break (mutant killed). A decorative recipe (red stays green) or a broken control red FAILS; a live-file cksum backstop DETECTS (fail-closed) any break that escapes the sandbox. The live tree is never edited.
- **Red-green evidence.** `redgreen-check` requires a build that adds a test (`adds-test: yes`) to carry a real, non-placeholder `red-green:` attestation (the failing test + why it failed first) — accepting real vocabulary, rejecting only empty/placeholder, with the substance re-challenged at review.
- **Dogfood.** The `compass-3-phase` program ledger is seeded (Phase-1 `v0.15.4`, Phase-2 `v0.21.0` shipped, 7a in-flight), and `go`/`resume` surface the next phase.

## [0.21.0] — 2026-08-03

**Data, migration & compliance safety — the consolidated finisher (Phase 2, contract 6).** The last cluster of audit gaps closed as durable, fixture-proven Compass gates, so a schema-changing or data-touching build can no longer reach SHIPPED with these risks unchecked. Nine audit items, each **fail-closed on a declared surface** and **byte-inert (N/A-pass) off it**, shipped in four committed waves.

- **Contract-header pins.** `schema-pin-gate` (a `schema-touching: yes` build must carry a filled field-schema block — `name · type · nullable · unit/enum · example` + `evolution-rules:` — or an explicit `schema-pin: N/A — <reason>`) and `perf-budget-gate` (a non-trivial-Scale build must pin literal p95 + peak-mem + cost + an SLO healthy-range). Both ride the **contract** gate seam.
- **CROSSTAB review island (item 5).** A new method block, **byte-identical across `review-plan` `[B]` and `review-build` `[B]`** (smoke-enforced like PERFFMEA/EDGERACE/RBACSTRIDE): enumerate cross-table invariants (child-sums-to-parent · no orphan FK · one active generation), assert **DB-constraint/trigger** enforcement (not app-only) + a **zero-violators** pre-flight. Carries the load-bearing **`challenge the disprovable N/A for schema/migration/PII`** clause (smoke-asserted, not prose).
- **Migration-safety gates.** `expand-contract-gate` (a declared migration is phased expand/contract with an old-code-on-new-schema probe recipe + a prod-shaped dry-run; a `contract` op is deferred to a separate post-bake build), `backfill-recon-gate` (a declared backfill records a count+checksum tie-to-source), and `rollback-fwdcompat-gate` (a schema/data ship RECORDS `old-code reads new-version writes → OK`, enforced at ship and re-challenged in review). Discipline + probe-*recipe* checks — the plugin never touches a live DB (a hard non-goal).
- **Merge / compliance / image.** `green-ci-gate` (a CI-declaring repo records a green-CI merge proof, re-challenged in review), `pii-gate` (a `pii: yes` build's plan states `compliance/PII: no raw PII/secret in logs · retention · residency · no regulated field out-of-scope`), and image-secret hygiene (a `test-tenant` disclosure + checklist; **`secret-scan` is text-only** — no image/OCR scanner).
- **The honest boundary.** These header/discipline gates are the fail-closed floor on a **declared** surface; a **concealed** surface is caught by the review methods (the CROSSTAB challenge-N/A clause + review-plan/review-build re-challenge of every honor-level recorded line). The gate can only see what the author declared — by design, since the plugin is dependency-free.
- **Enforcement + the review that earned it.** 14 new INV-group names synced across the coupled triple (`recon.sh` `INV_NAMES` + `selftest.sh` `NAMES12` + the `smoke.sh` name-loop; self-guard-protected against drift). Guard-first N/A-pass so every legacy build passes byte-identically (INV-BC — seam witnesses for the contract, plan, and review-build seams). The final adversarial review ran **five rounds**: it caught **3 CRITICAL soft-passes** (gates matching required tokens as loose whole-file substrings / accepting empty values / matching through negations — a build with zero real budget numbers passed) and **6 MAJOR false-rejects / enforcement gaps** (natural phrasings like `p95 latency: 200ms`, `2 GiB`, `no regressions` wrongly blocked; the rollback gate never enforced at ship), all fixed and regression-locked. Suites: **selftest 406 → 471 · smoke 297 → 324 · recon 50 → 64 pinned groups**; floors held (never re-baselined).



**Per-dependency FMEA + anti-pattern-hunt review METHOD (Phase 2, contract 5).** The review's operability/perf stream was named-only — it never forced the reviewer to reason about what happens when an external dependency is slow or down, or to hunt the query-count/memory anti-patterns that blow up at real scale. Two classes of prod incident lived there unchecked: an unmitigated dependency (a call with no timeout, no fallback) and an unbounded anti-pattern (N+1 / paginationless fetch / O(n²)) that is fine on a toy set and falls over at the contract's row count. v0.20 turns that stream into a real, enforced method.

- **PERFFMEA island.** One combined delimited method block, **byte-identical across `review-plan` `[D]` (operability) and `review-build`** (smoke-enforced like the EDGERACE / RBACSTRIDE / COMMSCAN blocks, so it cannot drift). It carries: (1) a **per-dependency FMEA** — for each external dependency (DB / API / cron / queue / third-party) state its behavior when **slow** and when **down** plus the mitigation (timeout / retry-backoff / fallback); **no dependency called with no timeout**; (2) an **anti-pattern hunt** — N+1, paginationless / unbounded fetches, O(n²) loops, with the **query count and peak memory asserted at the contract's row count**, not a toy set; (3) a **challenge-the-N/A** clause — a real dependency or a data-volume-sensitive loop present while the review claims N/A is itself a finding (*never wave off a dependency or volume-sensitive loop you can see*); and a **blocks-CLOSED** consequence (unmitigated dependency = MAJOR; data-loss / OOM at the contract's volume = CRITICAL).
- **Byte-inert & self-contained.** N/A (byte-inert) for a build with no external dependency or data-volume-sensitive loop. No external skill dependency. The `plan` stage gains an FMEA / perf design step for dependency builds.
- **Enforcement.** 7 new `INV-PERFFMEA` smoke fixtures (byte-identity, one island each, the 5-anchor method grep, a **receipt-only** `applied` anchor whose match is proven scoped to the receipt line — the island body carries no `applied`, a plan-step grep, and the byte-inert grep) + 5 pinned INV-group names synced across the coupled triple (`recon.sh` `INV_NAMES` + `selftest.sh` `NAMES12` + the `smoke.sh` name-loop). Suites: **selftest 406/0 · smoke 285 → 297 · recon 45 → 50 pinned groups**. Teeth mutation-proven (all 7 fixtures bite; the isolated tests keep byte-identity green while only the target fixture goes red) and cleared by an independent fresh-context critique.

## [0.19.0] — 2026-07-31

**Boundary/edge + concurrency/TOCTOU review METHOD (Phase 2, contract 4).** The review's `[A]` correctness stream was named-only — no numeric/temporal boundary checklist and no race analysis. Two classes of prod bug lived there unchecked: off-by-one / naive-UTC-vs-IST / month-rollover, and idle-in-transaction locks / saturated-pool races. v0.19 gives `[A]` a real, enforced method.

- **EDGERACE island.** One combined delimited method block, **byte-identical across `review-plan` `[A]` and `review-build` `[A]`** (smoke-enforced like the RBACSTRIDE/COMMSCAN blocks, so it can't drift). It carries: (1) a **boundary/edge checklist** — for each numeric/temporal/index input on a reachable path, enumerate null · empty · zero · one · max · negative · **off-by-one** · unicode · **timezone+DST** · month/year rollover; each unhandled boundary on a reachable path is a finding; (2) a **concurrency/TOCTOU** analysis — for every read-modify-write, name the **losing interleaving** and **assert the guard** (row lock / unique constraint / atomic upsert), and flag long transactions holding locks across I/O; (3) a **challenge-the-N/A** clause — a boundary/RMW surface present while the review claims N/A is itself a finding (*never wave off a boundary or race you can see*).
- **Byte-inert & self-contained.** N/A (byte-inert) for a build with no boundary or read-modify-write surface. No external skill dependency. The `plan` stage gains a concurrency/TOCTOU-analysis step for read-modify-write builds.

Built contract→review→plan→review→build→review on Compass itself in `--auto`. The reviews found + fixed **2 CRITICAL-adjacent MAJOR + 5 minor**: review-contract caught the byte-inert N/A being a *disprovable escape hatch* and the method's teeth (`assert the guard`, `blocks CLOSED`) being unpinned (EDGERACE had cloned RBACSTRIDE's shape without its teeth); review-plan caught a receipt-grep tautology-risk and a non-self-caught leg of the coupled name-sync triple. The method teeth are **mutation-proven** (stripping either tooth from both byte-identical islands flips the fixture). Suite floors: **selftest 406 · smoke 222 → 285** (5 new pinned INVARIANT groups; recon now pins 45). Explicit non-goals (later contracts): perf-budget/FMEA/anti-pattern/SLO, data & migration safety, compliance/PII, screenshot secret hygiene, a runtime concurrency/race harness (app-specific), and all Phase-3 items.

## [0.18.0] — 2026-07-31

**STRIDE + role×resource RBAC-matrix + IDOR review METHOD (Phase 2, contract 3).** The contract stage already *pins* the security surface (per-field classification + a role×view matrix + STRIDE-lite, since v0.15), but the review that's supposed to check it was named-only — `[E] Security/RBAC` / `[D] Security/RBAC/data-leakage`, one line each. v0.18 gives it a real, enforced method.

- **RBACSTRIDE island.** A delimited method block, **byte-identical across `review-plan` `[E]` and `review-build` `[D]`** (smoke-enforced exactly like the COMMSCAN block, so it can't silently drift). For every new view/endpoint the build adds, the reviewer: (1) builds a **role×resource matrix** and asserts each cell against the contract's role×view; (2) treats a view/endpoint added while the contract's role×view is `N/A`/absent as a **CRITICAL** — *never trust a disprovable N/A* (the under-declared-surface / cross-visibility class); (3) **STRIDE-walks** each surface; (4) runs an **IDOR probe** — as each lower role, fetch another tenant's object id → assert **403/empty**; (5) a deny cell that returns data / a non-403 / any unasserted cell → a **CRITICAL that blocks CLOSED**.
- **Byte-inert & no hard dep.** The method is N/A (byte-inert) for a build with no new view/endpoint. The repo's `permission-matrix` skill is wired **when present** only — never a hard dependency. The `plan` stage gains a threat-model / RBAC-matrix design step that produces the matrix the reviews assert against.

Built contract→review→plan→review→build→review on Compass itself in `--auto`. The reviews found + fixed **3 CRITICAL + 1 MAJOR**: review-contract caught the method silently no-op'ing on an under-declared contract (its whole target case); review-plan caught a hidden **double name-list** (recon `INV_NAMES` + selftest `NAMES12`) that would break `selftest`, and a **tautological grep** (`"N/A"+"CRITICAL"` already appear elsewhere) that would let the headline security clause ship missing on a green suite — now a unique-phrase grep, **mutation-proven** (deleting the clause from both byte-identical islands flips the fixture). Suite floors: **selftest 406 · smoke 222 → 272** (6 new pinned INVARIANT groups). Explicit non-goals (later contracts): boundary/TOCTOU, perf-budget/FMEA, data & migration safety, compliance/PII, screenshot secret hygiene, a runtime IDOR harness (app-specific), and all Phase-3 items.

## [0.17.0] — 2026-07-31

**Declared-value CERTAIN shareable-Brief scrub (Phase 2, contract 2).** The `compass-visual` Contract-Brief generator used to redact the shareable copy by *guessing* which numbers in the free-form prose were the confidential reconciliation gold — a best-effort heuristic whose long tail the v0.15 post-ship loop kept finding one more format it missed. v0.17 replaces the guess with a declaration.

- **`brief-data` fence.** A contract can carry an optional, machine-readable ` ```compass-brief-data ` fence declaring its `gold:` value(s) and `never-show:` tokens. When present, a `--shareable` Brief scrubs each declared value **and every numerically-generable reformatting of it** — the full cross-product of {Western 3-digit, Indian 2-2-3} grouping × {comma, ASCII/NBSP/thin/narrow space, apostrophe, European period} × {no-prefix, currency} — with **certainty**, keyed off a value the contract *states* rather than one the generator guesses. The declared value is normalized to its bare magnitude first, so declaring `₹87,50,000` covers the same set as `8750000`.
- **Fail-closed by construction.** No fence, or a `none`/empty fence → the prior best-effort scrub, now honestly labelled. A malformed fence (unclosed, or an unparseable body) → **hard error (exit 2) on `--shareable` only** — never a silent downgrade to "absent", never a blessed exit-0 leak. Recognition is robust to CRLF, tab/NBSP/exotic-whitespace tag separators, a markdown info-string token, and a single `.ext`, while an unrelated tag (`compass-brief-database`) is correctly ignored.
- **Additive, not a replacement.** The declared values also seed the best-effort normalized layer, so the belt-and-suspenders hold even when the Reconciliation section is `N/A` (the intended hybrid setup). The **local** lock-surface Brief ignores the fence entirely and stays faithful+full; the shareable copy carries an always-on best-effort caveat banner.
- **Honest bound.** Certainty covers the realistic numeric-locale set for 3+ significant-digit declared values; undeclared unit-word/spelled-out/exotic-Unicode restatements and very short (≤2-digit) or unit-suffixed values are exact-scrubbed where possible and otherwise best-effort — the structural guarantee (the gold *card* is always a badge, secrets hard-stop, the artifact is opt-in and operator-reviewed) always holds. This tail is disclosed in the skill, not chased.

Built contract→review→plan→review→build→review on Compass itself in `--auto`. The adversarial reviews earned their keep: **4 CRITICAL + 9 MAJOR + 9 minor** found and fixed across the stages — the recurring class was a fence-recognition **fail-open** (a Windows CRLF fence, then tab/NBSP/U+2028 tag separators, that leaked a *declared* value at exit 0) and a certainty-set narrower than the promise (Indian-grouping-with-non-comma separators, and an over-claimed unit-word guarantee). review-build's 5-round fan-out ran the built code against ~70 crafted contracts; the separator set is now single-sourced so it can't drift, and a **mutation-proven coverage fixture** fails if any separator is dropped. Suite floors: **selftest 406 · smoke 222 → 256** (34 new fixtures). Disclosed residual (accepted): the exotic-Unicode / <3-significant-digit tail is best-effort, honestly labelled. Explicit non-goals (later Phase-2/3 contracts): STRIDE/RBAC method, boundary/TOCTOU, perf-budget/FMEA, data & migration safety, compliance/PII gate, screenshot secret hygiene, and all Phase-3 items.

## [0.16.0] — 2026-07-29

**Survive the cutover (Phase 2, contract 1).** A production cutover is where a bad ship becomes an outage. v0.15 added the two prod-safety HARD STOPs (`restore-point`, `config-parity`); v0.16 adds the five-gate **cutover safety net** Compass hands to the managed build's prod — each a real `compass.sh` subcommand, fail-CLOSED, byte-inert for a build that declares no cutover config:

- **`canary-analysis`** — promote a slice only on *independent* green (canary reconcile + route-smoke; the gold command must differ from the slice command and not read the build's own artifacts, so "green" can never be self-computed). No traffic split → records `SUBSTITUTED-BAKE`, which now *requires* a bake window. A burn-rate **BREACH** auto-fires the rehearsed rollback with no human wait.
- **`bake-gate`** — the required soak before the terminal SHIPPED write. The bound is a **declared input** (`bake-bound:`), never inferred: an absent ceiling *or* an absent reading (especially memory) is **never** in-bound; multi-line readings union to the worst. A LIBRARY bound re-runs the suites green (Compass's own release dogfoods this).
- **`watcher-check`** — an opted-in cutover needs a **named** watcher (a real name, not `TBD`) or, in `--auto`, a **proven-armed** rollback (`rollback-rehearsed: … → exit 0`, not a bare `armed`).
- **`abort` / `abort-check` / `abort-clear`** — a mid-flight sentinel checked at the top of each build step and before every mutating op, so `compass.sh abort <slug>` halts an autonomous build *before* the next mutation, bounding blast radius (bulk ops run in checkpointed batches).
- **`ship-cutover-receipt-match`** — the ship receipt must record all three of canary/bake/watcher (N/A or real); a `deploy: in scope` build cannot fail-**open** by leaving all three N/A without an explicit `cutover: waived — <reason>`.

Wired into the ship skill as **Step 0.7** (a HARD STOP after prod-safety, before SHIPPED) and into the build skill's per-step loop (the abort check). Fixture-proven end-to-end (`fixtures/{abort,bake,canary,watcher,cutover-receipt}/`). Two adversarial reviews earned their keep: review-plan's 3-agent pass closed 2 CRITICAL + 7 MAJOR **before any code**, and review-build's 6-round fan-out found and fixed **3 CRITICAL + 13 MAJOR** in the built gates (a bake-gate that read absent memory as in-bound; a canary that promoted a *recorded failure*; an `--auto` that shipped on a placeholder) — all permanently regression-locked (17 fixtures) with the gates now take-WORST and fail-CLOSED. Suite floors re-baselined **selftest 349 → 406 · smoke 192 → 222**; 7 new pinned INVARIANT groups. Disclosed best-effort residual: the canary reconcile/route-smoke checks read operator-recorded receipt text (structural teeth — gold≠slice, fail-closed-on-absence, breach⇒rollback — are the guarantee). Explicit non-goals (later Phase-2/3 contracts): STRIDE/RBAC method, boundary/TOCTOU, perf-budget/FMEA, expand-contract migration, mutation testing, DORA ledger, the program-continuity ledger, the compass-visual Brief-generator rebuild.

## [0.15.4] — 2026-07-29

**Fourth post-ship patch — the Brief now shows the FULL block it asks you to lock.** The post-ship critique loop caught that the **local** Contract Brief rendered only the *first paragraph* of the reconciliation and security sections. So a reconciliation figure/tolerance written in a later paragraph — and the F-SECPIN **role×view matrix + STRIDE-lite** (which sit below the classification line in every real security block) — were silently dropped from the surface the operator locks against, contradicting the skill's "renders the full block" promise (CRITIQUE-TARGET #3).

The local Brief now renders the **full section body** (figure, tolerance, role×view matrix, STRIDE-lite all included). The shareable path is unchanged — it still redacts the gold to a badge and scrubs never-show values. Regression-guarded with a multi-paragraph fixture (smoke floor 191 → 192).

## [0.15.3] — 2026-07-28

**Third post-ship patch — completing a partial fix.** v0.15.2's post-ship critique caught that the v0.15.2 security-card fix was half-done: it taught the *badge* to detect never-show in any format, but the shareable **scrubber** still read only the inline `never-show:` key. So a never-show declared as a **list** (`Never-show fields:` + bullets) or a per-field label was not scrubbed, and the leak gate **blessed the shareable copy at exit 0** with the field names present — a soft-pass on a format the product's own tests use.

The shareable scrubber now collects never-show fields in **every supported format** (inline, list, per-field label, multi-value) → list/per-field never-show HARD-STOP at exit 3 with the names absent. Regression-guarded, including the missing `--shareable` list-fixture test (smoke floor 189 → 191).

**Known limitation (Phase-2).** The shareable-Brief leak gate is a **best-effort** scrub over free-form markdown; making it airtight across every conceivable format is deferred to a Phase-2 redesign (or a strict-declared-format re-scope). The structural guarantee always holds — the reconciliation-gold *card* is always badged and the shareable Artifact is opt-in + operator-reviewed.

## [0.15.2] — 2026-07-28

**Second post-ship patch — more parser edges, hardened.** v0.15.1's post-ship critique loop found a second soft-pass class and two Brief format edges:

- **`config-parity` soft-passed a missing prod key named in a COMMENT (MAJOR).** A trailing `# STRIPE_KEY not yet provisioned` on the `prod-keys:` line made the commented key count as *declared* — flipping the HARD STOP to PASS while prod actually lacked it. Comments (`# …`, `<!-- … -->`) are now stripped from `env-keys-referenced` / `prod-keys` before tokenizing.
- **The Contract Brief's security card is now format- and vocabulary-robust.** It renders the sensitive surface (no false "N/A — no sensitive surface" badge) whenever a block declares never-show fields in **any** format (inline `never-show:` *or* a "Never-show fields:" list) or uses common sensitivity words (PII / PHI / commercial-sensitive / confidential / restricted) — even when the block leads with "N/A".

Regression-guarded (smoke floor 186 → 189). Two off-spec residuals remain disclosed as Phase-2 hardening (multi-line env-key lists; genuinely-exotic sensitivity vocabulary) — the documented single-line format and the F-SECPIN vocabulary are fully protected.

## [0.15.1] — 2026-07-28

**Post-ship patch — the loop caught what the review missed.** v0.15.0's post-ship critique loop, running against the freshly-published artifact, found two defects the pre-ship review rounds had not:

- **The Contract Brief could hide a real sensitive surface (MAJOR).** `compass-visual`'s security-card "N/A" detection was unanchored, so an `N/A` inside a *required* STRIDE-lite line ("Repudiation — N/A") or a role×view cell flipped a contract that declares **PII + never-show** fields to a false green **"N/A — no sensitive surface"** badge — exactly the "user locks something they didn't understand" failure the Brief exists to prevent. The N/A badge now fires only when the security block **leads** with N/A **and** declares no sensitive fields; otherwise the per-field classification + never-show list render.
- **`config-parity` tab-anchor parity (minor).** Its header anchor omitted tabs (`restore-point`'s already included them), so a tab-indented `env-keys-referenced:` line was skipped → soft-pass. Both now use `^[-*[:space:]]*`.

Both regression-guarded (smoke floor 183 → 186). No other behavior change. This is the post-ship loop working as designed: SHIPPED is not the finish line — the live artifact is re-critiqued, and a real finding is fixed and re-shipped.

## [0.15.0] — 2026-07-28

**Trust made real, and shown.** Compass's reasoning was already strong; this release hardens its weakest seams and makes the rigor legible to a first-time user. Two halves (Phase 1 of a phased program, grounded in a 16-agent audit of all five stage-agents), built `--auto` on Compass itself.

- **Review integrity (the gate is no longer gameable).** A calibrated **severity bug-bar** (Critical/Major/Minor rubric) that every ledger row must cite; a **self-refutation** rule (a Critical/Major only counts once its trigger is proven *reachable from a real entry point* AND *not already guarded*); and **dedupe + Critical-first + a top-blocker footer** — inlined into all three review skills.
- **Prod-safety floor.** Two new provider-agnostic HARD STOPs wired into ship: **`compass.sh restore-point`** (refuses a destructive migration/backfill without a confirmed, complete snapshot) and **`compass.sh config-parity`** (refuses a deploy when the change references a prod env key prod lacks). Both model `migration-gate` — an absent required signal *dies*, never a soft pass — and are proven by both-direction behavioral fixtures; a `ship-prodsafety-receipt-match` gate makes a silent skip fail the suite.
- **Kill-switch spine + security pin.** The contract now requires a **Rollout & kill-switch** line and a **Security & data-sensitivity** block (per-field classification + role×view matrix + STRIDE-lite; `N/A — <reason>` allowed); the build stage builds user-visible changes flag-off-by-default and verifies both states; ship verifies the flag disables the feature without a redeploy; review's security stream gains a **commercial-sensitivity scan** (IRR/take-rate/gross-rev%/COF on a non-management surface = CRITICAL), kept byte-identical across the review skills so the field set can't drift.
- **Clarity/UX layer.** A confidence **welcome** on `/compass:go` that teaches the mental model; a bundled **`compass-visual`** skill that renders a build's **Contract Brief** (cinematic-hero cover + rk-house-style body, a pure function of `contract.md`) and progress **Cockpit** as self-contained HTML + PNG — with a **local-vs-shareable** split that redacts the reconciliation-gold literal and never-show values before any shareable Artifact; an **explicit contract lock**; a plain-English **Feynman clarity + confidence block** at every stage (size-capped so it never bloats the lifecycle); an auto-vs-gated **mode choice**; and **`/compass:explain`** for on-demand teaching.
- **Reconciliation + adversarial hardening.** Smoke gains 69 v0.15 assertions (floor re-pinned 114 → 183), the recon INV-group registry grows 12 → 27 pinned groups (in lockstep across recon + selftest + smoke), and the prod-safety fixtures + the Brief render + an independent aesthetic eyeball are the genuinely-independent gold. The prod-safety gates (`restore-point`/`config-parity`) and the shareable-Brief leak scrub were hardened through a **multi-round adversarial review-build** — real defects found and fixed, each closed with a re-run regression test (a declared-destructive contract in the repo's own `value → reason` header style no longer soft-passes; the gold-value scrub matches across locale number formats; restore-point fails closed on any non-`no` value). The shareable leak scrub is **best-effort over free-form prose** (documented in the `compass-visual` skill): the gold *card* is always badged and secret classes hard-stop, but a figure a user restates in an exotic format should still be caught by an operator review before sharing. Every INVARIANT asserts a real bound; presence-vs-independent checks are honestly labeled.

## [0.14.1] — 2026-07-24

**Fixed: the front door is `/compass:go`.** Plugin slash commands are always namespaced (`/plugin:command`), so a bare `/compass` can never register — v0.14.0's README, landing page, and changelog overpromised it. Renamed the front-door command `compass` → `go` so it reads cleanly as **`/compass:go`** (not the redundant `/compass:compass`), and corrected every doc to the real invocation. No behavior change: the router logic and the seven namespaced stage commands are untouched; the smoke assertions were updated to the new name.

## [0.14.0] — 2026-07-24

**High-craft prototypes + a single front door.** Two things: Compass now ships a bundled design system so every prototype comes out looking world-class, and `/compass:go` becomes the one command you need.

- **Bundled design system (auto-installed).** Two skills ship WITH the plugin — `rk-house-style` (product UI: dashboards, tables, forms, charts; a pinned `neutral-indigo` default theme, 14 component recipes, and drift gates: anti-drift-grep + compose-check + an independent gestalt scorer) and `cinematic-hero` (hero/launch motion + stills). No external dependency — public installers get the full quality machinery. The bundled `rk-house-style` is **neutralized**: the private theme + real gallery are stripped and replaced by freshly generated neutral **visual gold** (dashboard / form / table), each PROVEN to pass its own gates (0 off-theme tokens + composed-from-the-kit) and reviewed world-class by an independent scorer.
- **Design aesthetic wired into the lifecycle.** For any web/dashboard build, the contract now ASKS which aesthetic and binds it (`design-standard: rk-house-style | cinematic-hero | both`), and the build stage applies that skill's tokens + recipes on every UI step — so "high craft" is the default, not a hope.
- **`/compass:go` — the front door.** One command reads where your build is and asks what to do next, then routes you into the right stage. The seven namespaced stage commands stay as the engine and remain fully usable for direct access; the README now leads with `/compass:go`.
- **Reconciliation.** Smoke gains a v0.14 assertion block (bundled files present, 0 GQ bytes in the neutralized copy, the 3 gold pages + PNGs, the contract/build wiring, the router, the README lead) and its floor is re-pinned to the new baseline; selftest unchanged. Dogfooded end-to-end through Compass's own contract → review → plan → review → build → review → ship.

## [0.13.0] — 2026-07-21

**Co-construct + sketch.** The contract interview stops transcribing and starts co-designing: a six-phase Intake Protocol that scans the repo first, GENERATES possibilities the user hasn't considered (pre-mortem / constraint-relaxation / 10x / adjacent-use-cases — reacted to as menus, never "anything else?"), converges a NOW/LATER/NEVER scope ladder, clarifies only what the scan couldn't answer (hard question budget), and locks — while a Sketch Loop renders what's being decided AS it's decided (grayscale throwaway wireframe for web, Mermaid logic map otherwise, A/B/C alternatives side-by-side before contested questions).

- **`intake-gate` (exit codes, evidential):** ordered phase markers per mode · all 4 generators with ≥2 DISPOSED options each (nothing raised is silently dropped) · **the "expansion was real" hard fail — an all-NOW ledger refuses** (sycophancy or scope balloon, both defects) · Phase-4 question budget enforced (≤4 FULL / ≤2 LIGHT) · ladder COUNT-sync between intake.md and the contract · ≥1 recorded human answer. Evidence-based, never marker-based: re-gating an `--auto` build that legitimately interviewed stays clean; `intake: classic` is the honest headless fallback (an auto session never authors intake.md). `intake-phase` is the resume pointer.
- **`sketch-gate` (exit codes):** the render LEDGER must exist · web builds carry EITHER the ACCEPTED mockup (line-1 `COMPASS-MOCK` marker + visible THROWAWAY banner — the mockup IS the binding spec) OR a named `design-standard:` (both paths kept, per the design decision) · non-web co-construct builds must embed a `## Logic Map` Mermaid fence (a pipeline can't silently skip its logic map) · **the leak tracer: a tracked product file whose LINE 1 is the mockup marker is a hard FAIL** — first-line-anchored, so docs (or Compass's own source) mentioning the marker can never self-trip. Premortem picks feed `CRITIQUE-TARGET:` lines — the v0.12 post-ship critic's seed list: intake wires the loop.
- **Script-owned invocation:** both gates ride `compass.sh gate` (contract + review-build seams) — proven by behavioral fixtures, inert byte-for-byte for legacy builds.
- **Template-drift machinery:** every SKILL-pinned receipt literal (round receipts, cold-critic receipts, user-accepted line, the new contract boxes) is extracted from the skill text by smoke, instantiated via one pinned placeholder map, and fed to the same `*_match` helpers the gates use — templates and parsers physically cannot drift. Every new gate's invocation seam is grep-asserted (INV-WIRED).
- **`compass.recon.sh` finalized:** the pinned INV-group list grows to 12 (the v0.13 groups included); full reconciliation at this release: selftest and smoke both green with counts well above their pinned floors (≥118 / ≥60).
- Suites grow well past the 118/60 baselines (the review-build hardening added ~30 regressions); reconciliation enforces the floors, not a brittle exact total (baselines 118/60 intact — INV-BC); GATE-block byte-identity (8 consumers) preserved throughout. Built by Compass on Compass, same build as v0.12.0 (one contract, two releases — the full 5-layer review ledger lives in the build folder).

## [0.12.0] — 2026-07-21

**The post-ship critique loop, with eyes.** SHIPPED is no longer the finish line: every new shipping build gets a bounded post-ship critique loop against the LIVE system — grounded in on-disk evidence, enforced by exit codes — and `SHIPPED` is mechanically unwritable until it converges. Institutionalizes the loop Rishi hand-wrote into his last three contracts (2 consecutive clean rounds or a 5-round cap), and the 2×cold-GO design gate his UI builds already used by hand. (This release coincided with the Jul-2026 "graph engineering" discourse — Compass's stages/gates/verifier-nodes are exactly that shape; the vocabulary here stays Compass-native.)

- **Post-ship loop machinery (all exit codes, never prose):** `postship-required` (header policy `post-ship-loop: on (clean N / cap M) | off — <reason>`; the contract skill writes it for every NEW shipping build; header-less legacy contracts are byte-identical N/A) · `postship-signal` (the loop REFUSES to run without an external verifier — RECON-CMD, declared routes, `post-ship-check:` or `observation-channel:` lines; self-critique alone is never graded) · `loop-round` (a round cannot register without: a receipt carrying real command→output evidence; on-disk observation — PNG magic-bytes ≥20KB for web, or a digest whose first line byte-matches the declared command; a ledger agreeing with the verdict via the new `ps_open_rows`; a fresh redeploy between MATERIAL rounds; moving code — no-progress + A,B,A,B ping-pong + nogit-stall detection; and, in `--auto`, the budget bump OWNED by the gate itself) · `loop-converged` (header-N consecutive clean; `user-accepted: ship-as-is` cap-escape with SET semantics — a finding opened after acceptance voids it) · **G-O1 in `lifecycle-audit`**: SHIPPED requires `loop-converged` exit 0 when the loop is required.
- **`coldgo-gate` — the 2×cold-GO design gate:** 2 consecutive cold-critic GOs on the IDENTICAL tree sha == current HEAD (any commit between or after resets), checked clean-tree boxes, `cold-critic: on` written for every new web contract; gated-only `HUMAN-GO · "<quote>"` fallback when declared. Wired into build's final web verify + review-build [C].
- **`auto-suspend` / `auto-resume` — the interactive-driver lever**, born from a live incident during this build's own review: the Stop-hook self-spawn displaced the interactive driver mid-review, ran a shallow 1-agent pass, and declared convergence; the only counter was hand-deleting `.auto-mode`, which round 2 then proved disarms the loop's own budget metering. `auto-suspend` creates `.auto-suspended` ALONGSIDE `.auto-mode` (metering + the no-fabricated-human-eyes refusals stay armed), the spawn guard sits inside `_auto_spawn_maybe` (both entry points), chain events extend `AUTO_EVENTS`/`check-session-chain`, and `auto-resume` demands declared budget ceilings.
- **`compass.recon.sh` — the reconciliation gold got teeth:** per-suite last-line-anchored count extraction (cross-matching the two suites' tallies is structurally impossible), pinned baselines (selftest ≥118, smoke ≥60 — a build that deletes tests cannot reconcile), and a PINNED literal INV-group list authored from the plan, never derived from the suites it runs.
- **Three live engine bugs fixed (one class):** an `exit` inside a `with_lock` critical section skips the RETURN-trap release and leaks the mutex — BUG-1 `cmd_gate_clear` executed `/usr/bin/ld` via a stray word and never released the gate-lock; BUG-2 `fire-g1`/`fire-g2` died inside the lock BY DESIGN, leaking on every fire; BUG-3 `budget-check` died inside the lock at the ceiling. All three found by dogfooding THIS build's own gates; fixed die-outside with byte-identical messages + 12 regressions (Checkpoint A commit, separately revertible).
- **Grounding rules baked in:** critics are fresh in-session subagents seeing ONLY the contract + the round's evidence (never builder reasoning); HUMAN-OBSERVED/HUMAN-GO are gated-mode-only; auth via env-vars only; every refusal across the new gates prints a pinned `refuse: <code>` so two defects can never satisfy each other's test.
- Suites grow 118→225 selftest / 60→72 smoke; GATE block byte-identity (8 consumers) intact; headerless pre-v0.12 builds behave byte-for-byte as v0.11.0 (INV-BC). Built by Compass on Compass — contract v3a locked after 2 adversarial rounds + a user-ordered verify pass (35 root defects folded); plan v5 locked after 2 rounds + independent verify + micro-verify (26+22+5 material folded); the full ledger lives in the build folder.

## [0.11.0] — 2026-06-23

**`--auto` is now genuinely autonomous and genuinely triggerable.** Two gaps found by running v0.10 `--auto` on a live build are fixed:

- **The self-spawn now fires at EVERY stage, not just build.** In v0.10 the cross-session auto-spawn sat *after* the `is_mid_build` gate in `cmd_stop_guard`, so a session stopping at contract/plan/review fell back to a manual hand-off instead of self-continuing. The `.auto-mode` branch now runs *before* that gate, guarded by a new `is_stage_continuable` (real pending work, not terminal/idle, no gate-lock) so it never spawns on a done/idle build. Gated mode (no `.auto-mode`) is byte-for-byte unchanged (INV-BC).
- **Two explicit triggers.** `compass.sh auto-start <dir> [--wall/--sessions/--stages]` is a single command (precheck + budget-init + auto-init); and `/compass:start` (no flag) now asks **Gated or Autonomous?** up front. No more reading prose to hand-wire it.
- **G1 is a real gate.** The upfront approval now takes a gate-lock (`fire-g1`) like G2, so a self-spawn can never bypass the one human checkpoint; `gate-clear` releases it on approval.
- **Honest degrade.** The self-spawn launches `nohup claude -p "/compass:resume <slug> --auto"`; a liveness probe records `spawn-failed` and stops cleanly if the launcher dies — never a silent or faked continuation.
- **The safety teeth (INV-HALT) — proven across REAL separate processes.** The runaway ceiling (wall + max-sessions + max-stages) is proven to bind across genuinely separate OS processes re-entering the budget lock — a recursive-shell self-spawn chain self-propagates and the (cap+1)-th spawn is refused; 5 concurrent real spawns with one slot yield exactly one winner, no deadlock, in <10s. **Safety is decoupled from real-`claude` availability** — the chain cannot exceed the budget regardless of what the spawn launches. This is the explicit guard against the 1.16B-token autonomous-loop failure mode.
- New `compass.sh` subcommands: `auto-start`, `fire-g1`, `gate-clear`, `stage-continuable`. Built **autonomously by Compass on Compass** (`--auto`, dogfooded) under a measurable budget; its own Review-1 caught that the in-process runaway proof had to become a real-separate-process proof, and that G1 needed its own lock — both fixed before code. selftest 99→118, smoke 56.

## [0.10.0] — 2026-06-22

**Opt-in `--auto` autonomous loop.** Compass can now run the full lifecycle without the per-hop human gate, stopping for a human at only **two** points — grounded in an audit of 38 past Compass/CRM builds which found the human gate changed direction in ~45% of builds but only ever at (A) taste/product/strategy/security calls and (B) "ship despite a failed/infeasible invariant", while *all* mechanical correctness was already caught by the autonomous adversarial reviews. So `--auto` keeps exactly those two gates and auto-advances the rest. Default (no flag) behavior is **unchanged** (INV-1) — every existing gate still fires.

- **Two human gates only:** **G1** (one upfront approval of contract + design/product intent, right after the contract receipt) and **G2** (event-triggered — fires on an INVARIANT failure, a review capping un-converged, the budget ceiling, or a ship/prod-verify failure; writes a `gate-wait-G2` banner and STOPs, never auto-resolves/spawns/hangs; after `g2_fires` ≥ 3 the "keep-trying" option is withdrawn). Everything else auto-advances via `compass.sh can-advance`.
- **Mandatory MEASURABLE budget** (Claude Code doesn't expose per-session tokens to a shell, so tokens are *not* the limit): a composite ceiling of **wall-clock seconds + max-sessions + max-stages** (defaults 3600s / 6 / 40), enforced cumulatively across sessions, checked at every stage boundary. `--auto` refuses to start without one (INV-3). This is the runaway guard for the 1.16B-token failure class.
- **Autonomous cross-session continuation:** when context runs low mid-build, the Stop hook auto-spawns a fresh `claude` running `/compass:resume <slug> --auto` from on-disk state and lets the old session exit — guarded by single-flight (INV-5), no-gate-bypass (INV-6), and a crash-safe session cap incremented *before* spawn (INV-7). No human needed for continuation.
- **Honest auto-close:** in `--auto`, review-build records `auto-closed: two clean adversarial rounds + all INVARIANTs green` (never a faked human signature); `lifecycle-audit` G-L2 now accepts that marker. Ship still runs its FULL real verification; any failure fires G2.
- **`--auto` is mutually exclusive with `--unattended`** (INV-8). State files are line-oriented (`budget.env`, pipe-delimited `session-chain.log`) — no JSON, since the engine is POSIX shell. New `compass.sh` subcommands: `auto-precheck`, `auto-init`, `budget-init`, `budget-check`, `check-session-chain`, `fire-g2`, `auto-spawn`, `can-advance`; new `scripts/spawn-smoke.sh` (Phase-0 feasibility gate).
- **Built by running Compass on Compass** (contract → 2 reviews → plan → build). The reviews earned their keep again: review-contract caught that a token budget is unmeasurable from a shell (→ measurable composite) and that auto-close would be blocked by the existing `lifecycle-audit` sign-off grep; review-plan caught that JSON can't be parsed in POSIX shell (→ line-oriented) and that the 1h ceiling wouldn't actually bind without a per-stage call-site. 23 new selftest assertions (89 total) + 5 new smoke checks.

## [0.9.1] — 2026-06-22

Two hygiene fixes so Compass matches its own documented design. **(1) Every lifecycle stage is now reachable as a namespaced `/compass:<stage>` command.** Until now only `start`/`resume`/`status` were `commands/` (namespaced `/compass:start`); the 7 stages were `skills/` only, which on the installed Claude Code surface as bare `/build`, `/plan`, … — so the `/compass:contract … /compass:ship` invocations `start.md` promised did not resolve. Added thin wrapper commands `commands/{contract,review-contract,plan,review-plan,build,review-build,ship}.md`, each delegating to its skill. The bare skill names still work (and still auto-trigger on natural language); the wrapper just adds the namespaced entry. (On a future Claude Code where plugin skills namespace, the wrapper is harmlessly shadowed and the skill wins.)

**(2) The 4-button next-step gate now fires on every entry path.** Previously the gate lived only in `start.md`; the 7 stage skills ended with a text-only "suggest `compass:<next>`; don't invoke it" and showed no picker when a stage was run standalone or via the namespaced command. The gate is now defined once in `shared/gate.md` (the canonical source) and inlined **verbatim** into all 7 skills + `start.md`. A new smoke assertion fails the build if any copy drifts, so the gate can't silently diverge across entry paths. The gate is **owned by each stage's skill** — `start.md` no longer presents a second gate (no double-gate). It is 4 buttons (Approve / Revise / Amend / Pause), since AskUserQuestion caps at 4; "Show full artifact" is offered via Other.

- Built with Compass itself. **review-contract** caught that `shared/` files are not auto-loaded into a skill's context (the gate had to be inlined, not referenced) and that the gate could not be 5 options. **review-plan** caught a double-gate under `/compass:start` and that the old text-only tail had to be removed, not merely supplemented — both fixed before build. Smoke grows to **51 assertions** (INV-1 commands+descriptions, INV-2 every stage gates + old tail gone, INV-3 canonical 4-button source, INV-4 wrappers delegate with no double-gate, INV-7 gate block byte-identical across 7 skills + start.md, with a non-empty guard against a vacuous match).

## [0.9.0] — 2026-06-19

The v0.8 Stop hook fixed *when* to block but not *whom*: it scanned the whole project and blocked **every** session if **any** build was mid-flight. Working in several terminals on one project meant an unrelated window (a prod investigation, a different build) got blocked by a build it had nothing to do with — and the nag fired every turn. v0.9 makes the guard **window/session-scoped**: a build is owned by the session id of the terminal running it, and the Stop hook blocks **only that session**, only while it's truly mid-build. Every other session — unrelated work, another build, another project — stays quiet.

- **Session-scoped Stop hook (`compass.sh own` + ownership in `stop-guard`)** — a build records its owner at `.locks/<slug>.owner = session=<id>` (written by the build skill at Step 0 *before the gate*, refreshed per step; by `resume` on re-entry; by `ship` at start — using `$CLAUDE_CODE_SESSION_ID`, the verified runtime var, **not** the docs' unset `$CLAUDE_SESSION_ID`). The hook reads the stopping session's `session_id` from stdin (field-anchored parse — never the uuid embedded in `transcript_path`) and **blocks iff the mid-build's owner equals it** (exact POSIX compare). An orphaned build (owning terminal closed) blocks **nobody** until someone resumes it and re-binds. Cross-project is isolated by the inline state-root. The v0.7/0.8 anti-abandonment teeth are preserved exactly — the owning session, mid-build, still blocks.
- **Crash-proof + loop-safe** — every read guarded under `set -euo pipefail` (a Stop hook never crashes a session, always fail-open `{}`/exit 0). Loop-safety: `stop_hook_active` stays the primary anti-deadlock; a `session|slug|step-counter` fingerprint backstop (written under a fail-open inline mutex) blocks at most once per build-step, so cosmetic churn can't re-loop and a real step advance re-arms.
- **Ship single-flight + contention ordering** — `ship-claim`/`ship-release`/`ship-contenders`. The ship skill claims a project-wide lock **first and unconditionally** (only one build merges at a time) and releases on **every** exit — success, yield, or hard-stop — so a failed ship never deadlocks future ships; the lock self-heals (steals a SHIPPED/ROLLED-BACK or >2h-stale holder, **never** a CLOSED live-mid-ship holder). When two builds are both ship-ready, ship asks **which goes first**; the loser releases and yields, and on resume the existing `post-merge-check`/`merged-recon` re-check it against the advanced base (for library builds the merged-tree proof is the test suite). Contender status resolves progress-md-first (a stale INDEX can't miss/invent one).
- Reproduction self-test grows to **65 assertions**: session isolation S1–S17 (owner match/foreign/orphan/paused/two-builds/substring/fingerprint-dedup+re-arm/empty-refuse/transcript-uuid/env-fallback/trailing-ws), cross-project S14 (two real repos + converse), ship coordination P1–P7 (single-flight, no-steal-on-CLOSED, self-heal, executable loser-re-check P5). Built with Compass itself; review-plan's adversarial fan-out caught the wrong env-var name, an owner-bind ordering gap that would have left a resumed build unguarded, a ship-lock that deadlocked on a failed ship, and an over-claimed loop-safety — all before any code.

## [0.8.0] — 2026-06-19

Born from the same disease as v0.7 ("prose drifts, gates don't"), one layer up: in the `pg-method-rates` outage three pages 500'd on prod because a route was *named as at-risk* in the plan and then **verified with `tsc` instead of being loaded**. Compass now makes every page/route in a build's blast radius **prove it actually loads** — before and after deploy.

- **Blast-radius page-load coverage (`compass.sh route-coverage`)** — the plan declares a machine-readable `## Affected routes` list (the canonical set; **declaration is mandatory** when page/route files change or facet=web — you can't game it by omitting the block, G-R0), and **every declared route must carry a recorded canonical page-load proof** (`- [x] route <path>: <cmd> → 200 <assert>`) or the gate fails (G-R1). Typecheck-only verify for a page/route step is rejected; a `tsc`-only step is surfaced as an advisory (G-R2). Route matching is `grep -F` literal **anchored on the trailing colon** — a Next.js `[param]` segment isn't read as a regex char-class, and a prefix route (`/accounts`) can't steal a longer route's proof (`/accounts/new`). Honest limit stated: the script checks the *record*; **review-build now independently RE-LOADS each route**, and ship is the backstop.
- **Mandatory post-deploy route smoke (hard stop)** — `lifecycle-audit … SHIPPED` requires a **prod GET-200 proof per declared route** in the ship receipt; unreachable prod / any route not 200 keeps the build CLOSED, never a soft-pass (same teeth as v0.7's prod-verify). No-op for builds with no declared routes (back-compatible).
- **Stop-hook gate-quiet fix** — the v0.7.0 `stop-guard` blocked on *any* non-terminal build, which the harness paints red as "Stop hook error" even at a normal user gate (and nagged across projects for any stale/parked build). It now blocks **only on true mid-build abandonment** — a build step genuinely in progress (`build · … · IN-PROGRESS · step k/n`, or `plan.md` with a checked *and* an unchecked step) — and is **quiet at every clean checkpoint**: gates, `*-LOCKED`, `CONVERGED`, `CLOSED`-awaiting-ship, mid-contract/plan/review. The v0.7 anti-abandonment teeth are preserved exactly where work can be left half-applied. `is_mid_build` is crash-proof under `set -euo pipefail` (a Stop hook must never crash the session).
- Reproduction self-test grows to **INV-R0..R5** (33 assertions): the pg-method-rates shape (declared-but-unloaded routes, `[param]` + prefix-route literal-match, typecheck-only step, ship route-smoke red/green) and the stop-guard gate-quiet behavior (gate→quiet, mid-build→block, ambiguity guard, no-crash). Built with Compass itself; review-plan caught a prefix-route false-match and a Stop-hook crash-on-every-stop before build.

## [0.7.1] — 2026-06-18

Fixed — the `deploy: out-of-scope` waiver detection (in `lifecycle-audit` and `stop-guard`) was an **unanchored** grep, so it matched the phrase anywhere in the contract — including prose that merely *describes* the waiver. That let the "ship is mandatory" guarantee be bypassed by a contract that only mentions the phrase. Now anchored to a real field line (`^[-* ]*deploy: out-of-scope`); prose/backtick mentions no longer count. Self-test gains an INV-5 prose-only case (18 assertions). Caught by v0.7.0's own ship audit printing a false "deploy waived" — dogfooding worked.

## [0.7.0] — 2026-06-18

Two failure modes promoted from prose to executable gates ("prose drifts, gates don't"). Born from a real prod outage: a Compass-built feature (`pg-method-rates`) hand-applied a schema change to the dev DB via `prisma db execute` — no migration ever landed in the deploy's canonical folder — and ship was marked SHIPPED with prod-verify left unchecked. The lifecycle showed all green while prod broke.

- **Migration-delivery gate (`compass.sh migration-gate`)** — for `schema-touching: yes` builds: a real migration must exist in the deploy's **canonical** dir (Prisma: `prisma/schema/migrations` when `prisma/schema/` exists, else `prisma/migrations`), `db execute`/hand-apply can't substitute, a **stray migration in a non-canonical dir is caught** (the exact incident class), and a **fresh-DB apply must reproduce the schema (STRICT — no waiver)**. Wired as a hard gate into build, review-build, and ship.
- **Ship prod-verify is a HARD STOP** — unreachable prod = the build stays CLOSED, never `PARTIAL`/"deferred"/SHIPPED-with-an-unchecked-box.
- **Lifecycle enforced every time, always** — `compass.sh lifecycle-audit` (full-chain receipt + terminal-status guard, wired into `close`/ship) + a new **`Stop` hook** (`compass.sh stop-guard`) that blocks the agent from going quiet, skipping a gate, or forgetting ship while a build is mid-lifecycle (honors `stop_hook_active` to avoid deadlock). **Ship is now mandatory** unless the contract carries `deploy: out-of-scope — <reason>`. `close --abandon` cancels an incomplete build.
- Reproduction self-test `compass.selftest.sh` (INV-1..INV-7) encodes both real failures and proves the new gates catch them. Built with Compass itself; its review caught the Stop-hook deadlock risk, the `close`-traps-abandon regression, and a private-data-in-fixtures leak before build.

## [0.6.0] — 2026-06-17

Elegant parallel builds. Worktrees move out of sight, and parallel builds on one repo become visible and merge-aware. Born from a real mess — three confusingly-similar sibling folders (`GQ Business CRM`, `GQ Business CRM.compass/`, `GQ-Business-CRM-obs`) next to the project, plus un-GC'd worktrees and hand-rolled ones. Built with Compass itself; the reviews caught two that would have re-created the mess (the pre-commit guard silently breaking, and `close` deleting uncommitted work — the v0.5.0 incident).

### Added
- **Centralized worktree home.** Build worktrees now live in `~/.compass/worktrees/<project-id>/<slug>` (project-id = `<basename>-<cksum>`, collision-safe), out of the project's parent — so you only ever see the project folder next to your other projects, never a `.compass` or `-obs` sibling. Overridable via `COMPASS_WORKTREE_HOME`. State stays in-project (`.claude/builds/`).
- **`compass.sh builds`** — a live table of every in-flight build on the repo (slug · status · branch · worktree). `/compass:status` shows it when more than one build is active.
- **`compass.sh post-merge-check <slug>`** — the merge-consequence gate. When a sibling merges first, this checks the build against **`origin/<base>` (after fetch — never local `main`)**: is the base advanced? did the merge touch this build's claimed files (blast radius)? If so it STOPs and requires integrating the new base + re-verifying — **flagged during build, a hard block before ship.** Never auto-rebases (conflicts need human eyes). The base SHA is recorded at worktree creation as the diff anchor.
- **`compass.sh doctor [--migrate]`** — audits every worktree (managed vs stray, status, dirty, merged), sweeps clean terminals, and `--migrate` relocates clean ad-hoc siblings into the home via `git worktree move`. **Never touches dirty/unmerged — only flags them.**

### Changed
- **Dirty-safe removal everywhere (the v0.5.0 incident fix).** `gc` and `close` now use one shared **non-force** remove — a worktree with uncommitted work is LEFT in place and flagged, never force-deleted. (v0.5.0's `close` force-removed a dirty worktree and lost 55 files; that can't happen now.) `gc` also prunes orphans and scans the centralized home.
- **Worktree identity by branch, not path.** `cwd_slug` (used by the pre-commit guard, resume, and assert-worktree, via the new `compass.sh cwd-slug`) derives the slug from the `compass/<slug>` branch — location-independent, so the contamination guard keeps working after worktrees move. **Always create worktrees via `compass.sh worktree` — never hand-roll `git worktree add`.**

**Why:** parallel builds were technically isolated but operationally messy — siblings cluttered the project's parent, GC missed shipped worktrees, and a first-merge could silently invalidate the others. v0.6.0 makes the worktrees invisible, the parallel builds identifiable, and a merge's consequences a hard gate. Smoke: 28 → 40 assertions, including the merge gate against a real bare remote and the dirty-safe close.

## [0.5.0] — 2026-06-16

Design fidelity becomes a brutal, non-negotiable gate, and post-build verification stops being ceremonial. The most important behavioral change since inception: it redefines what "verified" and "done" mean. Built with Compass itself (contract → review → plan → review → build → review → ship); the reviews caught the ceremonial trap twice before it shipped (see below).

### Added
- **The mockup is the SPEC, not inspiration.** When a mockup exists, the contract now extracts an **itemized, binding Design Spec** (exact tokens, layout, every control, every state). No mockup → the contract must name a design standard (e.g. Stripe-level `frontend-design`); "use your judgment" is rejected. This is the only way to make "no drift" verifiable.
- **A brutal, non-negotiable design-fidelity gate** in review-build (and per-step in build): render the built UI vs the mockup at every viewport + state, log each difference to a `design-ledger.md`, and **loop until zero open rows — one drift = FAIL.** The bar is **identical** whether the mockup is an HTML file or a flat image; only the technique differs (HTML adds `design-style-diff` token checks + computed-CSS; an image uses disciplined element-by-element side-by-side reading).
- **Real script teeth (not prose):** four new deterministic `compass.sh` subcommands — `design-drift-gate` (blocks while any drift row is open; a design-scoped build with a missing/empty ledger FAILS — review-not-done ≠ clean), `converge-gate` (won't pass unless BOTH the correctness and design ledgers are clean), `design-style-diff` (a real token diff over real artifacts), and `status` (the where-am-I surface). Covered by new smoke assertions, including a **catch-the-drift fixture** that proves the gate FLAGS a real drift and PASSES the faithful build (both directions, non-circular).
- **`/compass:status`** — prints build · stage · step k/n · last passed receipt · the single next action + command, on demand.

### Changed
- **Post-build verify is no longer ceremonial.** review-build now **independently renders the live product on real/representative data** and adversarially reads the actual values + pixels — it does **not** re-run the build's own checks. Every check must be **falsifiable** (able to fail if broken); tautological or screenshot-only "looks right" checks are deleted, not counted. Convergence requires `converge-gate` (both ledgers clean), not just "no new findings."
- **Clean stage transitions + elegant hand-off.** Every stage ends with a one-line footer (what passed ✓ · next stage · exact command) — Compass never goes quiet mid-build. When a new terminal is needed, it prints exactly one clean, copy-paste-ready block (`cd "<root>" && claude`), nothing interleaved.

**Why:** real builds shipped correct-but-ugly UIs and "all-green but reader-useless" pages because every hard review checked logic and safety while design fidelity was a soft, one-shot screenshot eyeball — and post-build verify mostly re-ran the build's own checks. v0.5.0 makes design a first-class, looping, evidence-backed gate and forces verify to look at the live thing on real data. Fittingly, building it with Compass surfaced the same failure mode twice (invariants asserted by grepping prose; a missing ledger counting as "pass") — both caught and closed by the contract and plan reviews before any code shipped.

## [0.4.0] — 2026-06-09

Parallel builds, learned from running two Compass builds at once on a live CRM (one of them overnight, unattended). The two shared one working directory, so one build's `git add -A` swept in the other's files and a manual de-commingle was needed at the end. This release makes N builds in one repo safe — and the design was hardened by an 8-stream adversarial review (73 raw → 22 findings, all folded in) before any code was written.

### Added
- **One git worktree per build (the keystone).** Each parallel build gets its own working folder + branch backed by the same `.git`, so no two builds share a checkout. State stays canonical in the *main* checkout's `.claude/builds` and is reached from any worktree via the new `compass.sh state-root` (no symlink, no migration). Single-build runs are unchanged.
- **The teeth, extended.** New `compass.sh` subcommands, all deterministic and exit-coded: `state-root`, `active-builds`, `worktree`, `promote`, `worktree-rm`, `assert-worktree`, `claim`, `check-overlap`, `check-db-isolation`, `install-guard`, `audit-staged`, `merged-recon`, `gc`. Covered by a committed smoke test (`compass.smoke.sh`, 16 assertions) that runs in a path with spaces and parentheses.
- **A single slug-agnostic pre-commit guard** that blocks any staged file outside the active build's claimed file list — inside a worktree it enforces that build's claim; from the main checkout it refuses to commit any in-flight build's claimed file. This is what actually stops the `git add -A` contamination, including on unattended overnight runs.
- **Enforced cross-build overlap.** `claim` (file-level, expanded via `git ls-files` in the worktree) + `check-overlap` turn the old prose "coordinate additively" warning into a hard gate; shared files surface as an explicit, acknowledged overlap rather than a silent clobber. Builds claim `package-lock.json` and their migration dir so lockfile/migration conflicts surface early, not at merge.
- **DB-isolation gate.** Worktrees isolate files, not the database — so a contract may declare `isolation.db_provision`/`db_teardown` (a per-worktree `DATABASE_URL`), and `check-db-isolation` REFUSES a schema-touching parallel build that has no isolation (concurrent migrations on one dev DB corrupt it).
- **Post-merge reconciliation gate.** `merged-recon` re-runs both builds' recorded `RECON-CMD` on the *merged* tree before the second ships — two independently-green branches don't prove the union is green.

### Changed
- **Resume no longer trusts the global `CURRENT`.** It derives the build from the worktree (cwd/branch) and, in the main checkout, refuses to guess when more than one build is active — the exact ambiguity that resumed the wrong build before. `CURRENT` is demoted to a non-authoritative hint.
- **Build, ship, contract, start** skills now wire the gates above (worktree assertion, overlap/DB checks at build start, scoped commits with no `git add -A` / `--no-verify`, the merge gate in ship, the isolation block in contract).

**Why:** the parallel run shipped both features, but the shared checkout cost a manual cleanup and the riskiest moment was the unattended run committing with `git add -A`. The adversarial review found the naive "just use worktrees" design left DB corruption, lockfile merges, and a bypassable guard unsolved; v0.4.0 closes those before turn-on.

## [0.3.0] — 2026-06-08

Two improvements learned from the first real end-to-end run (a production feature on a live CRM, where the reviews caught a self-introduced IDOR and a shipped-incomplete data-redaction fix).

### Changed
- **A fix is treated as new code and re-attacked before convergence.** review-build now requires the final clean round to be a genuine *verify-the-fixes* round: any round that applied a fix is not clean by definition, and the independent **Security/RBAC, Secret-leak, and Verification-audit agents re-spawn on every fix diff — regardless of which group the fix belonged to**. A "functional" fix routinely opens a security hole (e.g. a pagination fix that introduces an IDOR); this no longer depends on the user asking for an extra round.
- **Coverage, not sample — fixes are checked against canonical definitions.** When a fix is defined relative to a canonical set (sensitive/commercial fields, roles, allowed values, redaction targets), review-build now requires the implementation to be **driven by the canonical source itself**, not a hand-maintained copy/regex that can drift, and the test to exercise the **full set**, not a hand-picked sample. A duplicated canonical set is a Major finding.

**Why:** on the first real run, a Round-4 fix passed its own test but had silently drifted from the canonical field list, leaving commercial data visible — caught only because a manual verify round was added. These changes make that catch automatic.

## [0.2.0] — 2026-06-07

### Added
- **Zero-drift-from-imagined-design as a first-class verification.** The contract now *requires* capturing the **design intent** for web builds (a mockup/screenshot path, reference URL, or precise described visual). At build and in review-build, the live UI is **screenshotted and read back against that captured intent**, naming any drift from what was imagined (layout, hierarchy, spacing, feel).

### Changed
- **The verify layer now uses two complementary UI checks instead of banning screenshots.** *Exact things* (a number, a hex, a spacing value) are still proven by exact assertions (DOM text / computed CSS) — never a screenshot. *Design-intent fidelity* is now proven by a **screenshot read-back vs the captured design**, because the gestalt "does it match what we imagined" is a judgment an exact assertion cannot make. Both are required for web builds.

**Why:** a feature should ship with zero drift from what was conceptualized during planning — including the design. Computed-CSS assertions catch a wrong token but cannot catch "this doesn't look like what we pictured." That holistic match needs a visual eyeball, anchored to a design intent captured up front.

## [0.1.0] — 2026-06-07

First public release. A contract-first build lifecycle for Claude Code, hardened over three independent adversarial review rounds.

### Added
- **Seven-stage lifecycle:** `contract → review-contract → plan → review-plan → build → review-build → ship`, with user-driven gates (Approve / Revise / Amend contract / Pause / Show) between every hop and a required human sign-off before close.
- **The contract as the invariant** — every later stage is checked against the locked spec; any deviation stops and asks.
- **Real enforcement, not prose** (`scripts/compass.sh`): a deterministic gate that exits non-zero when the prior stage's receipt is absent, FAIL, has an unchecked box, or was superseded. Reconciliation and secret-scan are deterministic `PASS/FAIL` gates that block close. Escalation supersedes downstream receipts so re-reviews actually re-run.
- **Reconciliation to an independent gold figure** — the target must be a published/audited number, never the build's own query agreeing with itself; runs duplicate/fan-out/source-table bug-class checks.
- **Verify ladder** — cheapest real proof first, by project facet (`web` / `pipeline` / `library`, composable). Asserts DOM text + computed CSS for UI; prod stays read-only; Playwright over Chrome MCP (no cross-project lock).
- **Adversarial reviews** that fan out as ~6 agents, converge on recorded evidence (one clean pass for the light review, two consecutive clean rounds for the full reviews), and escalate up a level when stuck instead of faking done.
- **File-based, resumable state** in `.claude/builds/<slug>/` with clean cross-session handoff (`/compass:resume`).

### Notes
- Built and pressure-tested via three rounds of independent adversarial review (26 + 17 + 16 findings, all resolved), then a token-efficiency pass. See `docs/REVIEW-FINDINGS.md`.

[0.1.0]: https://github.com/Rishi4792/compass/releases/tag/v0.1.0
