# Fixture — canary route-smoke-failed (RB3: a recorded non-200 smoke is not green)
canary: prod-slice
canary-reconcile: reconcile 100 100 0 → PASS
canary-route-smoke: /health → HTTP 500 (p95 200ms)
canary-gold-cmd: fetch published-gold from the data-room
canary-slice-cmd: query the live slice metric
