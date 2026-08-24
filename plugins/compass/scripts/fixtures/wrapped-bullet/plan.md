# plan — wrapped-bullet

## Step checklist

- [ ] **S1** A short step. — VERIFY: it runs.

## DB / migration · Dependencies · API

- **Concurrency — N/A.** Every check is a pure read; there is no read-modify-write on
  SENTINELTAILSURVIVED, which is the half a wrapped bullet used to lose.
- **API — N/A.** No endpoint.
