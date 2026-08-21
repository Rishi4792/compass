# auto-advance-unstamped

**How it was found.** Contract §7 permits auto mode to advance WITHOUT asking, on one condition:
the receipt carries `asked=no · reason=auto-mode`, "so every un-asked stage stays visible forever".
Without the reason there is no difference on the page between a stage that was deliberately not
asked and one where the ask was simply skipped.

**This build committed that exact defect against itself** and recorded it at plan step S13: a turn
pushed the rail and cockpit and then ended WITHOUT the AskUserQuestion.

**What must happen.** `asked=no` with no `reason=auto-mode` is REFUSED; with it, accepted.
