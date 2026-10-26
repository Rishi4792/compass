# Engineering Plan — compass-1-0 · v1 · drafted 2026-10-26

Status is never written here. It is computed from `receipts.md`. This file holds the plan and its decision log.

## 1. Goal and promises
Rebuild Compass as a 1.0 plugin for Claude Code with user experience at its core. The 31 promises are in `idea.md` (P1.1 to P8.3). Every step below carries the promise IDs it serves. Every promise has at least one step (checked in §13).

## 2. Non-goals
- No new product features beyond the Idea page's 8 parts.
- No change to the landing page, film or GTM assets under `docs/`.
- No support for hosts other than Claude Code.
- No fixed budget per slice and no time-extension prompts (Rishi, 26 Oct).
- No stalled-build alarm (Rishi declined it, 26 Oct).

## 3. Current state (read, not assumed)
Checked in this checkout: `compass/scripts/compass`, `compass/templates/card.html`.
- Repo `Rishi4792/compass`, public, MIT. Plugin at `plugins/compass/`. Marketplace manifest `.claude-plugin/marketplace.json` and plugin manifest `plugins/compass/.claude-plugin/plugin.json`, both version `0.35.0`. Latest tag `v0.35.0`. Install path in `README.md` lines 149 to 160: `/plugin marketplace add Rishi4792/compass` then `/plugin install compass@compass`.
- Surfaces today: 3 commands (`commands/go.md`, `resume.md`, `status.md`); 12 skills under `skills/` (7 stage skills, `start`, and 4 bundled design or visual skills: `rk-house-style`, `cinematic-hero`, `compass-visual`, `explain`); 6 shared doctrine files under `shared/` (feynman, engine, gate, enforcement, review-core, verify-ladder, walkthrough; 4,924 words).
- Machinery: `scripts/compass.sh` is 6,088 lines; 59 files under `scripts/`, most of them checks that test Compass itself. Instruction text totals 63,372 words.
- Hooks (`hooks/hooks.json`): `UserPromptSubmit` runs `hooks/orient-hook.sh`; `Stop` runs `compass.sh stop-guard`; `PreCompact` prints a reminder to update `progress.md`.
- Build state today lives in `.claude/builds/<slug>/` as `contract.md`, `plan.md`, `progress.md`, `receipts.md`, `review-ledger.md`, `intake.md`, plus rendered `brief.html` and `plan-map.html`. Status is typed into `progress.md`, `INDEX` and `CURRENT`, which is why copies disagree.
- Release process: `RELEASING.md` and `CHANGELOG.md` at the repo root; tags per version.
- Data-safety rules worth keeping live in `skills/plan/SKILL.md` §6 (RBAC matrix, race analysis, failure-mode analysis, cross-table invariants, PII line), `skills/build/SKILL.md` (migration gate, flag both states, reconcile as a script), `skills/ship/SKILL.md` steps 0.6 and 0.7 (restore point, config parity, cutover net with automatic rollback).

## 4. Proposed design
Six pieces, one command, one record.

```
/compass  ──►  scripts/compass state ──► one question ──► stage skill
                      ▲                                      │
                      │ receipts.md (append-only record)  ◄──┘  every passed step
                      │
            scripts/compass card ──► card.html (+ Artifact URL)   ◄── what the user watches
            scripts/compass idea-page ──► idea-page.html           ◄── what the user approves
```

- `commands/compass.md` — the one door. Computes state, prints the one status line, asks exactly one question, invokes a hidden stage skill.
- `skills/idea`, `skills/plan`, `skills/build`, `skills/deploy`, `skills/amend` — the stages, all `user-invocable: false`.
- `skills/attack` — the attack protocol used inside every stage: promises × failure catalogue → ranked attacks → fresh subagent per attack → `held` or `broke: <reproduction>` → fix → permanent check → one re-attack.
- `scripts/compass` — one dependency-free Node script with eight verbs: `state`, `card`, `idea-page`, `plan-card`, `attacks`, `receipt`, `gates`, `writeback`. Target under 900 lines.
- `shared/` — `failure-catalogue.md`, `plan-template.md`, `interview.md` (the 8 questions and their defaults), `kept-gates.md`.
- `templates/` — `idea-page.html`, `card.html`.
- Interfaces: `receipts.md` line grammar (`## RECEIPT — <stage> · <slug> · <result> · <ISO ts>` plus `- [x] <claim>: <cmd> → <output>` lines); `idea.md` promise grammar (`- P<part>.<n> <sentence> → <number>`); `attacks.md` row grammar (`| A<id> | P<id> | <class> | <attempt 1|2> | held|broke | <evidence> |`).

