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

**Honest scope — best-effort over free-form prose, CERTAIN for declared values.** The gold-VALUE scrub catches the reconciliation figure in every *realistic* locale format: plain, currency, percentages, multiples, unit words (crore/lakh/bps), and any thousands grouping (comma, space, NBSP, narrow/thin space, apostrophe) collapsed to a normalized numeric key. Over free-form prose it is **best-effort** — not a certainty against every exotic reformatting (a spelled-out number, two figures glued by a bare space). The shareable Brief carries an always-on **best-effort caveat banner** saying exactly this. The **primary** guarantee is structural and always holds: the reconciliation-gold **card is always replaced by a badge** (its literal is never rendered), never-show values are scrubbed case-insensitively, and secret classes hard-stop. Because a figure restated in free prose can't be caught with certainty, the shareable Artifact is **opt-in and operator-reviewed** — read the redacted copy before you send it.

### The `brief-data` fence — declared values, scrubbed with CERTAINTY (v0.17.0)

A contract can pin the sensitive values in a machine-readable fence so the shareable scrub keys off a value the contract *states*, not one it *guesses*:

```
```compass-brief-data
gold: 8750000, 87.5 lakh
never-show: irr, take_rate
```
```

- **Recognition (this line is the fail-open boundary):** a code-fence opener LINE (**≥3 backticks OR ≥3 tildes**) whose info-string — lowercased, `\r`/whitespace-trimmed, `-`/`_`/space-collapsed — equals `compassbriefdata`. Line-anchored (a prose/inline mention is NOT an opener → **absent**) and fuzzy on the tag (case / CRLF / trailing space / tilde still recognize). First recognized opener wins.
- **Three states:** **absent** (no opener) or **`none`/empty** → best-effort path, no error · **malformed** (opener recognized but unclosed, or a body line that is neither `none` nor a recognized `gold:`/`never-show:` key) → **hard error, exit 2, on `--shareable` only** (never silently "absent", never a false exit-0).
- **Certain vs best-effort:** each declared `gold:` literal is normalized to its bare integer magnitude (currency + all grouping separators stripped, a lone decimal tail preserved), then every numeric locale reformatting — {Western-3, Indian-2-2-3} × {plain, comma, ASCII/NBSP/thin/narrow space, apostrophe, European period} × {no-prefix, currency} — is scrubbed with **certainty**; the exact literal is always scrubbed too. **Unit / display forms** (e.g. `87.5 lakh`) are certain only when declared as their own `gold:` token; undeclared unit / word-spelled / arbitrary-prose forms stay **best-effort** (the always-on banner). Declared values also seed the normalized best-effort layer, so the "suspenders" hold even when the Reconciliation section is N/A.
- **LOCAL ignores the fence entirely** — it is read on the `--shareable` path only, so a malformed fence never breaks the lock-surface Brief.
- **Recognition robustness (accepted bound).** The fence tag is recognized through case, `-`/`_`/whitespace variation (incl. tab, NBSP, thin/narrow spaces, U+2028/U+2029), a trailing info-string token, and a single `.ext`. A tag mangled by an even more exotic transformation than these falls to the **absent** path — best-effort, with the always-on banner — never a false hard-error; the structural guarantee (gold card badged, opt-in + operator review) still holds. Declared values with **<3 significant digits** or unit/`%`/`x` suffixes are exact-scrubbed (literal + bare magnitude) but not guaranteed across every reformatting — the banner labels them best-effort. This is a deliberate bound, not a defect: chase certainty only for the realistic-locale numeric set, disclose the exotic tail.

**Exit codes:** `0` ok · `2` usage/missing-state **OR a malformed `brief-data` fence on `--shareable`** · `3` leak-gate HARD-STOP.

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
