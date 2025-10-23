pdf2csv - simple PDF to CSV helper

This repository contains a small bash script `pdf2csv.sh` that converts text-based
PDFs into CSV files using `pdftotext` (part of the Poppler utils).

When it works:
- Best for PDFs that are text-based (not scanned images).
- Works well when columns are separated by tabs or multiple spaces.

Install dependencies (Windows WSL or Linux/macOS recommended):
- poppler-utils (provides `pdftotext`)
- optional: `column` (usually in util-linux or bsdmainutils)

Examples:
- Convert a single file:
  ./pdf2csv.sh report.pdf report.csv

- Convert only pages 1 through 2:
  ./pdf2csv.sh -p 1-2 report.pdf report.csv

- Convert all PDFs in a directory:
  ./pdf2csv.sh -d ./pdfs

Notes and alternatives:
- For complex tables or PDFs where text extraction fails, use Tabula (Java)
  https://tabula.technology/ or Camelot (Python) https://camelot-py.readthedocs.io/

- On Windows, run this script in WSL, Git Bash, or MSYS2 for best compatibility.

License: MIT
