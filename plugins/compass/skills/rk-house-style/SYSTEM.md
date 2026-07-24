# SYSTEM — the house design system (universal kit)

> The reusable 90%. Token STRUCTURE + component recipes + the craft rubric.
> Identity (the 10%) is set by 4 seeds → `seeds-to-tokens.mjs` → a theme in `themes/`.
> Default theme = `neutral-indigo`. Gold = `gallery/` + the active theme's tokens.

---

## Part 1 — Token STRUCTURE (the shape every theme fills)

A theme is ONE `TOKENS` object with these 9 groups — the exact shape `seeds-to-tokens.mjs`
emits, and the shape the bundled `neutral-indigo` default fills. **Build with token
references, never raw literals.** (The example hex values below are the `neutral-indigo`
defaults, for orientation only — read them from the theme JSON, never hard-code them.)

```ts
type Tokens = {
  // 1. INK RAMP — text from strongest to faintest (4 steps, all AA on surface)
  ink: string;        // primary text / big numbers      (e.g. #0A2540)
  mut: string;        // secondary text                   (AA ≥4.5 on surface)
  mut2: string;       // tertiary / captions              (AA ≥4.5 on surface)
  kicker: string;     // uppercase label color

  // 2. ACCENT + tints (ONE brand color, used sparingly for emphasis/links/active)
  accent: string;     // the brand hue                    (e.g. #4F46E5)
  accentDark: string; // pressed/hover                    (derived −12% L)
  accentWash: string; // 6–8% tint for chips/active bg    (rgba(accent,.07))

  // 3. STATUS — fg+bg PAIRS (never color-only; always paired with text/icon)
  greenFg: string; greenBg: string;   // ok
  amberFg: string; amberBg: string; amberBorder: string;  // watch
  redFg: string;   redBg: string;     // risk
  chipFg: string;  chipBg: string;    // neutral tag chip — AA dark on faint

  // 4. SURFACES — the page is layered, not flat
  bg: string;         // app canvas
  surface: string;    // card                             (#FFFFFF)
  headBg: string;     // table header / inset panel
  line: string;       // hairline border (NOT a heavy 1px gray)
  grid: string;       // chart gridline

  // 5. TYPE — 2 families max (display/body sans + optional mono for figures)
  fontSans: string;   // body + headings                  (e.g. 'Inter')
  fontMono?: string;  // optional, for dense figures (the default theme ships sans only)
  // scale (px): big 44/700 · h1 34/700 · h3 15/600 · body 13–14 · kicker 11/700 · micro 9.5–11
  // figures ALWAYS font-variant-numeric: tabular-nums

  // 6. SPACING — 4/8 grid: 2 4 6 8 11 14 16 20 22 26 (card pad = 20–22)
  // 7. RADII — card 12 · chip 6 · pill 99 · inset 8 · control 7–9
  // 8. SHADOW — soft depth, not heavy: card e.g. 0 1px 2px rgba(ink,.04)
  //            (hairline border does most of the separation work)
  // 9. MOTION — entrance ONCE on mount, 0.5–0.6s cubic-bezier(.22,.61,.36,1),
  //            staggered ≤ .26s; honor prefers-reduced-motion; hover ≤ 120ms
};
```

**Rules that hold across every theme (the "minus novelty" guardrails):**
- ONE accent. No second brand hue. Status colors are for status only.
- Hairlines + soft shadow for depth — never heavy borders or flat gray boxes.
- Tabular numbers on every figure. ≤ 2 font families.
- The single most important thing on a screen is the largest, highest-contrast element.
- Color is never the only signal — pair every status with text/icon.
- No purple-gradient-on-white cliché unless the brand accent *is* that, used intentionally.

The craft rubric that enforces all of this lives in **`gates/rubric.md`** (read it — the
self-critique gate G3 scores against it).

---

## Part 2 — Component recipes

> Compose pages from THESE. Each maps to a page in the neutral `gallery/` gold
> (dashboard / form / table). Geometry is exact — copy it; don't reinvent. All colors are token refs.

### R1 · Card  — `gallery/dashboard`
`background:surface; border:1px solid line; border-radius:12px; padding:20px 22px`.
The hairline + soft shadow do the separation — never a heavy gray border.

### R2 · Kicker (section label)  — every gallery shot
`font-size:11px; font-weight:700; letter-spacing:.07em; text-transform:uppercase; color:kicker`.
Labels every block above its value. (Stat-tile kicker variant: 10px.)

