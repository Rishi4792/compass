# Session isolation & ship coordination (v0.9.0)

Compass runs in many terminals. v0.9 makes sure one build never disturbs another build — or any unrelated session — in the same project or across projects.

## The Stop hook is owned, not global

Every build records the **session id** of the terminal driving it:

```
.claude/builds/.locks/<slug>.owner   →   session=<id>
```

- Written by the **build** skill at Step 0 (before the gate, unconditionally — fresh *and* resumed), refreshed each step; by **resume** on re-entry; by **ship** at start. Source of the id: `$CLAUDE_CODE_SESSION_ID` (the runtime env var; the docs' `CLAUDE_SESSION_ID` is unset in Bash).
- The **Stop hook** (`compass.sh stop-guard`) reads the stopping session's `session_id` from stdin and **blocks only if a mid-build's owner equals it** (exact compare). 

Result:

| Situation | Stop hook |
|---|---|
| You own a mid-build, you stop | **block** (don't abandon half-applied work) |
| A *different* session owns the only mid-build | quiet `{}` |
| You own nothing mid-build | quiet `{}` |
| Orphan build (owning terminal closed) | quiet for **everyone** — until someone resumes it and re-binds |
| A mid-build in another project | quiet (state-root is per-project) |

The owning-session safety net from v0.7/0.8 is preserved exactly — only *unrelated* sessions stopped being blocked.

### Safety properties
- **Never crashes a session.** Every read is guarded under `set -euo pipefail`; any error fails open to `{}` exit 0.
- **Loop-safe.** `stop_hook_active` is the primary anti-deadlock. A `session|slug|step-counter` fingerprint (written under a fail-open mutex) blocks at most once per build-step — cosmetic churn can't loop it; a real step advance re-arms it.

## Ship coordination (one project, two ship-ready builds)

- **Single-flight lock** — `compass.sh ship-claim <slug>` (claimed first, unconditionally, in ship Step 0). Only one build per project ships at a time. Released on **every** exit (success, yield, hard-stop), so a failed ship never leaks the lock. Self-heals: steals a `SHIPPED`/`ROLLED-BACK` or >2h-stale holder — **never** a `CLOSED` holder (that's the live mid-ship state).
- **Contention ordering** — `compass.sh ship-contenders <slug>` lists other ship-ready builds (status `CLOSED`, deploy not waived; status read progress-md-first so a stale INDEX can't mislead). If any exist, ship asks **which goes first**. The loser releases the lock and yields; on resume, `post-merge-check` + `merged-recon` re-check it against the now-advanced base and block until it integrates + re-verifies. (For library builds with no reconciliation figure, the merged-tree proof is the test suite going green.)

## Commands

```
compass.sh own <slug> [--session <id>]   # bind owner (refuses an empty id)
compass.sh ship-claim <slug>             # acquire the single-flight ship lock
compass.sh ship-release <slug>           # release it (only if you hold it)
compass.sh ship-contenders <slug>        # list other ship-ready builds in this project
```

All of this is covered by 65 assertions in `compass.selftest.sh` (session isolation S1–S17, cross-project S14, ship coordination P1–P7).
