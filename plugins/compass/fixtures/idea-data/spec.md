# Spec — fare-history · from idea.md v1
## Rules
- The reader lists every *.pdf in the input folder and records a row per file with pages read. → P1.1
- Each extracted value stores file name and page number. → P1.2
- A spot-check script samples 50 rows and compares to the PDF text layer. → P2.1
## Assumptions (from the scan, not from the person)
- PDFs have a text layer (checked 3 of 14 with pdftotext); scanned pages would need OCR.
- Output is CSV; the analyst opens it in Excel.
## Kind
- data
