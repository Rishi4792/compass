# Fixture — bake numeric-recon-prose (RB-C1: numeric bound with "reconciled" prose must stay NUMERIC)
bake-window: 5m
bake-bound: err=0 lat=200 mem=512 — reconciled against prod
bake-observed: dur=600 err=0 lat=150 mem=888888
