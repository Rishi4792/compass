# Idea — till-tally
title: Till Tally
page: local
for: a small shop owner at closing time, on a phone
hurts: Every evening you add up the day's sales by hand. Last Tuesday it took 25 minutes and was wrong by ₹400.
purpose: See today's sales total the moment you close, without adding anything up.
done: 0 wrong totals in 14 days, and under 10 seconds from opening the app to the number.

### Part 1 — Today's total
picture: money
Open the app and the day's total is already there. One big number, nothing to tap.
- P1.1 See today's total within 10 seconds of opening. → under 10 s
- P1.2 The total matches the till to the rupee. → ₹0 difference
sketch:
```ascii
┌──────────────────────┐
│  Today · Tue 26 Oct  │
│                      │
│      ₹ 18,240        │
│                      │
│  42 sales · last 19:52│
└──────────────────────┘
```

### Part 2 — Low stock nudge
picture: bell
When an item drops below five, you get one message. Never two for the same item on the same day.
- P2.1 One message per item per day when stock drops under 5. → 1 message

## Later
- Weekly sales chart
- Export to the accountant
## Never
- Messages after 22:00
- Any other shop's numbers
