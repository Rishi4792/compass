## RECEIPT — idea · toy-shop · approved · 2026-10-20T09:00:00Z
- [x] decision: approved by reading the page
## RECEIPT — plan · toy-shop · approved · 2026-10-20T10:00:00Z
- [x] decision: approved the plan on one screen
## RECEIPT — build · toy-shop · step S1.1 proven · 2026-10-21T09:00:00Z
- [x] verify: `node sales.js | grep total` → total 4,210
## RECEIPT — build · toy-shop · step S1.2 proven · 2026-10-21T10:00:00Z
- [x] verify: `node check.js` → exit 0
## RECEIPT — attack · toy-shop · A1 P1.1 attempt 1 held · 2026-10-21T11:00:00Z
- [x] class: wrong output · time box 10 min
## RECEIPT — attack · toy-shop · A2 P1.2 attempt 1 broke · 2026-10-21T11:20:00Z
- [x] reproduction: `node check.js --date 2026-10-19` → exit 1 (refund rows ignored)
## RECEIPT — build · toy-shop · fix A2 · 2026-10-21T12:00:00Z
- [x] check added: tests/refunds.test.js
## RECEIPT — attack · toy-shop · A2 P1.2 attempt 2 held · 2026-10-21T12:30:00Z
- [x] reproduction re-run: `node check.js --date 2026-10-19` → exit 0
## RECEIPT — build · toy-shop · step S2.1 proven · 2026-10-22T09:00:00Z
- [x] verify: `node stock.js --dry` → 1 message
- [x] decision: refunds count as negative sales
## RECEIPT — attack · toy-shop · A3 P2.1 attempt 1 held · 2026-10-22T10:00:00Z
- [x] class: duplicate output · time box 10 min
## RECEIPT — deploy · toy-shop · released · 2026-10-23T08:00:00Z
- [x] deploy: `./deploy.sh` → ok
## RECEIPT — deploy · toy-shop · writeback · 2026-10-23T09:00:00Z
- [x] P1.1: live 1 line ✓
- [x] P1.2: live 0 difference ✓
- [x] P2.1: live 1 message ✓
- [x] leftover: stock count ignores items with no barcode (accepted in writing)
