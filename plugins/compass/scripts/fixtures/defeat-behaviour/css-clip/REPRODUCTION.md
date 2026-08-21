# css-clip

**How it was found.** Contract §9 cheat 5, and this contract's own version 3 CREATED it — by
deleting the sentence that separated "text present in the page" from "text a person can reach".
The sentence is restored, and this entry is the standing proof of why it is there.

It defeats all four other cheats by using none of them: no marker, no hidden row, a control that is
neither empty nor shared, and the complete remainder present in the page.

**Reproduce.** Emit every remainder in a per-row `<details>` whose content carries
`-webkit-line-clamp:1`.

**What must happen.** The unreachable figure must NOT fall. Clipped subtrees are removed before the
check looks, and the clipping is detected from the page's own `<style>` rules, not only from an
inline `style=` attribute — so moving the rule into a class does not help either.
