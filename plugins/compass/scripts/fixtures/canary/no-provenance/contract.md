# Fixture — canary no-provenance (isolates the gold/slice provenance clause, RB-M4)
canary: prod-slice-5pct
canary-reconcile: reconcile 100 100 0 → PASS
canary-route-smoke: /health → 200
canary-gold-cmd: TBD
canary-slice-cmd: query the canary-slice live metric
