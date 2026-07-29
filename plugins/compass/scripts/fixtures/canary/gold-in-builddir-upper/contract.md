# Fixture — canary gold-in-builddir-upper (RB2-M2: CONTRACT.MD resolves on a case-insensitive FS)
canary: prod-slice
canary-reconcile: reconcile 1 1 0 → PASS
canary-route-smoke: /health → 200
canary-gold-cmd: cat CONTRACT.MD and sum
canary-slice-cmd: query the live slice metric
