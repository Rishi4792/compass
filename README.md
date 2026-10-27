# 🧭 Compass 1.0

**Describe what you want. Read one page. Approve four times. Get a product that does what the page says, proven live.**

Compass is one command inside [Claude Code](https://claude.com/claude-code). It interviews you like a product head, draws an Idea page you can read in a minute, writes the engineering plan the best teams write, builds part by part, tries to break its own work before you see it, puts it live, and writes the real numbers back onto your page.

## First time, step by step

1. **Get Claude Code** from [claude.com/claude-code](https://claude.com/claude-code). It is the app Compass lives in. Follow its own install page.
2. **Get Node**, the one free helper Compass needs, from [nodejs.org](https://nodejs.org). One download; click Next until it finishes. If you skip this, Compass tells you in one line and waits.
3. **Open Claude Code in the folder of your project.** An empty folder is fine for a new idea. In the Claude Code desktop app, use its "Open folder" button. In a terminal: open the Terminal app, type `cd ` (with a space), drag your folder into the window, press Enter, then type `claude` and press Enter.
4. **Paste these two lines into its chat box**, one at a time, and press Enter after each. Claude Code needs both. Besides opening Claude Code, these two lines and `/compass` are all you will ever type.
   ```
   /plugin marketplace add Rishi4792/compass
   /plugin install compass@compass
   ```
5. **Type `/compass`** and press Enter. That is the whole manual. From here you only answer questions.

## Use

Type `/compass`. It tells you where your build is in one plain line and asks you one question only when the answer is yours.

Shaping the idea takes about a dozen short questions (12 at most), each with choices to pick from. After that you approve four things, plus the screens if there are any, and settle the rare question the plan cannot answer alone:

1. **Approve the Idea page** — a picture per part, few words, a number on every promise.
2. **Approve the plan** — one screen: your parts in build order, the three biggest risks, and anything that needs your answer.
3. **Accept what was set aside** — anything the tests could not close, named in writing.
4. **Say yes to going live** — after the safety checks pass and the undo has been practised.

Everything else runs for you. You watch one live card: where the build is, one row per promise, every decision you made, and the one question that needs you, if any.

## What runs underneath, which you never read

- **Attacks, not review rounds.** Inside every stage, fresh reviewers try to make each promise false, choosing from Compass's catalogue of the 13 ways software fails. An attack ends `held` or `broke` with a reproduction. A break is fixed, becomes a permanent check, and is attacked once more. Two attempts, then you decide. No rounds, no findings lists, no tests the AI chose on its own.
- **Build to spec.** Nothing is built that the Idea page does not say. A change goes through "Change your mind" first, which re-plans one part and leaves the rest proven.
- **One record.** Status is computed from an append-only record of passed steps. No status file can disagree with another, because there is only one.
- **The look, judged once.** For visual parts you approve a real mock before code. After that the build is checked for conformance to it, element for element.

## For contributors

`node plugins/compass/scripts/check` runs the gate suite: one check per promise on the Idea page that has a step, plus every check born from a break. It also refuses a core over 10,000 words of instructions. Open [`plugins/compass/`](plugins/compass/) and read `skills/compass/SKILL.md` first; it is the one door.

Coming from 0.35: the seven stages, three review loops and 59 self-check scripts are gone; 1.0 is four stages and one script. A build started under 0.35 is finished with the old version: `git checkout v0.35.0` in a clone of this repo, then `claude --plugin-dir ./plugins/compass`.

MIT © Rishi Kapoor
