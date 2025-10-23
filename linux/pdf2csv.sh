#!/usr/bin/env bash
# pdf2csv.sh - extract structured verses into CSV with headers: BOOK,CHAPTER,VERSE,DESCRIPTION
# Usage: pdf2csv.sh [options] <input.pdf> [output.csv]
# Options:
#   -d, --dir <directory>   Process all PDFs in directory
#   -p, --pages <range>     Pages range to extract, e.g. 1-3
#   -h, --help              Show help

set -euo pipefail
IFS=$'\n\t'

show_help() {
  cat <<EOF
Usage: $(basename "$0") [options] <input.pdf> [output.csv]

Converts PDF text to a CSV with columns: BOOK, CHAPTER, VERSE, DESCRIPTION.
This script requires `pdftotext` and `python3` to be available.

Options:
  -d, --dir <directory>   Process all PDFs in directory
  -p, --pages <range>     Pages range to extract, e.g. 1-3
  -h, --help              Show this help

Examples:
  $(basename "$0") report.pdf report.csv
  $(basename "$0") -p 1-2 report.pdf report.csv
  $(basename "$0") -d ./pdfs
EOF
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Error: required command '$1' not found. Install it and retry." >&2
    exit 2
  fi
}

require_cmd pdftotext
require_cmd python3

# defaults
PAGES=""
PROCESS_DIR=""

# parse args
POSITIONAL=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      show_help; exit 0;;
    -d|--dir)
      PROCESS_DIR="$2"; shift 2;;
    -p|--pages)
      PAGES="$2"; shift 2;;
    --)
      shift; break;;
    -*|--*)
      echo "Unknown option $1"; show_help; exit 1;;
    *)
      POSITIONAL+=("$1"); shift;;
  esac
done
set -- "${POSITIONAL[@]}"

