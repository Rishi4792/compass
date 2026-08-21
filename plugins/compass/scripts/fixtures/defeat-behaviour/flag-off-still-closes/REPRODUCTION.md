# flag-off-still-closes

**How it was found.** Contract §12 documents a kill switch — `COMPASS_V32_STRICT`, default ON,
one-command disable — and then constrains it: *"the flag may disable reporting gates, but never the
measurement the build is graded on, and closure is REFUSED while the flag is off."*

That constraint exists because round 2 of the contract review found the flag as first designed
returned EVERY new gate to an N/A-pass, **including the one that measures the gold**, so one
environment variable made every promise in the contract read green.

**The measurement that made this entry necessary.** Before it, `COMPASS_V32_STRICT` was read by
nothing at all — zero references across all nine v0.32 checks, except two comments saying it is
deliberately not read. So both halves of §12 were unbacked: the flag could not disable anything, and
nothing refused closure while it was off. A rule with no implementation on either side is a
paragraph.

**What must happen — both halves, both directions.**

*Closure:*
1. with the flag OFF, `compass.sh close` refuses **for the flag's own reason**, naming §12 and the
   `v32-strict=off` receipt stamp;
2. with the flag ON, that refusal does not appear — otherwise the guard is not a switch;
3. every spelling of off (`0`, `off`, `OFF`, `false`, `no`) refuses, or one of them is a silent
   bypass of the whole section;
4. `--abandon` is still allowed with the flag off. Cancelling a build claims nothing about it, and
   blocking the cancel would only strand it.

*Measurement:*
5. the reachability figures are byte-identical with the flag ON and OFF;
6. and no v0.32 measurement **reads** the flag in code at all — which is what makes "it cannot
   silence the measurement" a fact about the code rather than an intention.

**Why the flag is isolated by MESSAGE, not by exit code.** A first version of this case tried to use
a build that closes cleanly with the flag on, so the two exit codes could be compared. The stub
could not close for unrelated reasons, the control failed, and the case proved nothing. `close` has
other preconditions that refuse too — an exit code they already guarantee measures nothing about the
flag. This is the same vacuity class this build has now found ten times.
