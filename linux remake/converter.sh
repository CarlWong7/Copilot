#!/usr/bin/env bash
# converter.sh - Convert PDF to TXT, page-by-page, splitting multi-column pages into separate pages when there is a blank-space vertical separator.
# Usage: ./converter.sh input.pdf output.txt [max_pages]
# Dependencies: pdfinfo, pdftotext (from poppler), python3, fmt (optional)

set -euo pipefail
IFS=$'\n\t'

if [[ "$#" -lt 2 ]]; then
    echo "Usage: $0 input.pdf output.txt [max_pages]" >&2
    exit 2
fi

INPUT_PDF="$1"
OUTPUT_TXT="$2"

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

# Get number of pages
PAGES=$(pdfinfo "$INPUT_PDF" | awk '/^Pages:/ {print $2}')
if [[ -z "$PAGES" ]]; then
    echo "Could not determine number of pages." >&2
    exit 4
fi

# Optional max pages argument
MAX_PAGES=$(( PAGES ))
if [[ ${3-} != "" ]]; then
    if ! [[ "${3}" =~ ^[0-9]+$ ]]; then
        echo "max_pages must be a positive integer" >&2
        exit 5
    fi
    MAX_PAGES=${3}
    if (( MAX_PAGES < 1 )); then
        echo "max_pages must be >= 1" >&2
        exit 5
    fi
fi

# We'll process up to the smaller of PAGES and MAX_PAGES
if (( MAX_PAGES < PAGES )); then
    PAGES_TO_PROCESS=$MAX_PAGES
else
    PAGES_TO_PROCESS=$PAGES
fi
if [[ -z "$PAGES" ]]; then
  echo "Could not determine number of pages." >&2
  exit 4
fi

# Prepare/clear output
: > "$OUTPUT_TXT"

# For each page, extract layout-preserved text and post-process with embedded Python
for ((p=1; p<=PAGES_TO_PROCESS; p++)); do
  PAGE_FILE="$TMPDIR/page-${p}.txt"
  pdftotext -f "$p" -l "$p" -layout -enc UTF-8 "$INPUT_PDF" "$PAGE_FILE"

  # Call python to detect column separators and output column texts to stdout
    # Append the python output directly into the output file so it's saved
    python3 - "$PAGE_FILE" "$p" <<'PY' >> "$OUTPUT_TXT"
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

        # (no footer markers; python output is already redirected into the output file)

done

echo "Conversion complete: $OUTPUT_TXT"
exit 0
