# Fixture — canary no-route-smoke (isolates the route-smoke clause, RB-M4)
canary: prod-slice-5pct
canary-reconcile: reconcile 100 100 0 → PASS
canary-gold-cmd: fetch published-gold from the data-room
canary-slice-cmd: query the canary-slice live metric
