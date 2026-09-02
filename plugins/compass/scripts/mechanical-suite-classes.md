# The registry — every defect class the cheap checks decide

**The promise this file keeps.** When an adversarial review finds a defect a script could have
found, that class is ADDED here and taught to the suite — it is never re-reviewed forever. Without
this file the suite is frozen at whatever classes the last release happened to produce, and the
build's central claim ("reviewers stop paying for the cheap half") quietly stops being true one
release later.

Each row: the class, which check owns it, and whether that check MEASURES (fails a run) or REPORTS
(prints and never fails). The split is not decoration — building these checks showed that most
classes have a judgment core, and a check that fires on correct work gets disabled within a week.

| class | owner | measures or reports | note |
| --- | --- | --- | --- |
| a version string stated in more than one manifest | dup-fact-check | MEASURES | v0.32's SELF-2: a clean clone was 686/1 because one manifest moved and an assertion did not |
| a gate with two dispatch arms | dup-fact-check | MEASURES | RA-3's shape: five status parsers where three were found |
| two declared stream lists in one skill | dup-fact-check | MEASURES | the gate reads the first and the rest rot |
| a pinned suite floor stated in several files | dup-fact-check | MEASURES | deliberate tripwires are allow-listed with a reason |
| a hardcoded path root beside a root variable | dup-fact-check | MEASURES | |
| an assertion whose two sides are both constants | vacuous-assert-check | MEASURES | unless it declares `N/A — <reason>`; 12 correct ones do |
| an assertion inside a loop whose source can be empty | vacuous-assert-check | REPORTS | whether it can be empty is a judgment |
| an assertion over the gitignored build path | vacuous-assert-check | REPORTS | correct on this tree in all 5 cases |
| a command with no caller anywhere | unwired-gate-check | MEASURES | found cockpit-gate and stage-end-gate, both built by v0.32 and never run |
| a check that declines when an outside directory is missing | unwired-gate-check | REPORTS | intent is a judgment; visibility is the guarantee |
| a space-joined path list | shell-trap-check | MEASURES | fatal in a repo whose own path has spaces |
| `grep -c` compared for equality | shell-trap-check | REPORTS | the first rule failed 40 correct lines |
| an unguarded read under `set -e` | shell-trap-check | REPORTS | whether it can fail at EOF is a judgment |
| an apostrophe closing a single-quoted awk program | shell-trap-check | REPORTS | three rules tried, all three failed on correct code |
| an unescaped variable inside a regex | shell-trap-check | not scanned | a judgment about the value, said rather than skipped |
| a doctrine file nothing reads | doctrine-wired-check | MEASURES | feynman.md sat unread for three releases |
| a delegation to a skill the plugin does not ship | doctrine-wired-check | MEASURES | `/compass:explain` pointed at nothing on every install but its author's |
| a shipped path that can restart itself unattended | self-arm-check | MEASURES | the one privilege never handed to an installer |
| a stated cap exceeded with no recorded decision | cap-enforce-check | MEASURES | a recorded raise naming who and when is allowed |
| text present on a page but not reachable by a reader | outside-in-reachable | MEASURES | measured from the rendered page, never from the generator's own account |
| unshipped commits piling up past the cap | incremental-check | MEASURES | v0.32 ran ~50 on one branch before shipping |
| a ternary whose two branches are identical | not yet owned | not scanned | v0.34: `h1 === want ? 'REPORT' : 'REPORT'` — the verdict could not depend on the comparison, so the check could not fail. See below |
| a counter that is incremented, printed, and never tested | not yet owned | not scanned | v0.34: an ERR total that let the whole mechanism be deleted while four suites stayed green |
| two gates deciding the same question from different signals | not yet owned | not scanned | v0.34: one gate read a text line while every other read a stamp file — the rule was silently off on 14 folders |
| a gate message naming a finding the gate did not make | not yet owned | not scanned | v0.33.5: `engine-gate` passed with "Skill found at ." because the path variable is empty when nothing is found. See below — this one is SAID, not scanned |

