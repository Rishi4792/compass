# stage-end-no-question

**How it was found.** Contract §7: the next step is asked via AskUserQuestion at every non-auto
stage end. Measured before the gate existed: **5 of 30 receipt files carry any `asked=` at all**,
and all five are the mode choice at LOCK time, not a stage end. The rule had never been recorded,
let alone checked.

**What must happen.** A stage-end stamp with no `asked=` is REFUSED; a well-formed one passes.
