# The failure catalogue — the ways software fails

Compass brings this list. The person never writes failure modes. Each class has: what it means, the kinds of product it applies to, how likely it is per kind (1 to 5), how much damage a break does (1 to 5), the attack recipe, what a demonstrated break looks like, the shape of the permanent check that is added when it breaks, and its scope: `promise` classes are attacked per promise, `product` classes once per build. `scripts/compass attacks` reads the `key:` lines; reviewers read the prose.

## wrong-output
name: Wrong output
scope: promise
damage: 5
applies: visual data service
likely: data=5 service=4 visual=3
attack: Compute the promised value a second way, independently of the product's own code, for inputs at the edges the promise covers: empty, one item, the maximum, duplicates, yesterday's data, a different time zone, a leap day. Compare.
break: For an input the promise covers, the product's output differs from the independent value.
check: A test that feeds that exact input and asserts the independent value.

## missing-output
name: Missing output
scope: promise
damage: 4
applies: visual data service
likely: data=4 service=4 visual=3
attack: Count what went in and what came out. Feed a batch where every item is distinct and traceable, then look for items that vanished, were skipped on error, or fell off a page boundary.
break: An item that went in and should appear does not appear, with no error shown.
check: A test that feeds a traceable batch and asserts the count and the presence of each item.

## duplicate-output
name: Duplicate output
scope: promise
damage: 3
applies: visual data service
likely: data=4 service=4 visual=2
attack: Run the same action twice, run two at once, retry after a simulated failure halfway, and reload the page mid-save. Look for two of anything that should be one.
break: The same item, message or row appears twice after an action the promise describes as one.
check: A test that performs the action twice and asserts one result.

## stale-data
name: Stale data
scope: promise
damage: 4
applies: visual data service
likely: data=4 service=3 visual=4
attack: Change the source, then read through every path that shows the value: the page, the cache, the saved file, the message. Time how long each stays old.
break: A path shows the old value after the promise says it should show the new one.
check: A test that changes the source and asserts the new value on the slowest path within the promised time.

## data-lost
name: Data lost
scope: product
damage: 5
applies: visual data service
likely: data=3 service=4 visual=3
attack: Save, then crash: kill the process mid-write, fill the disk, pull the network during a save, reload during a save, run the migration twice. Then look for what was saved.
break: Something the person saved is gone, or an older version has replaced a newer one.
check: A test that saves, interrupts in the same way, and asserts the saved item is intact.

## wrong-person
name: Wrong person sees data
scope: product
damage: 5
applies: visual service
likely: visual=4 service=4 data=1
attack: As a second user or a logged-out visitor, request every page, file and address the first user can reach, including guessed IDs one above and one below theirs. Also search logs and messages for another person's values.
break: Any value belonging to one person is shown or sent to another without that person's action.
check: A test that requests the resource as the wrong user and asserts refusal or emptiness.

## cannot-undo
name: Cannot undo
scope: product
damage: 4
applies: visual data service
likely: data=4 service=3 visual=3
attack: Perform the change the promise describes, then follow the documented undo. Time it. Then check the data, the schema and the running version are back to before.
break: The undo fails, needs steps nobody wrote down, or leaves a difference behind.
check: A test that applies and reverts, asserting identical state before and after.

## bad-input
name: Breaks on bad input
scope: promise
damage: 3
applies: visual data service
likely: visual=4 service=4 data=4
attack: Feed the empty string, 10,000 characters, emoji, a right-to-left script, HTML and script tags, a negative number, a number as text, a date in the wrong format, a file of the wrong type, and a file of 100 MB.
break: A crash, a hang, a blank page, a saved value that is not what was typed, or script that runs.
check: A test for each input that broke, asserting the promised handling.

## retry
name: Breaks on retry
scope: promise
damage: 4
applies: data service
likely: data=5 service=5 visual=2
attack: Run the job or request again right after it succeeds, again after it fails halfway, and twice at the same time. Compare the end state with a single clean run.
break: The end state after a retry differs from the end state after one clean run.
check: A test that runs twice and asserts the same end state as once.

## load
name: Breaks under load
scope: product
damage: 3
applies: visual data service
likely: service=4 data=3 visual=3
attack: Use the real volume the Idea page names, then ten times it. Measure the promised time and memory. Look for work that grows with the square of the count.
break: The promised time is missed at the named volume, or the product falls over at ten times it.
check: A test that runs at the named volume and asserts the promised time.

## silent-failure
name: Fails silently
scope: promise
damage: 4
applies: visual data service
likely: data=4 service=4 visual=3
attack: Make each dependency fail: unplug the network, return an error from the source, corrupt the input file, revoke a permission. Watch what the person is told and what the log says.
break: The product reports success, or nothing, while the promised result did not happen.
check: A test that makes the dependency fail and asserts a visible error and a log line.

## regression
name: Breaks what worked
scope: product
damage: 4
applies: visual data service
likely: visual=4 service=4 data=4
attack: Run every check born from an earlier break, and walk the three most-used existing paths that share code with the change.
break: A check that passed before this part now fails, or an existing path behaves differently.
check: The existing check stays; a new one covers the path that broke.

## picture-mismatch
name: Does not match the approved picture
scope: promise
damage: 3
applies: visual
likely: visual=5 data=1 service=1
attack: Open the built screen at phone and desktop width with real data. Compare against the approved sketch: what is on the screen, in what order, what is one tap away, what is hidden.
break: An element the sketch shows is missing or moved, or an element the sketch does not show demands attention.
check: A screenshot test at both widths, compared to the approved sketch's element list.
