# unverified-review-silent

**How it was found.** Contract §4, after Rishi's decision: *"PROVING INDEPENDENCE IS IMPOSSIBLE HERE,
AND COMPASS WILL STOP CLAIMING IT CAN."* A reviewer subagent's capabilities are a strict subset of
its caller's — same user, same process — so a caller can impersonate a reviewer perfectly. That was
demonstrated, not argued: a reviewer forged a subagent transcript pair and back-dated it in four
shell lines with zero Agent calls. The invariant that tried to prove independence was deleted, and
INV-DISCLOSE-UNVERIFIED replaced it: **the page AND the receipt say so.**

Before this entry, silence was the default and nothing refused it. A review that said nothing about
whether it was independently verified read exactly like one that was.

**What must happen — both halves, both directions.**

*Receipt* (`compass.sh review-disclose-gate`):
1. a per-stream-format receipt carrying the sentence → PASSES;
2. the same receipt without it → REFUSED;
3. a receipt predating the format → N/A-PASSES **and says so**, including what it is not claiming.
   30 of this repo's 31 build folders carry a review receipt and 27 are in that state; a silent pass there reads as a clean bill;
4. two recorded rounds with one disclosure line → REFUSED. One sentence cannot speak for a round
   written after it.

*Page* (`gen.mjs unverifiedBanner` + `artefact-gate.mjs`):
5. a rendered review page carries the sentence, and artefact-gate records `review-disclosure`;
6. the same page with the sentence stripped → REFUSED by name;
7. a NON-review page records `review-disclosure-na` rather than skipping in silence — a rule that
   silently skips is indistinguishable from one that passed, which is this build's own defect class.

**On styling, which is not cosmetic here.** Two cold readers walked past the previous disclosure and
moving it changed nothing, because a reader skips by STYLE before position matters. The banner is a
red-ruled block in body-sized text at the top of the review page. It also carries a number that
moves — how many per-stream evidence files exist — so it cannot be read as boilerplate.

**What this does NOT claim.** Nothing here establishes independence; §4 says that cannot be done in
this environment. It establishes only that Compass stops implying it.
