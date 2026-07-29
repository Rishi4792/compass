# Fixture — canary route-decoy (RB4-M1: a failing route + a passing decoy route must block, take-worst)
canary: prod-slice
canary-reconcile: reconcile 100 100 0 → PASS
canary-route-smoke: /checkout → 500
canary-route-smoke: /health → 200
canary-gold-cmd: fetch published-gold external
canary-slice-cmd: query the live slice
