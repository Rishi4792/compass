# Fixture — canary no-reconcile (isolates the reconcile-PASS clause, RB-M4)
canary: prod-slice-5pct
canary-route-smoke: /health → 200
canary-gold-cmd: fetch published-gold from the data-room
canary-slice-cmd: query the canary-slice live metric
