# Fixture — bake stale-loose-first (RB-C3: a loose bake-bound line above the real tight one must not win)
bake-bound: err=999 lat=999 mem=999
bake-window: 5m
bake-bound: err=0 lat=0 mem=0
bake-observed: dur=600 err=5 lat=500 mem=500
