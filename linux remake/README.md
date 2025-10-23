# pdf2csv.sh

Small helper to convert PDF files into CSV files with the columns:

- BOOK
- CHAPTER
- VERSE
- DESCRIPTION

Requirements
------------

- pdftotext (from poppler-utils) must be installed and available in PATH.
- python3 (3.6+) must be installed.

On Windows you can use WSL, Git Bash with poppler installed, or Cygwin.

Usage
-----

Run the script with one or more PDF filenames:

```bash
./pdf2csv.sh file1.pdf file2.pdf
```

Each input file will produce a CSV next to it with the same basename.

Notes and assumptions
---------------------

- The script uses `pdftotext -layout` to extract text from the PDF. This
  works best for PDFs with selectable text. Scanned images will not parse
  unless OCR is run first (e.g., with Tesseract).
- Parsing is heuristic: the embedded Python tries to match lines containing
  a book name followed by a chapter and optional verse. If a line can't be
  parsed, the entire line is placed in DESCRIPTION and other fields are empty.
- You can adapt the regex inside the script for your PDF's specific layout.

Improvements you might add
--------------------------

- Use OCR for scanned PDFs (tesseract + tesseract-ocr language packs).
- Improve grouping of multi-line descriptions (merge lines belonging to
  the same verse).
- Support output to a single combined CSV for multiple PDFs.
