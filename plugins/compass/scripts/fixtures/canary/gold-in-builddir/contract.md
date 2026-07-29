# Fixture — canary gold-in-builddir (gold reads the build own artifact)
canary: prod-slice-5pct
canary-reconcile: reconcile 100 100 0 → PASS
canary-route-smoke: /health → 200
canary-gold-cmd: cat contract.md and sum the column
canary-slice-cmd: query the canary-slice live metric
