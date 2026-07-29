# Fixture — canary breach-rollback (BREACH + rollback-fired; never promotes)
canary: prod-slice-5pct
canary-reconcile: reconcile 100 100 0 → PASS
canary-route-smoke: /health → 200
canary-gold-cmd: fetch published-gold from the data-room figure
canary-slice-cmd: query the canary-slice live metric
burn-rate: BREACH error budget spike
rollback-fired: git reset --hard prev-tag
