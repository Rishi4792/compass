---
name: compass-visual
description: Render a build's Contract Brief and progress Cockpit as self-contained HTML + a PNG — the visual "what we're building" and "where it stands" surfaces of a Compass build. The Brief is a cinematic-hero cover + rk-house-style body, read as a PURE FUNCTION of contract.md; the Cockpit is the stage timeline + step k/n + blocker + what's next + what the reviews caught, from progress.md/plan.md/receipts.md/review-ledger.md. Trigger at contract closure (produce the Brief before the explicit lock), at any point someone asks "show me where this build stands", or when the Compass contract/build stages need the visual. A shareable Artifact is produced ONLY on request — and the user is told that option exists.
---

# compass-visual

Two views of a build, generated deterministically from its on-disk state by `gen.mjs`.

- **Contract Brief** — *what we're building.* A cinematic-hero cover (its own accent + grade) over an rk-house-style body: the goal, what it touches, the reconciliation gold, the invariants, the NOW/LATER/NEVER scope, and the security classification. A pure function of `contract.md`.
- **Cockpit** — *where it stands.* Stage timeline (done / ◉ here / left), step k/n, the next action, and what the reviews caught. From `progress.md` / `plan.md` / `receipts.md` / `review-ledger.md`.

Both are **self-contained HTML** written into the build folder, rendered to **PNG** via `cinematic-hero/render.sh`. Same state → byte-identical HTML (no clock, no randomness) — safe to re-run.

## Generate

```
node skills/compass-visual/gen.mjs <build-dir> <view> [--shareable] [--out <file>]
```

- `view` ∈ `brief` | `brief-body` | `cockpit`.
  - `brief` — the full page: cinematic cover + house body. This is what you render + show.
  - `brief-body` — ONLY the house-style body region. This is the artifact the house gates run on (the cinematic cover is off-theme **by design** and is excluded from the gate — it follows cinematic-hero's own accent + editorial radii).
  - `cockpit` — the progress view.
- `--out <file>` writes to a file; without it, HTML goes to stdout (so `diff <(gen …) <(gen …)` proves idempotency exactly).

**Render to PNG** (headless Chrome):
```
bash skills/cinematic-hero/render.sh <build-dir>/brief.html still 0 <build-dir>/brief.png
```

## The two variants — LOCAL vs SHAREABLE (a real split, not one render)

- **LOCAL** (default) — the build-folder Brief renders the **full reconciliation-gold literal** and the **full security block**. This is the truth the operator locks against.
- **SHAREABLE** (`--shareable`, on request) — for sending outside the build. The gold literal and every **never-show field value** are redacted to a `gold pinned ✓` / `⟨redacted ✓⟩` badge (the classification **labels** still render — the point is *what's classified*, not the values).

A single redact-everywhere render would drop the gold from the LOCAL Brief and violate the contract's Brief requirement — so the two are **distinct code paths**. Never hand a shareable copy off silently: produce it **only when asked**, and **tell the user** the shareable option exists and what it withholds.

## The leak gate (mandatory before ANY shareable Artifact)

`--shareable` runs a **scrub-then-HARD-STOP** gate on the generated HTML: any secret class (`sk-…`, `AKIA…`, `xox…`, JWT, PEM private key, inline URL credentials, an inline `*_SECRET` value), any commercial-sensitive **value** (IRR / take-rate / gross-revenue / COF adjacent to a number), or any gold / never-show **residue** is scrubbed from the written copy **and** forces a non-zero exit (3). Never a soft pass: a leak both scrubs the copy **and** stops — a secret does not belong in a contract, so the operator must fix the source, not ship a scrubbed artifact quietly.

**Honest scope — best-effort over free-form prose.** The gold-VALUE scrub catches the reconciliation figure in every *realistic* locale format: plain, currency, percentages, multiples, unit words (crore/lakh/bps), and any thousands grouping (comma, space, NBSP, narrow/thin space, apostrophe) collapsed to a normalized numeric key. It is **not** a certainty against every exotic reformatting a human could type in the Goal — a European period-grouping (`8.750.000`), a spelled-out number, or two figures glued by a bare space. The **primary** guarantee is structural and always holds: the reconciliation-gold **card is always replaced by a badge** (its literal is never rendered), never-show values are scrubbed case-insensitively, and secret classes hard-stop. Because a figure restated in free prose can't be caught with certainty, the shareable Artifact is **opt-in and operator-reviewed** — read the redacted copy before you send it.

Defense in depth — also run the engine's own scanner on the output before sharing:
```
compass.sh secret-scan <build-dir>            # scans the generated HTML too (grep -I: scan source HTML, not the PNG)
```

## Invariant

Generated assets are **real assets, not wireframes** — the first line is `<!doctype html>`, **never** a `<!-- COMPASS-MOCK slug=` marker (which would trip the sketch-gate leak tracer). The body's craft is proven by the bundled house gates on `brief-body`:
```
node skills/rk-house-style/gates/anti-drift-grep.mjs <build-dir>/brief-body.html skills/rk-house-style/themes/neutral-indigo.json   # 0 off-theme tokens
node skills/rk-house-style/gates/compose-check.mjs   <build-dir>/brief-body.html                                                   # composed from the kit
```
plus a render to a **> 5KB PNG** and an independent world-class aesthetic eyeball (append-only `compass-visual/score.md`, verdict `GO`).
