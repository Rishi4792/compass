# Plan template — the 21 sections the best engineering teams write

Copy the headings exactly, in this order. Fill every section or write "Not applicable, because …". `skills/plan/SKILL.md` §2 lists what `plan-check` refuses.

```
# Engineering Plan — <slug> · v1 · <date>

## 1. Goal and promises
<the purpose line from idea.md; the promise IDs this plan delivers>

## 2. Non-goals
<what this build will not do, from ## Never and ## Later>

## 3. Current state (read, not assumed)
<what exists today, with real paths; cite one that exists. Empty folder: "greenfield" and the chosen stack.>

## 4. Proposed design
<the pieces, the data flow, the interfaces between pieces, one diagram in a fenced block>

## 5. Alternatives considered
<two or three other designs and why not>

## 6. Data changes
<every data change, expand then contract, reversible, counted against the source, dry-run on a copy; a rule spanning tables enforced by the database itself. "None" if none.>

## 7. Dependencies and blast radius
<new libraries with exact versions; everything touching the changed code that could break>

## 8. Walking skeleton (slice 1)
<the thinnest version that runs end to end through every layer named in §4>

## 9. Slices and steps
### Slice 1 — Skeleton (<what it proves>)
- [ ] S1.1 <what> → P<id>[, P<id>] · verify: <command that proves it> · ≈ <estimate, for information only>
### Slice 2 — <Part title>
- [ ] S2.1 …
<one slice per part, in value order; every step fits one sitting>

## 10. Order and parallelism
<what depends on what; what can run at the same time>

## 11. Rollout
<behind which switch, off by default; canary first; the kill switch named and how it is proven>

## 12. Rollback
<the exact steps to undo, rehearsed on a copy before deploy>

## 13. Testing strategy
<the gate suite is the promise checks plus checks born from attacks; every number checked against one computed independently; test data named; what is not tested and why>

## 14. Definition of done
<step: verify ran, receipt exists; slice: attacks closed; build: every promise live>

## 15. Observability
<per promise: the metric or log line that proves it live, and the alert if it stops>

## 16. Failure modes
<per outside dependency: slow, down, garbage; timeouts and retry limits; safe to run twice; the losing interleaving and its guard>

## 17. Security and privacy
<sensitive data; who may see what (role × resource); the likeliest attacks and guards; where secrets live; nothing sensitive in logs>

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
