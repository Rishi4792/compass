# unavailable-without-evidence

**How it was found.** Contract §8: `COULD-NOT-VERIFY` "requires machine evidence of the failed spawn
and HARD-BLOCKS closure". Nothing required the evidence. The verdict was three words a reviewer
could type to turn an unrun stream into a recorded one.

**What must happen.** Both directions, and the honest path must stay open — a rule that punishes a
genuine failure only teaches people to write CLEAN instead:
1. an all-`CLEAN` round with no spawn logs → PASSES (the rule must not demand logs it should not);
2. `COULD-NOT-VERIFY` with nothing beside it → REFUSED;
3. `COULD-NOT-VERIFY` **with** a non-empty `<review>-r<round>-<stream>.spawn.log` → PASSES;
4. an EMPTY spawn log → REFUSED, because a zero-byte file is not machine evidence of anything.

**Mutation proof.** Removing the spawn-log requirement → RED. A gate that returns 0 immediately →
RED.

**What this does NOT claim.** It cannot tell whether the spawn genuinely failed, only whether
anything was recorded. Contract §4 is explicit that independence cannot be proven in this
environment; INV-DISCLOSE-UNVERIFIED is what covers the residue.
