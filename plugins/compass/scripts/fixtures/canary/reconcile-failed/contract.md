# Fixture — canary reconcile-failed (RB3: a recorded non-PASS reconcile is not green)
canary: prod-slice
canary-reconcile: reconcile 90 100 10 → did NOT PASS (drift)
canary-route-smoke: /health → 200
canary-gold-cmd: fetch published-gold from the data-room
canary-slice-cmd: query the live slice metric