## 5. Alternatives considered
- **Patch v0.35 in place.** Rejected 26 Oct: the 63,372 words and 59 self-checks are the cost, not the asset.
- **Keep review as a stage with a smarter stopping rule.** Rejected 26 Oct: any rule that sorts findings still runs rounds and still asks the user about small points.
- **Reviews produce tests.** Rejected 26 Oct: AI writes too many immaterial tests; pace then depends on tests the AI chose.
- **A new plugin name.** Open question for Rishi (§20 Q1). Recommendation: same name and repo, version 1.0.0, so existing installs upgrade to the new door; `v0.35.0` stays installable by tag.
- **Status in a database or JSON file.** Rejected: a second source of truth. Status is a pure function of `receipts.md`.

## 6. Data changes
None. No database. The only stored data is Markdown and HTML under `.claude/builds/<slug>/`. Old builds keep their files; 1.0 reads only `receipts.md`, `idea.md`, `plan.md` and treats a folder without `idea.md` as a legacy build it can show but not continue.

## 7. Dependencies and blast radius
- Runtime: Claude Code plugin loader, `node` (already required by the 0.35 renderers), `bash`. No npm packages.
- Blast radius: every current user of `/compass:go`, `/compass:resume`, `/compass:status` loses those entries on upgrade. The `UserPromptSubmit` and `Stop` hooks are removed; the `SessionStart` hook replaces them with one status line. In-flight 0.35 builds are shown as legacy and finished with the 0.35 tag if needed.
- Host features used when present, with a fallback when absent: the Artifact tool (card and page URL; fallback: local HTML opened in the browser plus the terminal line); scheduling (end-of-watch check; fallback: a dated line on the card).

## 8. Walking skeleton (slice 1)
`/compass` → a 2-question interview → an Idea page with one part → a 1-slice plan → one build step with a receipt → deploy writes the live number back → card shows it. Touches every layer: command, script, state, card, page, all five stage skills as stubs. Proves the door, the record-only state, the card and the stage handoff before any breadth.

## 9. Slices and steps
Each step: what · promises served · the command that proves it · an estimate for information only. Checkboxes are the record of intent; the receipt is the proof.

### Slice 1 — Skeleton (every layer, thin)
- [ ] S1.1 Branch `v1`; new tree under `plugins/compass/`: `plugin.json` 1.0.0-dev, `commands/compass.md`, `scripts/compass`, stub `skills/{idea,plan,build,deploy,attack,amend}/SKILL.md` with `user-invocable: false`, `shared/`, `templates/`. → P1.1 · verify: `test -d plugins/compass/skills/compass && test ! -d plugins/compass/commands && echo door-ok` → door-ok · ≈ 1 h
- [ ] S1.2 `scripts/compass state <dir>`: stage, part k of n, each promise's state (planned, building, built, held, fixed, live), last receipt, next action, computed from `receipts.md` + `idea.md` + `plan.md` only. → P4.1, P7.4 · verify: `node plugins/compass/scripts/check --only P7.4` → 1 of 1 checks green · ≈ 2 h
- [ ] S1.3 `scripts/compass card <dir>`: renders `templates/card.html` from state: status line, one row per promise grouped by part, your question, decisions, leftovers; publishes to the Artifact URL when available, else writes the file and opens it. → P7.1, P7.3, P4.2 · verify: `node plugins/compass/scripts/check --only P7.1` → 1 of 1 checks green · ≈ 2 h
- [ ] S1.4 The door skill `skills/compass/SKILL.md` (a skill, not a command, so it answers to bare `/compass`): run `state`, print the status line, ask one question whose options depend on state, invoke the named stage skill. → P1.1, P1.2 · verify: `node plugins/compass/scripts/check --only P1.1` → 1 of 1 checks green · ≈ 1 h
- [ ] S1.5 `SessionStart` hook prints the status line of the active build and nothing else; old hooks removed from `hooks.json`. → P7.1 · verify: `grep -c SessionStart plugins/compass/hooks/hooks.json` → 1 · ≈ 30 min
- [ ] S1.6 Toy end to end on a scratch repo through the stubs. → P1.1, P1.3 · verify: `node plugins/compass/scripts/compass state plugins/compass/fixtures/live` → Live · · ≈ 2 h

