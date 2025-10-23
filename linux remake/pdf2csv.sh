#!/usr/bin/env bash
# pdf2csv.sh
# Convert one or more PDF files into CSV files with headers:
# BOOK,CHAPTER,VERSE,DESCRIPTION
#
# Requirements:
# - pdftotext (part of poppler-utils)
# - python3 (for more robust parsing)

set -euo pipefail

show_help() {
  cat <<EOF
Usage: $0 [options] <file1.pdf> [file2.pdf ...]

Converts PDF(s) to CSV(s) with header: BOOK,CHAPTER,VERSE,DESCRIPTION

Options:
  -h, --help    Show this help message and exit

Notes:
 - The script uses pdftotext to extract text and an embedded Python parser
   to convert lines into CSV rows. It's tolerant: when a line cannot be
   parsed into book/chapter/verse the whole line is placed in DESCRIPTION.
 - Output CSV is written next to each input PDF with the same basename.
 - On Windows use WSL, Git Bash, or Cygwin where pdftotext is available.
EOF
}

if [[ ${#@} -eq 0 ]]; then
  show_help
  exit 1
fi

for arg in "$@"; do
  if [[ "$arg" == "-h" || "$arg" == "--help" ]]; then
    show_help
    exit 0
  fi
done

command -v pdftotext >/dev/null 2>&1 || { echo "Error: pdftotext not found. Install poppler-utils." >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "Error: python3 not found." >&2; exit 2; }

process_pdf() {
  local pdf="$1"
  if [[ ! -f "$pdf" ]]; then
    echo "Warning: '$pdf' not found, skipping." >&2
    return
  fi

  local base dir out_txt out_csv
  base="$(basename "$pdf")"
  dir="$(dirname "$pdf")"
  out_txt="$dir/${base%.*}.txt"
  out_csv="$dir/${base%.*}.csv"

  echo "Converting '$pdf' -> '$out_csv'..."

  # extract text (preserve layout as best-effort)
  pdftotext -layout "$pdf" "$out_txt"


  # Use embedded python to parse the text into CSV
  # NOTE: heredoc is unquoted so shell variables $out_txt and $out_csv are expanded
  python3 - <<PY
import sys, csv, re

txt_path = r"""$out_txt"""
csv_path = r"""$out_csv"""

def normalize_space(s):
  return re.sub(r"\s+", " ", s).strip()

# List of common Bible books to detect headings (simple forms)
BOOKS = [
"Genesis","Exodus","Leviticus","Numbers","Deuteronomy","Joshua","Judges","Ruth",
"1 Samuel","2 Samuel","1 Kings","2 Kings","1 Chronicles","2 Chronicles","Ezra","Nehemiah","Esther",
"Job","Psalms","Psalm","Proverbs","Ecclesiastes","Song of Solomon","Song of Songs",
"Isaiah","Jeremiah","Lamentations","Ezekiel","Daniel","Hosea","Joel","Amos","Obadiah","Jonah","Micah",
"Nahum","Habakkuk","Zephaniah","Haggai","Zechariah","Malachi",
"Matthew","Mark","Luke","John","Acts","Romans","1 Corinthians","2 Corinthians","Galatians","Ephesians",
"Philippians","Colossians","1 Thessalonians","2 Thessalonians","1 Timothy","2 Timothy","Titus","Philemon",
"Hebrews","James","1 Peter","2 Peter","1 John","2 John","3 John","Jude","Revelation"
]

BOOKS_NORMAL = [b.lower() for b in BOOKS]

# tokens found in book names (e.g., 'samuel', 'kings', 'corinthians') used to detect TOC fragments
BOOKS_TOKENS = set()
for _b in BOOKS_NORMAL:
  for _t in re.findall(r"[a-z0-9]+", _b):
    BOOKS_TOKENS.add(_t)

# common words that indicate a description/preface/intro heading
DESCRIPTION_HEADINGS = [
  'about', 'introduction', 'preface', 'contents', 'table of contents', 'copyright', 'acknowledgement', 'acknowledgements'
]

def find_book_in_line(line):
  l = line.strip()
  low = l.lower()

  # common numeric prefixes mapping (roman/ordinal/word -> digit)
  prefix_map = {
    'i': '1', 'ii': '2', 'iii': '3', '1st': '1', '2nd': '2', '3rd': '3',
    'first': '1', 'second': '2', 'third': '3'
  }

  # try direct startswith (e.g., 'Genesis', 'Psalms')
  for b, bn in zip(BOOKS, BOOKS_NORMAL):
    if low.startswith(bn):
      return b

  # try patterns with numeric prefixes: '1 Samuel', '1st Samuel', 'I Samuel', 'First Samuel'
  for b, bn in zip(BOOKS, BOOKS_NORMAL):
    last_word = bn.split()[-1]
    # regex to capture optional prefix + book last word, allowing glued forms like '1Samuel'
    m = re.match(rf'^(?:(?P<prefix>\d+|[ivx]+|\w+st|\w+nd|\w+rd|first|second|third)\s*)?{re.escape(last_word)}\b', low, re.I)
    if m:
      pref = m.group('prefix') or ''
      if pref:
        pk = pref.lower().rstrip('.').replace('th','').replace('nd','').replace('st','').replace('rd','')
        pk = pk.strip()
        if pk in prefix_map:
          num = prefix_map[pk]
        elif re.match(r'^\d+$', pk):
          num = pk
        else:
          num = None
        if num:
          # construct canonical book name like '1 Samuel' or '1 Kings'
          # if book has spaces, take full form after the number (e.g., '1 Corinthians')
          name_parts = b.split(' ', 1)
          if len(name_parts) == 2 and name_parts[0].isdigit():
            # book entry already contains numeric prefix like '1 Samuel' in BOOKS; return as-is
            return b
          return f"{num} {name_parts[-1]}"
        else:
          # matched last word without prefix (e.g., 'Samuel' alone)
          # only return the book if the whole line equals the book name (avoid TOC fragments)
          if low.strip() == bn or low.strip() == last_word:
            return b

  return None

def is_description_heading(line):
  """Return True when the line looks like a description/preface heading to skip.

  Heuristics:
  - contains long-known phrases like 'new international version' or 'table of contents'
  - starts with common heading words (about, preface, contents, introduction)
  - short all-caps lines (likely centered headings)
  - lines that contain multiple book tokens (e.g., 'Kings Philippians')
  """
  l = line.strip()
  if not l:
    return False
  low = l.lower()
  # obvious long phrases
  if 'new international version' in low or 'table of contents' in low:
    return True
  # starts with known heading words
  for kw in DESCRIPTION_HEADINGS:
    if low.startswith(kw) or low == kw:
      return True
  # short uppercase centered headings (heuristic)
  words = l.split()
  if 0 < len(words) <= 5 and l.upper() == l and any(c.isalpha() for c in l):
    return True
  # if line contains multiple book-name tokens, consider it TOC/heading
  tokens = re.findall(r"[a-z0-9]+", low)
  token_hits = sum(1 for t in tokens if t in BOOKS_TOKENS)
  if token_hits >= 2:
    return True
  return False

rows = []
last_row = None
current_book = ''
current_chapter = ''
started = False   # don't emit rows until we see a reliable verse with book context
preface = []      # collect initial lines (TOC, title pages) -- will be discarded to avoid polluting CSV

with open(txt_path, 'r', encoding='utf-8', errors='replace') as f:
  raw_lines = [normalize_space(line) for line in f]

# iterate with index so we can look ahead and skip page numbers / TOC blocks
i = 0
while i < len(raw_lines):
  line = raw_lines[i]
  i += 1
  if not line:
    continue

  # Skip explicit description/preface headings (e.g., 'About the New International Version', 'Contents')
  if is_description_heading(line):
    if not started:
      preface.append(line)
    continue

  # Skip probable table-of-contents lines that list multiple book-name tokens
  lower = line.lower()
  words = re.findall(r"[a-z0-9]+", lower)
  book_token_hits = sum(1 for w in words if w in BOOKS_TOKENS)
  if book_token_hits >= 2:
    if not started:
      preface.append(line)
    continue

  book_found = find_book_in_line(line)
  if book_found and len(line) <= len(book_found) + 12:
    current_book = book_found
    rest = line[len(book_found):].strip()
    m = re.match(r'^(\d{1,3})(?:[:.\-\s]+(\d{1,3}))?', rest)
    if m:
      current_chapter = m.group(1) or current_chapter
    # continue to next line; don't mark started yet
    continue

  # Detect chapter-only lines (e.g., '1') but confirm it's a chapter by lookahead
  m_ch = re.match(r'^(\d{1,3})$', line)
  if m_ch:
    # peek next non-empty line
    j = i
    while j < len(raw_lines) and not raw_lines[j]:
      j += 1
    next_line = raw_lines[j] if j < len(raw_lines) else ''
    # if next line looks like it starts with a verse number, accept as chapter
    if re.match(r'^\d{1,3}\b', next_line) or re.match(r'^\d{1,3}\s*\w', next_line):
      current_chapter = m_ch.group(1)
      continue
    else:
      # likely a page number or other marker; skip
      continue

  # Detect verse number at start (e.g., '1 In the beginning' or '1In the beginning')
  m_v = re.match(r'^(\d{1,3})\s*(.*)$', line)
  if m_v and m_v.group(2).strip():
    verse = m_v.group(1)
    desc = normalize_space(m_v.group(2).strip())
    # If the description itself looks like a heading or TOC fragment, skip
    desc_low = desc.lower()
    desc_tokens = re.findall(r"[a-z0-9]+", desc_low)
    desc_book_hits = sum(1 for t in desc_tokens if t in BOOKS_TOKENS)
    if is_description_heading(desc) or desc_book_hits >= 2:
      if not started:
        preface.append(line)
      continue

    # If we don't have a current book, try to look back a few lines for a book heading
    if not current_book and not current_chapter:
      k = max(0, i-6)
      for bline in raw_lines[k:i-1][::-1]:
        bf = find_book_in_line(bline)
        if bf:
          current_book = bf
          break

    # still ambiguous? skip numeric-looking lines without context
    if not current_book and not current_chapter and not find_book_in_line(line):
      if not started:
        preface.append(line)
      continue

    started = True
    preface = []
    rows.append([current_book, current_chapter, verse, desc])
    last_row = rows[-1]
    continue

  # Detect 'Chapter 10' patterns
  m_ch2 = re.match(r'^(chapter)\s+(\d{1,3})$', line, re.I)
  if m_ch2:
    current_chapter = m_ch2.group(2)
    continue

  # If a line contains a single known book name (e.g., 'Genesis'), set current_book
  if line.lower() in BOOKS_NORMAL:
    # match exact book name
    idx = BOOKS_NORMAL.index(line.lower())
    current_book = BOOKS[idx]
    continue

  # Otherwise treat as continuation of the last DESCRIPTION when possible
  if not started:
    # accumulate preface until first reliable verse/book
    preface.append(line)
    continue

  if last_row is not None:
    last_row[3] = normalize_space(last_row[3] + ' ' + line)
  else:
    rows.append(['', '', '', normalize_space(line)])
    last_row = rows[-1]

with open(csv_path, 'w', newline='', encoding='utf-8') as cf:
  writer = csv.writer(cf, quoting=csv.QUOTE_MINIMAL)
  writer.writerow(['BOOK', 'CHAPTER', 'VERSE', 'DESCRIPTION'])
  for r in rows:
    # ensure description is a single-line string and trimmed
    r[3] = normalize_space(r[3]) if r[3] else ''
    writer.writerow(r)

print(f"Wrote: {csv_path}")
PY

  # cleanup extracted text file
  rm -f "$out_txt"
}

for pdf in "$@"; do
  process_pdf "$pdf"
done

exit 0
