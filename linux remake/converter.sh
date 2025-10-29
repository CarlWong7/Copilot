#!/usr/bin/env bash
# converter.sh - Convert PDF to TXT or CSV.
# - Default behavior: convert PDF -> TXT (preserves reflowed paragraphs, splits columns when vertical blank separators exist).
# - New: if output filename ends with .csv, script will convert the first N pages (default 50) to TXT then parse that TXT into CSV
#   with headers: BOOK, CHAPTER, VERSE, DESCRIPTION.
# Usage: ./converter.sh input.pdf output.(txt|csv) [max_pages] [book_name]
# Dependencies: pdfinfo, pdftotext (from poppler), python3

set -euo pipefail
IFS=$'\n\t'

if [[ "$#" -lt 2 ]]; then
    echo "Usage: $0 input.pdf output.(txt|csv) [max_pages] [book_name]" >&2
    exit 2
fi

INPUT_PDF="$1"
OUTPUT_FILE="$2"
MAX_PAGES_ARG=${3-}
BOOK_NAME=${4-}

# Check dependencies
for cmd in pdfinfo pdftotext python3; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Required command not found: $cmd" >&2
    echo "Please install it (e.g. poppler-utils for pdfinfo/pdftotext, and python3)." >&2
    exit 3
  fi
done

TMPDIR=$(mktemp -d -t converter.XXXXXX)
trap 'rm -rf "${TMPDIR}"' EXIT