### Slice 2 — The Idea stage (moved ahead of attacks, 26 Oct)
- [ ] S2.1 `shared/interview.md`: the 8 product questions (who · what hurts, last time it happened · what it does, part by part · what it should look like · what matters most · what is out · what would make you regret it · what done looks like as a number), each with a suggested answer rule and reason; "you decide" accepted everywhere; a banned-terms list for questions (rollback, flag, schema, migration, idempotent, env, RBAC, invariant). → P2.1, P2.2, P1.2 · verify: `node plugins/compass/scripts/check --only P2.2` → 1 of 1 checks green · ≈ 3 h
- [ ] S2.2 `scripts/compass idea-page <dir>` renders `templates/idea-page.html` from `idea.md`: a picture block per part from a small SVG library, promises with numbers; republished to the same URL after every answer. → P2.3 · verify: `node plugins/compass/scripts/check --only P2.3` → 1 of 1 checks green · ≈ 3 h
- [ ] S2.3 Sketch first for visual parts: a sketch block in the page before approval; none for non-visual parts. → P2.5 · verify: `node plugins/compass/scripts/check --only P2.5` → 1 of 1 checks green · ≈ 2 h
- [ ] S2.4 `spec.md` generated from `idea.md` plus a codebase scan: every rule line ends with `→ P<id>`; engineering facts recorded as assumptions, never asked. → P2.2 · verify: `node plugins/compass/scripts/compass spec-check plugins/compass/fixtures/idea-data` → every rule points at a promise · ≈ 2 h
- [ ] S2.5 Idea-stage attacks (S3.6) run once slice 3 lands; until then only the question: Approve / Change a part / Pause. → P2.4, P7.2 · verify: `grep -c "Approve (Recommended)" plugins/compass/shared/interview.md` → 1 · ≈ 1 h

