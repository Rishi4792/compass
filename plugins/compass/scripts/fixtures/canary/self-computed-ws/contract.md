# Fixture — canary self-computed-ws (RB-C2: gold==slice modulo trailing whitespace must be SELF-COMPUTED)
canary: prod-slice
canary-reconcile: reconcile 1 1 0 → PASS
canary-route-smoke: /health → 200
canary-gold-cmd: query the slice metric
canary-slice-cmd: query the slice metric 