convert_pdf() {
  local input_pdf="$1"
  local output_csv="$2"
  local tmp_txt
  tmp_txt=$(mktemp --suffix=.txt)

  # ensure tmp cleaned
  trap 'rm -f "$tmp_txt"' RETURN

  echo "Processing: $input_pdf -> $output_csv"

  # extract text (use default non-layout extraction; non-layout output matched parser heuristics better)
  pdftotext_args=()
  if [[ -n "$PAGES" ]]; then
    # simple parse of X-Y format
    pdftotext_args+=("-f" "${PAGES%%-*}" "-l" "${PAGES##*-}")
  fi
  pdftotext_args+=("$input_pdf" "$tmp_txt")

  pdftotext "${pdftotext_args[@]}" || { echo "pdftotext failed for $input_pdf" >&2; return 1; }

  # call embedded Python parser to generate CSV with strict headers
  python3 - "$tmp_txt" "$output_csv" <<'PY'
import sys, re, csv

in_path = sys.argv[1]
out_path = sys.argv[2]

text = open(in_path, 'r', encoding='utf-8', errors='replace').read()
lines = [l.rstrip() for l in text.splitlines()]

# Full canonical Protestant Bible book list to improve book detection
BOOKS = [
  'Genesis','Exodus','Leviticus','Numbers','Deuteronomy','Joshua','Judges','Ruth',
  '1 Samuel','2 Samuel','1 Kings','2 Kings','1 Chronicles','2 Chronicles','Ezra','Nehemiah','Esther',
  'Job','Psalms','Proverbs','Ecclesiastes','Song of Solomon','Isaiah','Jeremiah','Lamentations','Ezekiel','Daniel',
  'Hosea','Joel','Amos','Obadiah','Jonah','Micah','Nahum','Habakkuk','Zephaniah','Haggai','Zechariah','Malachi',
  'Matthew','Mark','Luke','John','Acts','Romans','1 Corinthians','2 Corinthians','Galatians','Ephesians','Philippians','Colossians',
  '1 Thessalonians','2 Thessalonians','1 Timothy','2 Timothy','Titus','Philemon','Hebrews','James','1 Peter','2 Peter','1 John','2 John','3 John','Jude','Revelation'
]

def normalize_book(s):
  s = s.strip()
  s = re.sub(r'\b(1st|2nd|3rd|1st|2nd|3rd)\b', lambda m: m.group(0)[0], s, flags=re.IGNORECASE)
  s = re.sub(r'\s+', ' ', s)
  return s.lower()

books_norm = {normalize_book(b): b for b in BOOKS}

def is_book_line(line):
  key = normalize_book(re.sub(r'[^A-Za-z0-9\s]', '', line))
  return key in books_norm

def is_toc_entry(desc):
  if not desc:
    return False
  d = desc.strip()
  if re.match(r'^(\d+(st|nd|rd|th)?\b)', d, flags=re.IGNORECASE):
    rest = re.sub(r'^(\d+(st|nd|rd|th)?\s*)', '', d, flags=re.IGNORECASE).strip()
    if normalize_book(rest) in books_norm:
      return True
  if normalize_book(d) in books_norm:
    return True
  if re.match(r'^(contents|table of contents|page)\b', d, flags=re.IGNORECASE):
    return True
  return False

records = []
current_book = ''
current_chapter = ''

i = 0
N = len(lines)
while i < N:
  line = lines[i].strip()
  if not line:
    i += 1; continue

  # detect book title
  if is_book_line(line):
    current_book = books_norm[normalize_book(re.sub(r'[^A-Za-z0-9\s]', '', line))]
    current_chapter = ''
    i += 1; continue

  # chapter number
  if re.match(r'^\d+$', line):
    prev = ''
    j = i-1
    while j >= 0 and not lines[j].strip():
      j -= 1
    if j >= 0:
      prev = lines[j].strip()
    if is_book_line(prev) or not current_chapter:
      current_chapter = line
      i += 1; continue

  # inline verse
  m_inline = re.match(r'^(\d+)\s*(\S.*)$', line)
  if m_inline:
    verse = m_inline.group(1)
    desc = m_inline.group(2).strip()
    if is_toc_entry(desc):
      i += 1; continue
    # require book & chapter context
    if not current_book or not current_chapter:
      i += 1; continue
    # collect continuation
    j = i+1
    parts = [desc]
    while j < N:
      nxt = lines[j].strip()
      if not nxt:
        j += 1; continue
      if re.match(r'^(\d+)\b', nxt):
        break
      if is_book_line(nxt):
        break
      parts.append(nxt)
      j += 1
    desc_full = ' '.join(' '.join(p.split()) for p in parts)
    if len(desc_full) < 3:
      i = j; continue
    records.append([current_book, current_chapter, verse, desc_full])
    i = j; continue

  # digit-only verse
  m_digit = re.match(r'^(\d+)$', line)
  if m_digit:
    verse = m_digit.group(1)
    if not current_book or not current_chapter:
      i += 1; continue
    j = i+1
    parts = []
    while j < N:
      nxt = lines[j].strip()
      if not nxt:
        j += 1; continue
      if re.match(r'^(\d+)\b', nxt):
        break
      if is_book_line(nxt):
        break
      parts.append(nxt)
      j += 1
    desc_full = ' '.join(' '.join(p.split()) for p in parts)
    if not desc_full or is_toc_entry(desc_full) or len(desc_full) < 3:
      i = j; continue
    records.append([current_book, current_chapter, verse, desc_full])
    i = j; continue

  # continuation: append to previous record if exists
  if records:
    last = records[-1]
    extra = ' '.join(line.split())
    if extra:
      if last[3]:
        last[3] = last[3] + ' ' + extra
      else:
        last[3] = extra
  i += 1

# write CSV
with open(out_path, 'w', newline='', encoding='utf-8') as out:
  w = csv.writer(out)
  w.writerow(['BOOK','CHAPTER','VERSE','DESCRIPTION'])
  for r in records:
    w.writerow([ (s if s is not None else '') for s in r ])

PY
}

# process directory
if [[ -n "$PROCESS_DIR" ]]; then
  if [[ ! -d "$PROCESS_DIR" ]]; then
    echo "Directory not found: $PROCESS_DIR" >&2; exit 1
  fi
  shopt -s nullglob
  for f in "$PROCESS_DIR"/*.pdf; do
    out="${f%.*}.csv"
    convert_pdf "$f" "$out"
  done
  shopt -u nullglob
  exit 0
fi

# single file processing
if [[ $# -lt 1 ]]; then
  echo "Missing input PDF" >&2; show_help; exit 1
fi

INPUT_PDF="$1"
OUTPUT_CSV="${2:-${INPUT_PDF%.*}.csv}"

if [[ ! -f "$INPUT_PDF" ]]; then
  echo "Input file not found: $INPUT_PDF" >&2; exit 1
fi

convert_pdf "$INPUT_PDF" "$OUTPUT_CSV"

