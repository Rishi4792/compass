# The look rubric — how a screen is judged, once, before code

Compass owns this list the way it owns the failure catalogue. It is applied to the **mock** at Idea time by three fresh reviewers who see only the screenshots, the sketch and this file. Each scores every item 1 to 5 and names the exact region for anything under 4. The median decides against the bar for the design level the person chose. After the person approves the mock, no taste call happens again; the build is checked for conformance to the mock only.

## Bars
premium: every median ≥ 4, no median ≤ 2
clean: every median ≥ 3, no median ≤ 1
match: no rubric; conformance to the person's existing screens only

## Reviewer output
One line, nothing else:
`scores: hierarchy=4 spacing=3 type=4 color=5 components=4 states=3 alignment=4 polish=3 responsive=4 copy=4 depth=4 structure=4 controls=5 | low: spacing@"gap between the paste box and the list is 8px where the rest uses 24px"; states@"an empty list shows a blank area"`
The `| low:` part lists every item under 4 with its region in quotes. `scripts/compass look-score <level> <line> <line> <line>` turns three such lines into `held` or `broke`.

## Items

## hierarchy
name: Hierarchy
ask: Is the one most important thing on the screen obvious within three seconds, and is everything else visibly secondary?
5: One clear focal point; size, weight and position all agree on it.
3: A focal point exists but competes with one other element.
1: Everything has the same weight; the eye has nowhere to land.

## spacing
name: Spacing rhythm
ask: Do gaps come from one scale, and do related things sit closer than unrelated things?
5: One scale throughout; grouping is readable from spacing alone.
3: Mostly one scale; two or three gaps break it.
1: Gaps are arbitrary; grouping cannot be read from spacing.

## type
name: Type
ask: At most two families, a clear size scale, readable sizes, lines of running text under about 75 characters, and deliberate accents (one display weight or style used sparingly for emphasis)?
5: All four hold; headings and body are visibly different roles.
3: One of the four slips, such as a line too long or a third size that is not on the scale.
1: Sizes and weights are mixed without a scale; text is hard to read.

## color
name: Colour and contrast
ask: Do colours come from a small palette, does text pass contrast, and are good/warning/bad colours separate from the accent?
5: Palette of five or fewer, contrast passes everywhere, semantic colours distinct.
3: Palette holds but one contrast or one semantic use slips.
1: Many greys and accents; text fails contrast somewhere.

## components
name: Component consistency
ask: Do things with the same role look the same: same edges, radius, shadow, padding, and the same place on every item?
5: Identical treatment for identical roles; nothing one-off.
3: One component drifts from its siblings.
1: Buttons, cards or rows differ from screen to screen.

## states
name: Designed states
ask: Are empty, loading, error, long text, zero data and the maximum count all designed, not left to chance?
5: Every state is shown and reads as intended.
3: Empty and error exist; long text or the maximum breaks the layout.
1: Only the happy path exists.

## alignment
name: Alignment and density
ask: Do edges line up, is nothing orphaned or floating, and is density right for the moment of use?
5: Clean edges, no orphans, density matches the task.
3: One misalignment or one orphaned element.
1: Edges wander; items float; density is wrong for the task.

## polish
name: Polish details
ask: Icons from one set, visible focus state, hover and press feedback, restrained motion, no clipped text?
5: All present and quiet.
3: One missing, such as no focus state.
1: Mixed icon sets, no feedback, clipped text.

## responsive
name: Phone and desktop
ask: Does the screen read at 390 px and at 1200 px with no sideways scroll and nothing stacked badly?
5: Both widths are composed, not merely squeezed.
3: One width has a stacking or wrapping flaw.
1: One width is unusable.

## copy
name: Copy
ask: Are labels plain and specific, in the person's words, with no placeholder text and no jargon?
5: Every label says exactly what happens; a stranger understands it.
3: One vague or system-worded label.
1: Placeholder text or internal names visible.

## depth
name: Depth
ask: Do surfaces sit in clear layers: a ground, cards on it, and raised elements, told apart by tint, hairline and a quiet shadow, never by heavy borders?
5: Three planes read at a glance; shadows are soft and consistent; nothing floats without a reason.
3: Cards sit on a ground but one element uses a heavy border or a shadow that does not match the rest.
1: Everything is flat on one plane, or shadows and borders are mixed at random.

## structure
name: Page structure
ask: Does the page have a clear top-to-bottom order: a header that says where you are, one primary region, supporting regions after it, and consistent section rhythm?
5: The order is obvious; sections have the same rhythm; the primary region is first.
3: The order holds but one section is out of place or breaks the rhythm.
1: Regions compete; the eye does not know where to start.

## controls
name: Controls
ask: Is every button, field, select, toggle and link styled from the design system, with no browser-default control and no two controls of the same role looking different?
5: All controls are the system's; identical roles look identical; focus and disabled states are designed.
3: One browser-default control or one odd-one-out.
1: Native selects, default buttons or mixed control styles throughout.