### Slice 3 — Attacks engine (riskiest piece; after the Idea stage by Rishi's decision, 26 Oct)
- [ ] S3.1 `shared/failure-catalogue.md`: the 13 classes (wrong output, missing output, duplicate output, stale data, data lost, wrong person sees data, cannot undo, breaks on bad input, breaks on retry, breaks under load, fails silently, breaks what worked, does not match the approved picture). Each: definition, applies to which kinds of product, attack recipe, what a demonstrated break looks like, the permanent check shape. ≤ 1,500 words. → P5.3 · verify: `node plugins/compass/scripts/check --only P5.1` → 1 of 1 checks green · ≈ 2 h
- [ ] S3.2 `scripts/compass attacks <dir> <stage>`: promises × classes, drop classes that do not apply, rank by damage × likelihood (likelihood from the plan's touched paths), keep top 3 per promise, write `attacks.md`. → P5.1 · verify: `node plugins/compass/scripts/check --only P5.1` → 1 of 1 checks green · ≈ 3 h
- [ ] S3.3 `skills/attack/SKILL.md`: per attack, a fresh subagent whose only inputs are the promise, the recipe and the product; a time box; output must be exactly `held` or `broke: <reproduction>`; the main session re-runs the reproduction before it counts. → P5.1 · verify: `node plugins/compass/scripts/check --only P5.3` → 1 of 1 checks green · ≈ 3 h
- [ ] S3.4 Break → fix → permanent check in the repo's own test folder → one re-attack → close. → P5.2, P5.3 · verify: `node plugins/compass/scripts/check --only P4.3` → 1 of 1 checks green · ≈ 2 h
- [ ] S3.5 Still broken after attempt 2 → exactly one question to the user (fix by hand / cut the promise / accept in writing), recorded as a decision on the card. → P5.4 · verify: `node plugins/compass/scripts/check --only P4.1` → 1 of 1 checks green · ≈ 1 h
- [ ] S3.7 The look, built to spec: `shared/look-rubric.md` (10 items, 1–5 anchors, a bar per design level); for Premium visual parts the Idea stage produces a real HTML mock from the bundled design system; three fresh reviewers score the mock in isolation, the median decides against the bar; the person approves the mock; at build time the attack is binary conformance of the built screen to the approved mock. `scripts/compass shots` takes phone and desktop screenshots; `scripts/compass look-score` applies the bar. → P2.5, P5.1, P5.3 · verify: `node plugins/compass/scripts/check --only S3.7` → 1 of 1 checks green · ≈ 4 h
- [ ] S3.6 Stage-specific attack sets for idea (two parts contradict, a promise cannot be checked, something existing already does this, the stated user does not need this part) and plan (promise with no step, step with no promise, irreversible step without rollback, dependency that does not exist). Outcomes are edits to `idea.md` or `plan.md`, or one product question. → P5.1, P3.2 · verify: `node plugins/compass/scripts/compass attacks plugins/compass/fixtures/idea-data idea` → 4 attacks for stage idea · ≈ 2 h

### Slice 4 — The Plan stage
- [ ] S4.1 `shared/plan-template.md`: the 21 sections, plus `shared/kept-gates.md` mapping each v0.35 data-safety gate to its 1.0 home (migration dry-run on a copy, cross-table invariants, race analysis, failure modes and timeouts, RBAC matrix, PII line, secret scan, config parity, restore point, reconciliation to an independent figure). → P3.1 · verify: `grep -c "^## [0-9]*\. " plugins/compass/shared/plan-template.md` → 21 · ≈ 2 h
- [ ] S4.2 Scan first: the skill reads CLAUDE.md, CI, package scripts and touched files and cites paths; a lint rejects a "current state" section that cites no existing path. → P3.4 · verify: `node plugins/compass/scripts/check --only P3.2` → 1 of 1 checks green · ≈ 2 h
- [ ] S4.3 Traceability both ways: `scripts/compass gates <dir> --trace` fails on a step with no P-id or a promise with no step. → P3.2 · verify: `node plugins/compass/scripts/check --only P3.2` → 1 of 1 checks green · ≈ 1 h
- [ ] S4.4 Skeleton rule: slice 1 must be tagged `skeleton` and touch every layer named in §4 of the plan. → P3.3 · verify: `node plugins/compass/scripts/check --only P3.2` → 1 of 1 checks green · ≈ 1 h
- [ ] S4.5 `scripts/compass plan-card <dir>`: slices in order, the 3 biggest risks, questions for the user; shown in the terminal and on the card. → P3.1 · verify: `node plugins/compass/scripts/check --only P3.1` → 1 of 1 checks green · ≈ 2 h
- [ ] S4.6 Plan-stage attacks (S3.6) run; then one question: Approve / Revise / Pause. → P7.2 · verify: `grep -c "Approve and build (Recommended)" plugins/compass/skills/plan/SKILL.md` → 1 · ≈ 1 h

### Slice 5 — The Build stage
- [ ] S5.1 Step loop: build → prove by running (command + fresh output) → `scripts/compass receipt` → `card` re-render. → P4.2 · verify: `grep -c "Prove by running" plugins/compass/skills/build/SKILL.md` → 1 · ≈ 2 h
- [ ] S5.2 Resume from record only: kill the session mid-step; a new session's `/compass` resumes at the right step. → P4.1 · verify: `node plugins/compass/scripts/check --only P7.4` → 1 of 1 checks green · ≈ 2 h
- [ ] S5.3 Gate suite = promise checks + break checks only: `scripts/compass gates <dir>` lists them; nothing else runs at a part boundary. → P4.3 · verify: `node plugins/compass/scripts/check --only P4.3` → 1 of 1 checks green · ≈ 1 h
- [ ] S5.4 Step size: a step estimated over one session is split by rule before it starts. → P4.4 · verify: `node plugins/compass/scripts/check --only P4.4` → 1 of 1 checks green · ≈ 1 h
- [ ] S5.5 Part boundary: when a part's steps are proven, build attacks run on that part; rows move to held or fixed. → P5.1, P5.2 · verify: `node plugins/compass/scripts/check --only P4.1` → 1 of 1 checks green · ≈ 2 h
- [ ] S5.7 Drift stop: before each step the builder re-reads the spec lines it serves; a step that would change what the Idea page or spec says, even to improve it, stops and routes to `compass:amend`; never a silent improvement. → P4.5 · verify: `grep -q "drift stop" plugins/compass/skills/build/SKILL.md && echo drift-ok` → drift-ok · ≈ 2 h
- [ ] S5.6 Visual parts: the "does not match the approved picture" attack compares a screenshot to the sketch; one human cold look at the end of the build as a single question. → P2.5 · verify: `grep -q "picture-mismatch" plugins/compass/skills/attack/SKILL.md && echo conformance-ok` → conformance-ok · ≈ 2 h

### Slice 6 — Deploy
- [ ] S6.1 Pre-flight kept from 0.35: restore point, config-key parity, secret scan, deploy via the repo's own path. → P6.3 · verify: `node plugins/compass/scripts/check --only P6.3` → 1 of 1 checks green · ≈ 2 h
- [ ] S6.2 Canary then everyone with automatic rollback where the repo supports it; else a declared "all at once, because <reason>". → P6.3 · verify: `grep -q "all at once" plugins/compass/skills/deploy/SKILL.md && echo canary-rule-ok` → canary-rule-ok · ≈ 2 h
- [ ] S6.3 Kill switch proven without a redeploy. → P6.2 · verify: `grep -qi "kill switch" plugins/compass/skills/deploy/SKILL.md && echo switch-rule-ok` → switch-rule-ok · ≈ 1 h
- [ ] S6.4 `scripts/compass writeback <dir>`: runs each promise's check against the live system and republishes the Idea page with `live: <n> ✓/✗` per promise. → P6.1 · verify: `node plugins/compass/scripts/check --only P6.1` → 1 of 1 checks green · ≈ 2 h
- [ ] S6.5 Release note in plain words from promises and decisions; watch period with a named end date; Compass schedules the end-of-watch check where the host allows, else a dated card line. → P6.4 · verify: `node plugins/compass/scripts/check --only P6.1` → 1 of 1 checks green · ≈ 1 h

### Slice 7 — Change your mind
- [ ] S7.1 `skills/amend`: edit one part in `idea.md`; that part's spec lines and steps regenerate; other parts' files show no diff; only that part is attacked again. → P8.1, P8.2 · verify: `node plugins/compass/scripts/check --only P8.1` → 1 of 1 checks green · ≈ 3 h
- [ ] S7.2 The change is a dated decision on the card. → P8.3 · verify: `node plugins/compass/scripts/check --only P8.1` → 1 of 1 checks green · ≈ 30 min

### Slice 8 — Release and the novice test
- [ ] S8.1 Word budget: core instruction text (commands + skills + shared, excluding the optional design skills) ≤ 10,000 words; checked in CI. → P1.1 · verify: `node plugins/compass/scripts/check --only S8.1` → 1 of 1 checks green · ≈ 1 h
- [ ] S8.2 Remove the old surfaces: 7 stage skills, `start`, 3 commands, `compass.sh`, the 59 scripts, old hooks; `plugin.json` and marketplace to 1.0.0; CHANGELOG; README cut to one screen; `v0.35.0` tag stays installable. → P1.1 · verify: `test ! -d plugins/legacy-0.35 && echo old-gone` → old-gone · ≈ 2 h
- [ ] S8.3 Run on an empty folder and on an existing codebase (Jarvis) end to end. → P1.3 · verify: `node plugins/compass/scripts/compass state plugins/compass/fixtures/live` → Live · · ≈ 4 h
- [ ] S8.4 The novice test: two people, no instructions, only `/compass`, zero overrides, live numbers on their page. → P1.1, P1.2, P7.2, P6.1 · verify: `test -f .claude/builds/compass-1-0/novice-test.md && echo novice-done` → novice-doneNone

## 10. Order and parallelism
Slices run 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8. Inside a slice, steps that touch different files may run in parallel (S3.1 with S3.2; S2.1 with S2.2; S6.1 with S6.4). The Idea stage (slice 2) comes first because it is what every user meets first and what Rishi judges; the attack engine (slice 3) follows and is then wired into the idea and plan stages.

## 11. Rollout
The 1.0 plugin ships as version 1.0.0 of the same plugin. Users on 0.35 who upgrade get the new door. The kill switch is the tag: `v0.35.0` remains installable by pinning. There is no feature flag inside the plugin; the flag is the version.

## 12. Rollback
`git revert` of the release commit and re-tag; marketplace manifest back to 0.35.0. Rehearsed on a scratch clone in S8.2 before the release commit.

## 13. Testing strategy
The gate suite is the 31 promise checks (one per promise, the "verify" column above) plus every check born from a break during slices 1 to 8. Fixture folders under `plugins/compass/fixtures/` hold the sample builds. No other tests gate progress. Not tested: visual taste of the page beyond the sketch match and one human cold look.

## 14. Definition of done
A step is done when its verify command ran with fresh output and `scripts/compass receipt` recorded it. A slice is done when its steps are done and its part's attacks are closed. The build is done when S8.4 passes.

## 15. Observability
For each promise, the check in §9 is the signal. In production the signals are the two novice builds' `receipts.md` files and their Idea pages. A regression later shows as a promise whose live value turns ✗ on write-back.

## 16. Failure modes
- Host has no Artifact tool → local `card.html` and `idea-page.html` opened in the browser; terminal status line unchanged.
- Host has no scheduler → the watch end date is a line on the card; the next `/compass` after that date runs the check.
- A subagent returns prose instead of `held`/`broke` → `attack-receipt-check` rejects it; the attack is re-run once with the strict form quoted; a second failure counts as `held` with a note.
- Time box exceeded by an attacker → the attack ends `held`; the time box is recorded.
- `receipts.md` corrupted → `state` reports the last parseable receipt and names the broken line; nothing is inferred past it.
- Legacy 0.35 folder → shown as legacy; not continued.

## 17. Security and privacy
Build state may contain file paths and command output. `secret-scan` from 0.35 is kept for receipts and the release patch. The Idea page and card are private artifacts until the user shares them. No data leaves the machine except through the Artifact tool the user already uses.

## 18. Performance and capacity
Instruction text loaded per stage drops from up to 5,401 words (contract skill) to a target of ≤ 1,500 words per stage skill. `scripts/compass state` on a 500-receipt record must return in under 1 second.

## 19. Runbook
Run it: type /compass inside Claude Code in the project folder; the record is .claude/builds/<slug>/receipts.md and the card is card.html beside it.
- "Where am I?" → type `/compass`.
- Card not updating → `scripts/compass card .claude/builds/<slug>`; if the Artifact URL is lost, the local file is at `.claude/builds/<slug>/card.html`.
- A stage will not advance → the card names the unmet promise and the last receipt; nothing else to read.

## 20. Assumptions and open questions
- A1 The Artifact tool is available to Rishi; public users may lack it (handled in §16).
- A2 Subagents (the Agent tool) are available for attacks; without them, attacks run in-session with a fresh-context prompt.
- Q1 (answered) Same plugin name and repo, version 1.0.0, upgrade in place? Recommended yes.
- Q2 (answered) Who runs the first-time test, and by when? Needed before the final part.
- R1 You could be shown a list of review opinions instead of a yes or no. Guard: a reviewer may only answer held or broke with a reproduction; anything else is thrown away by a script.
- R2 Someone without the page tool could never see the card. Guard: the card opens as a local page in the browser, and the one status line is always printed.
- R3 A safety rule from the old version could be lost in the cut. Guard: a table maps all 10 rules to their new home before anything is deleted, and the suite checks the table.

## 21. Decision log
- 2026-10-26 Idea page v1 approved by Rishi. Plan v1 drafted. Plan-stage attacks not yet run (the attack engine is built in slice 2; the plan is re-attacked at the end of slice 2).
- 2026-10-26 Slice order swapped on Rishi's decision after the skeleton run: slice 2 = the Idea stage, slice 3 = attacks. Reason: the Idea page and interview are what a user meets first; the skeleton run showed a placeholder page and Rishi judged it. Idea-stage attacks are wired in when slice 3 lands.
- 2026-10-26 Door fixed after the skeleton run: it asked a question at every stage boundary; now only at the four gates.
- 2026-10-26 Three amendments on Rishi's decision: P4.5 (0 silent changes) added to part 4; S3.7 (look rubric on the mock at Idea time, binary conformance at build time) added to slice 3; S5.7 (drift stop) added to slice 5. Principle recorded: build to spec — judgement is spent on the spec once, before code; after approval only conformance is checked.
