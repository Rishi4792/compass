---
name: cinematic-hero
description: The house style for CINEMATIC MOTION + STILLS — best-in-the-world animated hero GIFs/MP4s and cinematic stills (deck covers, social cards, launch visuals), in one signature look. Triggers on requests for a "hero GIF/video", "cinematic" anything, "animated logo/wordmark", "launch/hero/demo asset", "motion graphic", "title card", "twitter/social video or card", "deck cover slide", or "make it cinematic / buzz.xyz / SpaceX / Nolan vibe". Give it a ONE-LINE BRIEF (product + a few beats) and it storyboards, builds a frame-deterministic HTML, renders GIF+MP4 (or a still), does a light self-review, and delivers. Does NOT trigger on functional UI pages/components/dashboards/forms — that is `rk-house-style`. This is the MOTION + cinematic-visual skill; rk-house-style is the product-UI skill.
version: 1.0.0
---

# Cinematic-Hero — the motion + cinematic-visual house style

**North stars:** **buzz.xyz** (kinetic energy, spray-paint wordmarks) · **SpaceX.com** (restraint, cold cinematic grade, mission-HUD) · **Christopher Nolan** (gravitas — weight, atmosphere, decisive moments). The output should make a viewer believe the product is world-class — the asset itself is proof of quality.

**Golden rule that took the most iterations to learn:** motion is **PHYSICS, never linear**. Things have mass — they overshoot, oscillate, and lock decisively. A plain spin/fade reads as "AI slop." Weight over speed.

## Companion files (in this skill dir)
```
template.html   ← the cinematic canvas + physics-motion library. START HERE — copy it, then write beats.
render.sh       ← per-frame renderer → GIF + MP4, or a single still. Has the hard-won pipeline lessons baked in.
```

## The DNA (what "cinematic" means here — keep all of it)
- **Environment:** deep cold indigo→black grade · **volumetric god-rays** from a top light · atmospheric **haze + drifting dust** · **film grain** (feTurbulence overlay) · deep **vignette** · a **mission-control HUD** (letterbox bars, mono tracked labels, timecode, a `GATES ARMED`-style status). Light emerges from darkness; nothing is flat.
- **Motion (physics):** damped-harmonic **settle** (`damp()` — overshoot → oscillate → converge) · velocity-based **motion blur** (`mblur()`) · **decisive locks** (`lock()` → a flash + an expanding shockwave ring + the target element *ignites*; and text flips state — "seeking…"→"LOCKED", fail→pass — AT the lock, not gradually) · slow, weighty timing.
- **Type:** SpaceX **condensed uppercase, wide-tracked** labels/HUD · buzz **spray-paint hero wordmarks** (`#spray` feTurbulence displacement + a blurred glow copy + light-sweep) · **mono** for terminals/HUD.
- **Content — show REAL depth, never abstraction:** a lit **terminal** with actual work ticking in (CI 94/94, eslint 0, secret-scan clean, adversarial review…) beats any "4 cute cards." Give roles a **persona** (e.g. *The Adversary* — "assume it's wrong, try to break it"). Prove things.
- **Accent:** the ONLY brand color (default indigo `--accent:#7C74FF`); green = pass, red = fail. Everything else is the cinematic grade. Swap `--accent` for the brand; keep the grade.

## Workflow — from a one-line brief
1. **Storyboard.** Turn the brief into ordered beats. Compose from PATTERNS: `logo-reveal` (a mark finds "true north" via `damp()` + `lock()`) · `kinetic-hero` (spray wordmark igniting from the light) · `terminal-depth` (real checks ticking in) · `persona` (named role + creed + evidence) · `loops+graphs` (a pipeline with exit-code edges + a node that visibly loops) · `spec-card` · `payoff` (green spray + a proof chip) · `outro-CTA`. Give each beat its own frame window `[a,b]`; beats cross-fade; the environment drifts the whole time.
2. **Build.** Copy `template.html`; set `--accent`, `TOTAL`, `FPS`; write the beats in `render(f)` using the motion library. Legibility rule: spray-paint is for *brand/emotion* words only — keep information (headlines, terminals, numbers) crisp.
3. **Render.** `bash render.sh <file.html> <TOTAL> <out-basename> [width] [fps]` → `<out>.gif` + `<out>.mp4`. Default 15 fps, GIF width ~1120. (For a **still/deck/social card**: `bash render.sh <file.html> still <frame> <out.png> [width]`, and set the target aspect/size in the HTML `html,body`+`#stage`.)
4. **Light self-review (the gate).** Extract 3–5 key frames (poster + each dramatic beat), *look at them*, and fix the obvious: overlapping/clipped/cut-off text, elements colliding, a beat that reads half-rendered when paused, an information word left illegibly sprayed, a lock that doesn't land, a dead/empty frame. Re-render, deliver. (Escalate to the full adversarial critic panel only if asked or the stakes warrant.)
5. **Deliver.** GIF (README/Twitter — Twitter transcodes GIFs to video) + **MP4** (WhatsApp/messaging — a raw GIF does NOT autoplay there; MP4 does). Copy to the target (Downloads/repo) and, for a proactive drop, surface the MP4.

## Rendering — the pipeline lessons (in render.sh; do NOT re-learn these)
- **Frame-deterministic** `render(f)` reads `location.hash`; every frame is a pure function of `f` (so renders are reproducible; `Date.now`/`Math.random` are banned — use `hh(i,s)`).
- **Unique `--user-data-dir` per frame** — shared Chrome profiles deadlock on the SingletonLock (a silent multi-minute stall). **A bash watchdog per Chrome** — macOS has no `timeout`, and a hung headless Chrome blocks forever. `--no-first-run --no-default-browser-check` — a fresh profile hangs on a first-run prompt otherwise. Kill stray `[Hh]eadless` Chrome before/after.
- **2× device scale** then downscale (crisp text). Render in parallel batches of ~6. A big render (~250 frames) is ~15 min — run it backgrounded with a progress monitor and an auto-deliver-on-completion; **never go silent** on the user.
- **MP4** = `libx264 high + yuv420p + faststart` (max compatibility). **GIF** = per-frame `palettegen stats_mode=diff` + `paletteuse` dither.

## The look-and-feel checklist (before delivering)
Physics on every move (no linear fades on hero elements) · light emerging from darkness (rays/bloom/vignette present) · grain + dust alive · at least one **decisive lock** moment · type discipline (spray for brand only, crisp info, condensed-uppercase labels, mono terminals) · one accent color · a mission-HUD framing · real substance shown, not abstract cards · a strong non-blank **poster/first frame** (loops + link-previews land on it).

## Why this exists
So the direction never has to be re-described. Everything learned building the Compass hero — the cinematic grade, the physics-driven needle that finds true north, the lit terminals that prove real work, the render pipeline that stopped stalling — is pinned here. Give a one-line brief; get the same world-class result.
