# review-claims-agents-zero-files

**How it was found.** Contract §8, INV-SUBAGENT-REAL: "One evidence file per stream in that review
skill's own machine-readable stream list." No skill had such a list, and nothing read one. The
denominator was whatever the receipt said about itself.

**The measurement that made it real** (this repo, before the gate existed): 31 build folders · 20
receipts carrying a checked `all streams run; ledger updated` line · **1** folder with an `agents/`
directory in it. Twenty reviews recorded that every stream ran, with zero evidence files on disk.

**What must happen.** Four things, each isolated by its own fixture so no one of them can be deleted
without the corpus noticing:
1. one well-formed file per DECLARED stream → PASSES (or the gate just refuses everything);
2. the same receipt with an empty `agents/` directory → REFUSED;
3. a receipt naming its own denominator (`1 of 1`) → REFUSED;
4. a receipt whose **numerator is honest** but whose **denominator is smaller than the declared
   list** → REFUSED. This case exists because the first attempt at it (`3 of 3`) was caught by the
   numerator rule instead, which proved nothing about the denominator rule.
5. files missing `nonce`/`target-sha` → not counted present. Contract §4 calls those ABSENT.

**Mutation proof.** Removing the per-stream-file rule *and* the shape rule → RED. Removing the
denominator comparison alone → RED. A gate that returns 0 immediately → RED.