## Three more classes with no owner, all from v0.34, all the same family

**A ternary whose two branches are identical.** `h1 === want ? 'REPORT' : 'REPORT'` shipped inside
the check built to catch vacuous assertions. `vacuous-assert-check.sh` could not see it **because it
scans shell suite files and this was a `.mjs`** — the population, again, not the logic. It is
mechanically detectable in principle (an AST or even a careful regex can spot a conditional whose
arms are byte-identical) and nobody has written it.

**A counter that is incremented, printed, and never tested.** `err_pairs` was reported on every run
and read by nothing, so deleting the entire mechanism it counted left four suites green. The
scannable shape is narrow and real: a shell variable assigned with `$((x+1))` that never appears in
a `[ ]`, `test`, or `case`. Not written.

**Two gates deciding the same question from different signals.** Every gate on the contract seam
asks "is this a modern build?"; one asked a text line and the rest asked a stamp file. The one that
disagreed was silently inert on 14 of 21 folders. Detecting this needs a notion of "the same
question", which is judgment — but a weaker version is not: two gates on one seam reading two
different files to make a guard-first decision is a shape worth printing.

**All three were found by independent reviewers running the code, not by any script here.** They are
recorded rather than fixed because guard-first has not been done on any of them, and this build has
already demoted ten rules for firing on correct work.

## The one class recorded here with no owner

**A gate's message asserting a finding the gate did not make.** v0.33.5: `engine-gate`'s passing
line ended `Skill found at $skilldir.` unconditionally, and that variable is empty on every install
without the `long-build` skill — so the gate printed "Skill found at ." while passing. The verdict
was right; the sentence was not.

**Guard-first says a line scan cannot own this.** The nearest mechanical shape is "a variable
assigned from a command that may return empty, then interpolated into an `ok`/`die` message". Counted
on this tree it returns **~90 hits, and roughly nine in ten are noise**, because a line scan does not
track function scope: one `local s` in `status_line()` matches every later message in the file.
Separating the real cases needs scope tracking, which is a different tool than a grep.

`unwired-gate-check` counts whether a gate is *reached*. Nothing counts whether a gate's *words*
match what it found. That gap is stated here rather than left implied — the same treatment as the
unescaped-variable row above, and the reason the table has a "not scanned" column at all.

## How to add a class

1. Write the check, or extend the check that owns the nearest class.
2. **Prove it red on a throwaway copy before trusting it green.** Three rules for the awk-apostrophe
   trap each failed on correct code, and the first never fired at all — it would have shipped as an
   unproven check if nobody had tried to plant its red.
3. Decide MEASURES or REPORTS honestly. If a line scan cannot separate the defect from correct code,
   it REPORTS.
4. Add the row above, with the real defect it came from.

## `grep -q` at the end of a pipeline, under `pipefail` — a red that means nothing
**Found:** v0.34 review-build round 2, from a smoke run that went `1023 passed, 1 failed` and could not
be reproduced in 20 consecutive tries afterwards.

`grep -q` exits the moment it matches and closes the pipe beneath it. The upstream command is then
killed by SIGPIPE and exits 141, and `set -o pipefail` promotes that to the pipeline's status. The
assertion goes red while the property it tests is perfectly satisfied — and it does so only under
load, which is the worst possible timing, because that is when somebody is trying to ship.

**Why it is not owned by a script here:** deciding whether a given pipeline can race needs to know
whether the upstream writes more than a pipe buffer before the match, which is a runtime property.
A grep for the shape finds **20 occurrences in `compass.smoke.sh` alone**; one is fixed (v0.30 v11's
truncation assertion, which flattens to a file first). The rest are latent.

**What to do instead:** write the flattened output to a file and grep the file. It removes the race
without weakening the assertion by a single character. Do NOT reach for `|| true` — that is the
vacuous-assertion class wearing a different hat, and it switches the test off for good rather than
for a moment.

**Related:** a spuriously red gate is one somebody switches off, which is the same reasoning that
demoted five MEASURE rules to REPORT in this release. A false positive costs more than a miss.
