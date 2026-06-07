# Compass enforcement — receipts, gates, and the gate script (read once)

<!-- Agents: do NOT read at runtime — the skills inline the one command they need. Human/maintainer overview only. -->


> Human reference. The skills inline the one command they need. The point: enforcement is a
> **deterministic script with an exit code**, not a checkbox the model grades itself on.

## The gate script
`scripts/compass.sh` (in the Compass plugin dir). Run it via `$CLAUDE_PLUGIN_ROOT/scripts/compass.sh`; if that env var isn't set in your shell, find the installed plugin (e.g. `~/.claude/plugins/*/*/compass/scripts/compass.sh`). Subcommands (each exits NON-ZERO on failure, so the Bash tool surfaces a hard error you cannot proceed past):

| Command | What it enforces |
|---|---|
| `gate <build-dir> <prior-stage>` | Blocks unless the prior stage's **latest** receipt is PASS, has **no unchecked `[ ]` box**, and is **not SUPERSEDED**. Run this in every downstream skill's Step-0. |
| `scan-receipt <build-dir> <stage>` | Self-check the receipt you just emitted: PASS + no empty box. Run it right after emitting. |
| `supersede <build-dir> <from-stage>` | On escalation / re-run: voids `<from-stage>` and **all later** receipts so the stages they gate must re-run. Run it whenever you escalate UP or re-run a stage. |
| `reconcile <actual> <gold> <tol>` | Deterministic numeric gate. `tol` = `0`, an absolute (`0.1`), or percent (`1%`). Non-zero exit = build cannot close. Removes model discretion over PASS/FAIL. |
| `secret-scan <build-dir> [files…]` | Fails if a cookie/JWT/key/connection-string looks committed (scans the git diff, or given files). |
| `close <build-dir> <slug>` | Clears `CURRENT` so a closed build can't leak its gate to the next standalone run. |

## Receipts (`receipts.md`, append-only)
Each stage emits one block. **Lines carry the actual command + output, not bare checkboxes** — a line that claims a check with no command is auto-FAIL (and `scan-receipt`/`gate` reject an unchecked `- [ ]`). Shape:
```
## RECEIPT — <stage> · <slug> · PASS
- [x] gate: prior <stage> receipt OK   (compass.sh gate → PASS)
- [x] <claim>: `<exact command>` → <fresh output / exit / count>
- [ ] <anything you could NOT prove — leaving this unchecked forces the gate to block downstream>
```
If any box can't be honestly checked, set the header to `FAIL` and do NOT hand on.

## Lifecycle order (for gate freshness + supersede)
`contract → review-contract → plan → review-plan → build → review-build → ship`
