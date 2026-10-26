# Plan template — the 21 sections the best engineering teams write

Copy the headings exactly, numbered, in this order. Fill every section or write "Not applicable, because …". `scripts/compass plan-check <dir>` refuses a plan with a missing heading, a current-state section that cites no real file, a promise with no step, a step with no promise, a first slice that is not the skeleton, or a step without a verify command. The person reads one screen of this (`plan-card`); the file is for the machine and for whoever comes after.

```
# Engineering Plan — <slug> · v1 · <date>

## 1. Goal and promises
<the purpose line from idea.md; the promise IDs this plan delivers>

## 2. Non-goals
<what this build will not do, from ## Never and ## Later>

## 3. Current state (read, not assumed)
<what exists today, with real paths: entry points, data shapes, existing tests, how it deploys. Cite at least one path that exists. In an empty folder write "greenfield" and name the chosen stack.>

## 4. Proposed design
<the pieces, the data flow, the interfaces between pieces, one diagram in a fenced block>

## 5. Alternatives considered
<two or three other designs and why not>

## 6. Data changes
<every schema or data change in expand-then-contract form; each reversible; backfills counted against the source; dry-run on a copy first. "None" if none.>

## 7. Dependencies and blast radius
<new libraries with exact versions; everything that touches the changed code and could break>

## 8. Walking skeleton (slice 1)
<the thinnest version that runs end to end through every layer named in §4>

## 9. Slices and steps
### Slice 1 — Skeleton (<what it proves>)
- [ ] S1.1 <what> → P<id>[, P<id>] · verify: <command that proves it> · ≈ <estimate, for information only>
### Slice 2 — <Part title>
- [ ] S2.1 …
<one slice per part of the Idea page, in the order they deliver value; every step fits one sitting>

## 10. Order and parallelism
<what depends on what; what can run at the same time>

## 11. Rollout
<behind which switch, off by default; canary first; the kill switch named and how it is proven>

## 12. Rollback
<the exact steps to undo, rehearsed on a copy before deploy>

## 13. Testing strategy
<the gate suite is the promise checks plus every check born from an attack; interface tests where two pieces meet; test data named; what is deliberately not tested and why>

## 14. Definition of done
<per step: the verify ran with fresh output and a receipt exists; per slice: its part's attacks closed; per build: every promise live>

## 15. Observability
<for each promise, the one metric or log line that proves it in production, and the alert if it stops>

## 16. Failure modes
<for each outside dependency: behaviour when slow, when down, when returning garbage; timeouts and retry limits; safe to run twice; the losing interleaving for any read-modify-write and the guard against it>

## 17. Security and privacy
<which data is sensitive; who may see what, as a role × resource table; the three or four likeliest attacks and the guard for each; where secrets live; nothing sensitive in logs>

## 18. Performance and capacity
<expected volume, the limit the design handles, the cost at that volume>

## 19. Runbook
<how to run it; known failure → the action to take>

## 20. Assumptions and open questions
- A1 <assumption and where it came from>
- Q1 (<who answers>) <question>
- R1 <the biggest risk and its guard>   (up to three R lines; the card shows them)

## 21. Decision log
- <date> <what changed, why, what it affects>
```

## Kept from Compass 0.35: the data-safety rules and where they live now
| Rule | 1.0 home |
|---|---|
| Migration rehearsed on a copy, row count and checksum equal | §6 Data changes; attack class cannot-undo |
| Cross-table invariants (child sums to parent, no orphans) enforced in the database | §6 and spec rules; attack classes wrong-output, data-lost |
| Race analysis: the losing interleaving named and guarded | §16 Failure modes; attack classes duplicate-output, retry |
| Every outside call has a timeout and a retry limit | §16 Failure modes; attack class silent-failure |
| Role × resource access table | §17 Security; attack class wrong-person |
| Sensitive fields named; none in logs | §17 Security; attack class wrong-person |
| Secret scan on the release | Deploy pre-flight (slice 6) |
| Every config key present in production before deploy | Deploy pre-flight (slice 6) |
| Restore point before deploy | Deploy pre-flight (slice 6) |
| Numbers reconciled to an independent figure | Attack class wrong-output ("compute it a second way"); deploy write-back |
