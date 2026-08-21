# clip-guard-exhaustion — the css-clip defence, turned off from inside the page

reachable-argument.mjs:100 — `for (let guard = 0; guard < 5000; guard++)`. Each pass removes the
FIRST clipped element it finds. When the counter runs out the loop simply stops and everything left
is treated as reachable. Direct proof:

    clipped elements=5000  SECRET occurrences still counted REACHABLE = 0
    clipped elements=5001  SECRET occurrences still counted REACHABLE = 1
    clipped elements=6000  SECRET occurrences still counted REACHABLE = 1000

So: emit 5001 empty <i style="display:none"></i> decoys FIRST, then the real clipped remainders.
The decoys eat the budget; the remainders survive the strip and score as reachable.