# Function: pdf_to_txt input.pdf output.txt max_pages
# Processes up to max_pages (if empty, all pages) and appends reflowed text into output.txt
pdf_to_txt() {
  local in_pdf="$1" out_txt="$2" maxp="$3"
  : > "$out_txt"

  # Get number of pages
  local pages
  pages=$(pdfinfo "$in_pdf" | awk '/^Pages:/ {print $2}') || pages=0
  if [[ -z "$pages" || "$pages" -eq 0 ]]; then
    echo "Could not determine number of pages." >&2
    return 4
  fi

  local toproc
  if [[ -n "$maxp" ]]; then
    toproc=$(( pages < maxp ? pages : maxp ))
  else
    toproc=$pages
  fi

  for ((p=1; p<=toproc; p++)); do
    PAGE_FILE="$TMPDIR/page-${p}.txt"
    pdftotext -f "$p" -l "$p" -layout -enc UTF-8 "$in_pdf" "$PAGE_FILE"

    # Call python to detect column separators and output column texts to stdout
    # Append the python output directly into the output file so it's saved
    python3 - "$PAGE_FILE" "$p" <<'PY' >> "$out_txt"
import sys
import textwrap
from pathlib import Path

page_path = Path(sys.argv[1])
page_num = int(sys.argv[2])
text = page_path.read_text(encoding='utf-8')
lines = text.splitlines()
if not lines:
    # empty page: emit a single blank line to preserve paragraph separation
    print('')
    sys.exit(0)

# Normalize tab characters into spaces
lines = [ln.replace('\t', ' ') for ln in lines]
maxlen = max(len(ln) for ln in lines)
# Create padded lines
padded = [ln.ljust(maxlen) for ln in lines]

nlines = len(padded)
# Compute proportion of space at each column
space_prop = []
for j in range(maxlen):
    cnt = 0
    for i in range(nlines):
        if padded[i][j] == ' ':
            cnt += 1
    space_prop.append(cnt / float(nlines))

# Find runs of columns that are mostly blank -> candidate separators
THRESH=0.96      # proportion of lines that must be spaces for that column
MIN_RUN=3        # minimum width (columns) of blank run to consider it a separator
runs = []
start = None
for j,sp in enumerate(space_prop):
    if sp >= THRESH:
        if start is None:
            start = j
    else:
        if start is not None:
            if (j - start) >= MIN_RUN:
                runs.append((start, j-1))
            start = None
# tail
if start is not None and (maxlen - start) >= MIN_RUN:
    runs.append((start, maxlen-1))

# Filter runs that are too close to page edges (we don't want to chop at margins)
filtered_runs = []
for s,e in runs:
    # ignore runs that touch very near left or right edges
    if s <= 2 or e >= (maxlen - 3):
        continue
    filtered_runs.append((s,e))

# If no separators found, treat as single column
if not filtered_runs:
    # Reflow text preserving paragraphs
    def reflow_text(lines):
        paras = []
        cur = []
        for ln in lines:
            if ln.strip() == '':
                if cur:
                    paras.append(' '.join(w for w in ' '.join(cur).split()))
                    cur = []
                else:
                    paras.append('')
            else:
                cur.append(ln.rstrip())
        if cur:
            paras.append(' '.join(w for w in ' '.join(cur).split()))
        out = []
        for p in paras:
            if p == '':
                out.append('')
            else:
                out.extend(textwrap.wrap(p, width=80))
        return '\n'.join(out)

    reflowed = reflow_text(lines)
    # emit reflowed text for single-column page
    print(reflowed)
    print('\n')
    sys.exit(0)

# Otherwise, build column slices using separator midpoints
cuts = []
for (s,e) in filtered_runs:
    cuts.append((s + e) // 2)
# Build column ranges
col_ranges = []
prev = 0
for c in cuts:
    col_ranges.append((prev, c))
    prev = c
col_ranges.append((prev, maxlen))

# For each column, extract, trim trailing spaces and reflow
for idx, (cs, ce) in enumerate(col_ranges, start=1):
    col_lines = [ln[cs:ce].rstrip() for ln in padded]
    # Remove leading/trailing empty lines
    while col_lines and col_lines[0].strip() == '':
        col_lines.pop(0)
    while col_lines and col_lines[-1].strip() == '':
        col_lines.pop()
    if not col_lines:
        continue
    # Reflow preserving paragraphs
    def reflow_text(lines):
        paras = []
        cur = []
        for ln in lines:
            if ln.strip() == '':
                if cur:
                    paras.append(' '.join(w for w in ' '.join(cur).split()))
                    cur = []
                else:
                    paras.append('')
            else:
                cur.append(ln.rstrip())
        if cur:
            paras.append(' '.join(w for w in ' '.join(cur).split()))
        out = []
        for p in paras:
            if p == '':
                out.append('')
            else:
                out.extend(textwrap.wrap(p, width=80))
        return '\n'.join(out)

    reflowed = reflow_text(col_lines)
    # emit reflowed text for this column (no markers)
    print(reflowed)
    print('\n')

PY
  done
}


# Function: txt_to_csv input.txt output.csv book_name
# A simple parser that splits on verse numbers at line starts and emits CSV rows
txt_to_csv() {
  local in_txt="$1" out_csv="$2" book_name="$3"
  python3 - "$in_txt" "$out_csv" "$book_name" <<'PY'
import sys
import csv
from pathlib import Path
import re

in_path = Path(sys.argv[1])
out_path = Path(sys.argv[2])
book = sys.argv[3] if len(sys.argv) > 3 else ''
text = in_path.read_text(encoding='utf-8')

# Normalize newlines
text = text.replace('\r\n', '\n')

# We'll scan for two kinds of markers at line starts (multiline mode):
# 1) Chapter marker: digits immediately followed by letters (e.g. "3Now...") -> chapter=N, verse=1
# 2) Verse marker: digits followed by whitespace (e.g. "17 When...") -> verse=M, chapter stays the last seen
pattern = re.compile(r'(?m)^\s*(?:(\d+)\s+|(\d+)(?=[A-Za-z]))')

rows = []
current_chapter = ''
matches = list(pattern.finditer(text))
if matches:
    for i, m in enumerate(matches):
        if m.group(1):
            # standard verse marker (number + space)
            verse = m.group(1)
            # description starts after the matched marker
            start = m.end()
            end = matches[i+1].start() if i+1 < len(matches) else len(text)
            desc = text[start:end].strip().replace('\n', ' ')
            if desc:
                rows.append((book, current_chapter, verse, ' '.join(desc.split())))
        else:
            # chapter marker (digits immediately followed by text) -> chapter=N, verse=1
            chap = m.group(2)
            current_chapter = chap
            verse = '1'
            start = m.end()
            end = matches[i+1].start() if i+1 < len(matches) else len(text)
            desc = text[start:end].strip().replace('\n', ' ')
            if desc:
                rows.append((book, current_chapter, verse, ' '.join(desc.split())))
else:
    # No clear markers: split into paragraphs
    paras = [p.strip() for p in re.split(r'\n\s*\n', text) if p.strip()]
    for p in paras:
        rows.append((book, '', '', ' '.join(p.split())))

with out_path.open('w', encoding='utf-8', newline='') as f:
    w = csv.writer(f)
    w.writerow(['BOOK','CHAPTER','VERSE','DESCRIPTION'])
    for r in rows:
        w.writerow(r)

print(f'Wrote CSV with {len(rows)} rows to {out_path}', file=sys.stderr)
PY
}


# Main: if output filename ends with .csv, run pdf->txt (up to max pages) then txt->csv
if [[ "${OUTPUT_FILE,,}" == *.csv ]]; then
  # default max pages for CSV conversion is 50 unless provided
  if [[ -z "$MAX_PAGES_ARG" ]]; then
    MAX_PAGES=50
  else
    MAX_PAGES="$MAX_PAGES_ARG"
  fi
  INTERMEDIATE="$TMPDIR/intermediate.txt"
  pdf_to_txt "$INPUT_PDF" "$INTERMEDIATE" "$MAX_PAGES"
  txt_to_csv "$INTERMEDIATE" "$OUTPUT_FILE" "$BOOK_NAME"
  echo "CSV conversion complete: $OUTPUT_FILE"
  exit 0
fi

# Otherwise default: produce TXT (honor optional max pages arg)
if [[ -n "$MAX_PAGES_ARG" ]]; then
  pdf_to_txt "$INPUT_PDF" "$OUTPUT_FILE" "$MAX_PAGES_ARG"
else
  pdf_to_txt "$INPUT_PDF" "$OUTPUT_FILE" ""
fi

exit 0
