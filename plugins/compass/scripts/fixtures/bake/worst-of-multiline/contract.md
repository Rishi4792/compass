# Fixture — bake worst-of-multiline (union takes worst mem=999 > 512)
bake-window: 5m
bake-bound: err=0 lat=200 mem=512
bake-observed: dur=700 err=0 lat=150 mem=400
bake-observed: dur=600 err=0 lat=150 mem=999
