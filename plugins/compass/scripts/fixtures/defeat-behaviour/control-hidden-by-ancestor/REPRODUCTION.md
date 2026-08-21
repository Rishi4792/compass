# control-hidden-by-ancestor

**How it was found.** An independent review of v0.32 S6. The commit's new positional rule ties a
control to its row by requiring the row's SHOWN half in the reachable text immediately before the
control. That rule is sound. What is not sound is the other half of the same judgement: whether the
control itself is reachable.

`controlsFor()` builds each control's text with `reachableText(m[0])`, where `m[0]` is the
`<details>…</details>` substring produced by a regex over the page. Clipping *inside* the control is
therefore seen — which is why the `css-clip` entry is defeated. Clipping on an **ancestor** of the
control is not in the substring at all, so it is never seen. The whole-page pass
(`reachableText(html)`) does honour ancestors, so the check applies ancestor-aware visibility to its
WEAK evidence ("merely present in the flow") and ancestor-blind visibility to its STRONG evidence
("in a control holding THAT row's remainder").

The `before` slice has the mirror-image blindness: it is computed over `html.slice(prevEnd, m.index)`,
a fragment that starts mid-document. A clipped wrapper opening between the shown text and the
control truncates the fragment *after* the shown text, so the shown text survives in `before`; a
wrapper that opened before `prevEnd` is not in the fragment at all, so the fragment reads as fully
visible.

**Reproduce.** Wrap every `<details class="rest">` in `<div style="display:none">`, and append one
visible pile of every remainder at the page foot so the SOURCE measure is unaffected.

**What must happen.** `REACHABLE` must FALL. It does not: it holds at exactly its honest value.

Measured on the tracked fixture corpus at 7a19721:

| figure | honest build | this cheat |
|---|---|---|
| dropped units | 172 | 172 |
| probed | 170 | 170 |
| REACHABLE | 83 | **83** |
| UNREACHABLE (bindable) | 0 | **0** |
| ...merely present | 20 | 20 |
| UNREACHABLE | 87 | **87** |
| SOURCE LINES | 108 | 108 |
| SOURCE UNREACHABLE | 82 | 82 |

`diff` of the two full check outputs is EMPTY. `compass.smoke.sh` reports 798 passed, 0 failed.
`behaviour-corpus-check.sh` reports 8 entries, 0 failing. `redfirst-count.sh` 4 re-run, 0 failing.

**Why a new rule.** Both existing rules are "the figure must not FALL". This cheat does not lower a
figure; it holds every figure at its honest value while making the disclosure unreadable. The rule
it needs is about the CREDIT side: `reachable-must-not-hold` — a cheat that hides every control must
not leave `REACHABLE` where it was.

**The fix the entry is asking for.** Judge a control in its ancestor context: strip clipped subtrees
from the WHOLE document once, and take controls (and their `before` slices) from the stripped
document, rather than re-parsing each `<details>` substring in isolation.
