# 🧭 Compass 1.0

**Describe what you want. Read one page. Say yes four times. Get a product that does what the page says, proven live.**

Compass is one command inside [Claude Code](https://claude.com/claude-code). It interviews you like a product head, draws an Idea page you can read in a minute, writes the engineering plan the best teams write, builds part by part, attacks its own work the way a red team would, deploys, and writes the real numbers back onto your page.

▶ [Watch the 59-second film](https://rishi4792.github.io/compass/)

## Install

```
/plugin marketplace add Rishi4792/compass
/plugin install compass@compass
```

Needs Claude Code and Node 18 or newer. Nothing else.

## Use

Type `/compass`. That is the whole manual.

It reads where your build is, prints one line, and asks one question. You are asked at most four times in a build:

1. **Approve the Idea page** — a picture per part, few words, a number on every promise.
2. **Approve the plan** — one screen: slices in order, the three biggest risks, any question for you.
3. **Accept the leftovers** — anything an attack could not close, named in writing.
4. **Confirm the deploy** — after pre-flight and a rehearsed undo.

Everything else runs for you. You watch one live card: where the build is, one row per promise, every decision you made, and the one question that needs you, if any.

## What runs underneath, which you never read

- **Attacks, not review rounds.** Inside every stage, fresh reviewers try to make each promise false, choosing from Compass's catalogue of the 13 ways software fails. An attack ends `held` or `broke` with a reproduction. A break is fixed, becomes a permanent check, and is attacked once more. Two attempts, then you decide. No rounds, no findings lists, no tests the AI chose on its own.
- **Build to spec.** Nothing is built that the Idea page does not say. A change goes through "Change your mind" first, which re-plans one part and leaves the rest proven.
- **One record.** Status is computed from an append-only record of passed steps. No status file can disagree with another, because there is only one.
- **The look, judged once.** For visual parts you approve a real mock before code. After that the build is checked for conformance to it, element for element.

## Coming from 0.35

The seven stages, three review loops and 59 self-check scripts are gone. 1.0 is four stages and one script. Builds started under 0.35 are shown as legacy and finished by pinning the old version: `git checkout v0.35.0` in a clone of this repo and load it with `claude --plugin-dir ./plugins/compass`.

## For contributors

`node plugins/compass/scripts/check` runs the gate suite: one check per promise on the Idea page that has a step, plus every check born from a break. It also refuses a core over 10,000 words of instructions. Open [`plugins/compass/`](plugins/compass/) and read `skills/compass/SKILL.md` first; it is the one door.

MIT © Rishi Kapoor
