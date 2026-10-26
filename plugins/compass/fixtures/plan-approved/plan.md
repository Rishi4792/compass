# Plan — toy-shop · v1

## 1. Goal and promises
A daily sales total that matches the till, and one stock message a day. Promises P1.1, P1.2 and P2.1 are on the Idea page.

## 2. Non-goals
- No online dashboard. No second shop.

## 3. Current state (read, not assumed)
Checked: `sales.js` reads `till.csv`; `check.js` compares; `stock.js` counts stock. No tests yet.

## 4. Proposed design
Three small scripts run by hand once a day; the total prints in the terminal.

## 5. Alternatives considered
A spreadsheet: rejected, because the till export changes shape and nobody maintains formulas.

## 6. Data changes
None.

## 7. Dependencies and blast radius
Only the till export file. Nothing else reads it.

## 8. Walking skeleton
Read the till file, print the total, compare it: the whole path in two steps.

## 9. Slices and steps
### Slice 1 — Skeleton (thin end to end)
- [ ] S1.1 Read the till file and print the total. → P1.1 · verify: `node sales.js till.csv` → total · ≈ 1 h
- [ ] S1.2 Compare the total to the till export. → P1.2 · verify: `node check.js` → ok · ≈ 1 h

### Slice 2 — Stock
- [ ] S2.1 Count stock and send one message under 5. → P2.1 · verify: `node stock.js --dry` → 1 message · ≈ 2 h

## 10. Order and parallelism
Slice 1, then slice 2. Nothing runs in parallel.

## 11. Rollout
All at once, because one person uses it.

## 12. Rollback
Undo: `git checkout v0 -- sales.js check.js stock.js`.

## 13. Testing strategy
The three verify commands are the gate suite, plus any check born from a break.

## 14. Definition of done
Every step proven by its command; every promise measured on the shop's machine.

## 15. Observability
The total prints with a date line; a missing date is the alarm.

## 16. Failure modes
Till file absent → the script says so and exits non-zero. Safe to run twice.

## 17. Security and privacy
Sales totals only; no names. Nothing leaves the machine.

## 18. Performance and capacity
Under 1 s for a 10,000-row file.

## 19. Runbook
Run: node sales.js
Total missing → check till.csv exists

## 20. Assumptions and open questions
- R1 The till file could change shape without warning. Guard: a check that fails loudly on an unknown column.
- R2 The shop has no internet after 20:00. Guard: everything works offline; nothing waits on the network.

## 21. Decision log
- 2026-10-20 plan v1 approved on one screen.
