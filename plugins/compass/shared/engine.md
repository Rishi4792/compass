# The engine — how a long build keeps moving

Loaded by the **build** and **start** stages. It governs how work is paced, not what is built.

## Why this file exists

Long builds die of politeness. The model finishes one step, writes a paragraph about it, and waits.
Compass's own `--auto` mode does exactly this — it says so in its own source: *"it finishes a step,
writes a paragraph and waits."* A build that stops every step is not autonomous; it is a build with
extra ceremony.

This file is the habit that fixes it. **It is doctrine, not a mechanism** — nothing here schedules
anything or restarts anything. See "What Compass deliberately does NOT ship" at the end, which is
the most important section on the page.

## The three habits

1. **Long turns.** Do a real batch of steps in one turn — five, ten, as many as genuinely fit. Run
   each step's verify before ticking its box. Do not end a turn to narrate progress; a one-line note
   between commands is enough. End a turn when the batch is done, when a blocker needs a person, or
   when the only work left is a background job.

2. **Detach slow work, never wait for it.** Anything expected to take more than two or three
   minutes — a test suite, a backfill, a render, an install — runs detached. Its completion wakes
   the session on its own, which is real event-driven pacing. Keep doing other steps while it runs.
   **Never sleep and poll.** A sleep loop burns the budget to learn something the job would have
   told you.

3. **State on disk, not in the conversation.** `progress.md` is the single source of truth, and it
   outranks memory of the conversation — context may have been compacted since the last turn. Write
   the ticked boxes, the next action, the blockers and the caps into it BEFORE ending a turn. Any
   fresh session must be able to read that file and resume exactly where the build stands.

## The five fences

Any loop that continues work without a person asking is dangerous, and these are not optional.

1. **Opt-in is explicit, per run.** Continue without asking only when a person has said so for THIS
   run. Never because a task "looks long".
2. **A stated cap.** A loop states its bound as a number before it starts. An unbounded loop is the
   failure mode that once burned **1.16 billion tokens** re-scheduling itself to "wait for CI".
3. **A stall detector.** If a turn ends with no change to `progress.md` — no step completed, no
   blocker newly recorded — that is a stall. Two in a row and the loop stops. Never continue "to
   check again later"; that is precisely how the runaway above happened.
4. **Never continue merely to wait.** Waiting is what detached jobs are for. If the only remaining
   work is a running job, end the turn.
5. **Stopping is the safe state.** Done, blocked, capped, stalled, or unsure of the state → stop and
   report. A stopped build costs one message to restart. A runaway costs a manual kill.

## What Compass deliberately does NOT ship, and why

**Compass ships the habits above. It does not ship a loop that restarts itself.**

The mechanism that makes a build continue with no human keystroke is a self-re-arming wakeup. It is
safe on the machine of someone who has opted into it, understands the fences, and can close the
window. It is not safe to hand to a stranger who installed a plugin.

Compass tried to make it safe with a counter that bounded the loop from inside the same process the
loop ran in. That counter was built three times, reviewed three times, and removed before release:
it counted per directory when a loop is per build, two sessions halved it, its stall detector could
not be made to fire, and **it had never once fired in the repository it was written in.** The
verdict was that it bought a bound on a loop a person can also stop by closing a window, and cost a
script running on every prompt in every project of anyone who installed it.

So the honest position, stated rather than implied:

- **Compass's `--auto` mode still stops after a step and waits.** This file does not change that.
- What it changes is that the stop is **legible**: the stage gate says in plain words that nothing
  will continue the build and you will need to say so.
- If you want a build to continue unattended, you arm that yourself, deliberately, per run. That
  keystroke is the fence — not an oversight, and not something a plugin should remove on your behalf.

An engine that is honest about where it stops is worth more than one that quietly runs on.
