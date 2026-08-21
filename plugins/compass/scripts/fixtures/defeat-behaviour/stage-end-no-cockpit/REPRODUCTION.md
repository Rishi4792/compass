# stage-end-no-cockpit

**How it was found.** Contract §7: "When any stage ends, then the cockpit prints — in every mode, no
exception." Nothing checked it. The clause was a sentence.

**What must happen.** A receipt block whose stage-end stamp does not say `cockpit=printed` is
REFUSED, and a well-formed one still passes — both directions, because a gate that refuses
everything satisfies a one-directional check for free.
