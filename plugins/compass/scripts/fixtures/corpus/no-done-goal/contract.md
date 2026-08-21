# Contract — no-done-goal · v1

facets: library
schema-touching: no

## Goal & scope
**Goal:** make the Brief fall back to goal sentence two. This second sentence is the one the Done-means card will show. This third sentence is dropped with no marker at all. This fourth sentence is dropped as well, and it is the reason the fixture exists.

### NOW
1. Carry no Done section and no acceptance bullet.

### LATER
1. Nothing.

### NEVER
1. Gain a `## Done` section — that would silence the path this fixture exists to fire.

## INVARIANTs
- **INV-FALLBACK:** the Done-means card falls back to goal sentence two. → *assert:* the instrument reports doneMeans.goalSentence2.
