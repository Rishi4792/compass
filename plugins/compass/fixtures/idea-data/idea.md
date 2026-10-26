# Idea — fare-history
title: Fare History
page: local
for: an analyst who needs last year's airline fares in a spreadsheet
hurts: The fares live in 14 PDFs. Last month it took two days to type them in, and three numbers were wrong.
exists: Typing the PDFs into a spreadsheet: two days per batch · Asking the airline: no answer in a month
because: Two days of typing per batch and three wrong numbers last time; no tool keeps the page reference.
purpose: Turn the fare PDFs into one checked table, once, with every number traceable to its page.
done: 14 PDFs in, 1 table out, 0 numbers that differ from the PDF on a 50-row spot check.

## Journey
- box: 14 PDFs land in a folder
- search: Every fare table is read
- chart: One checked table opens in Excel

### Part 1 — Read the PDFs
picture: box
Point it at the folder. It reads every fare table and keeps the page it came from.
- P1.1 Every PDF in the folder is read, none skipped. → 14 of 14
- P1.2 Every number carries the page it came from. → 100% traced

### Part 2 — One checked table
picture: chart
One table, one row per fare, with a checked column that shows the spot-check result.
- P2.1 A 50-row spot check against the PDFs finds no differences. → 0 of 50

## Never
- Guessing a number the PDF does not contain