### R3 · Hero (one focal number)  — `gallery/dashboard`
Left rail (≈430px): kicker → big number `font-size:44px; font-weight:700; letter-spacing:-.025em; line-height:1; color:ink` + a pace-style pill beside it → one-line sub-context (`13px; color:mut`, key figures bolded ink) → `hr` (1px line) → 2–3 sub-stats (kicker + 18px/700 value + 12px mut caption). Right: a chart panel on `headBg` inset. The hero is the largest thing on the page.

### R4 · Pace pill / status pill  — `gallery/dashboard`
`font-size:12px; font-weight:600; padding:4px 10px; border-radius:99px; color:{status}Fg; background:{status}Bg`, with a 7px `border-radius:50%` dot in `currentColor`. Text says the state ("Behind pace", "All clear") — never color alone.

### R5 · Chip (inline tag)  — `gallery/table`
`font-size:11.5px; font-weight:600; padding:2px 7px; border-radius:6px`. Status chip → status fg/bg; neutral chip → `mut2` on a faint surface; mini % chip → 9.5px.

### R6 · Data table  — `gallery/table`
Wrapper `border:1px solid line; border-radius:8px; overflow:hidden`. Header `background:headBg; font-size:9.5px; font-weight:600; text-transform:uppercase; color:mut`. Body cell `font-size:11–11.5px; border-bottom:1px solid line; font-variant-numeric:tabular-nums; text-align:right`. **First column ALWAYS `text-align:left`** (header + body), `font-weight:600`, padded `padding:10px 14px`. Current/active column highlighted in `accent`.

### R7 · Stat tile  — `gallery/dashboard`
Grid of `surface` tiles separated by 1px `line` gaps. Each: 10px uppercase kicker → 19px/700 value (`ink`, or status fg if concerning) → 11px mut caption with the threshold ("alert if ≥ 1").

### R8 · Zoned / funnel bar  — `gallery/dashboard`
Horizontal track `height ≈ 8–30px; border-radius:8px; background:grid`; fill `linear-gradient(90deg, accent-light, accent)` (or `greenFg` for "done"). Stage rows: label + count chips + a right-aligned value in `accent`. For a capacity/zoned bar, place non-overlapping markers ABOVE and BELOW the track so labels never collide.

### R9 · Line / cumulative chart  — `gallery/dashboard`
SVG. Light `grid` gridlines; the live series a 2.5px `accent` stroke (smoothed) with a 7% area fill; a reference/target series as `mut2` dashed. A dot on the latest point. `role="img"` + an aria-label. Aggregate to ≤ ~40 points — never a per-sample seismograph.

### R10 · Gradient-tinted detail card  — `gallery/dashboard`
A trio of cards, each with a 3px top accent in a DIFFERENT tint (a blue, a violet, a green) over a very faint matching wash background; a big value under a colored kicker; sub-cards inside on `headBg`. Use sparingly — this is the one place a second/third hue is allowed, as a soft *categorical* tint, still calm.

### R11 · Tabbed section  — `gallery/form`
Tab row: inactive `color:mut; font-weight:500`; active `color:accent; font-weight:600` with a 2px `accent` underline. Generous gap; hairline under the whole row.

### R12 · Timeline rail
A vertical 1–2px `line` rail with numbered nodes: each node a `28px` circle, `accent`→`accentDark` gradient fill, white bold number, centered on the rail. Connects sequential steps.

### R13 · Thread / list card
A `surface` card: a glyph + muted timestamp top-left, a small count chip top-right; bold `ink` title with inline chips (type, linked-entity); a faint preview line; an avatar stack (28px circles, colored initials) + names. Hover lifts subtly.

### R14 · Composer / form  — `gallery/form`
Rows with `kicker`-style labels; auto-chips in `greenBg`; a large body area (`13px`); a formatting toolbar; a primary `accent` submit button (white text) + a ghost secondary. Labels in `mut`, values in `ink`. Validation states pair a status color with text (never color alone).

---

## Provenance
- Tokens are generated deterministically by `seeds-to-tokens.mjs` from 4 identity seeds; the
  bundled `neutral-indigo` default is one such generated theme (`themes/neutral-indigo.seeds.json`).
- This file is the reusable craft; the enforcement it needs lives in `SKILL.md` + `gates/`.
