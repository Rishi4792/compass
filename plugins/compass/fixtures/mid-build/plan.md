# Plan — toy-shop

### Slice 1 — Skeleton (thin end to end)
- [ ] S1.1 Read the till file and print the total. → P1.1 · verify: `node sales.js | grep total` · ≈ 1 h
- [ ] S1.2 Compare the total to the till export. → P1.2 · verify: `node check.js` exits 0 · ≈ 1 h

### Slice 2 — Stock
- [ ] S2.1 Count stock and send one message under 5. → P2.1 · verify: `node stock.js --dry` prints 1 message · ≈ 2 h

## 20. Assumptions and open questions
- R1 The till export format may change without notice.
- R2 The shop has no internet after 20:00.
