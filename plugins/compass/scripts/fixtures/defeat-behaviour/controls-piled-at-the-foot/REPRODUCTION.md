# controls-piled-at-the-foot — the entry that PINS the positional rule

**How it was found.** The fifth independent review (M-1): deleting
`if (!ctrls[i].before.includes(shown)) continue;` from `reachable-argument.mjs` changed **no
assertion and no corpus entry**. The rule that does the most work in the whole check had nothing
behind it.

**What it does.** Keeps every control exactly as an honest build makes it — one per row, holding
that row's own remainder, proportionate, unclipped, not inert — and moves them all to the foot of
the page.

**What must happen.** The unreachable figure must NOT fall. A reader at a shortened row has no way
to get from it to its own half; a pile at the foot is an index of remainders, not disclosure.

**What it proves that nothing else does.** Delete the positional rule and this entry goes red while
every other entry stays green. That is the definition of a pinned rule.
