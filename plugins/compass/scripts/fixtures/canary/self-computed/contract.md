# Fixture — canary self-computed (gold-cmd == slice-cmd)
canary: prod-slice-5pct
canary-reconcile: reconcile 100 100 0 → PASS
canary-route-smoke: /health → 200
canary-gold-cmd: query the canary-slice live metric
canary-slice-cmd: query the canary-slice live metric
