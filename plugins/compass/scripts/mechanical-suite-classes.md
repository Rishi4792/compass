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

## How to add a class

1. Write the check, or extend the check that owns the nearest class.
2. **Prove it red on a throwaway copy before trusting it green.** Three rules for the awk-apostrophe
   trap each failed on correct code, and the first never fired at all — it would have shipped as an
   unproven check if nobody had tried to plant its red.
3. Decide MEASURES or REPORTS honestly. If a line scan cannot separate the defect from correct code,
   it REPORTS.
4. Add the row above, with the real defect it came from.
