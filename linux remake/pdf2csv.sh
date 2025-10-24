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

  # Attempt two-pass extraction for two-column layouts: use pdfinfo to get
  # page dimensions and run pdftotext twice (left / right halves). If pdfinfo
  # isn't available or the region extraction fails, fall back to a single
  # full-page extraction.
  out_txt_left="${out_txt%.txt}_left.txt"
  out_txt_right="${out_txt%.txt}_right.txt"
  out_txts=()

  if command -v pdfinfo >/dev/null 2>&1; then
    # pdfinfo prints a line like: "Page size: 612 x 792 pts"
    page_size_line=$(pdfinfo "$pdf" 2>/dev/null | awk -F': ' '/Page size/{print $2; exit}') || true
    if [[ -n "$page_size_line" ]]; then
      pw=$(echo "$page_size_line" | awk '{print int($1)}') || pw=0
      ph=$(echo "$page_size_line" | awk '{print int($3)}') || ph=0
      if [[ $pw -gt 0 && $ph -gt 0 ]]; then
        half=$((pw/2))
        # extract left and right halves; if these succeed we'll parse both
        pdftotext -layout -x 0 -y 0 -W "$half" -H "$ph" "$pdf" "$out_txt_left" 2>/dev/null || true
        pdftotext -layout -x "$half" -y 0 -W "$half" -H "$ph" "$pdf" "$out_txt_right" 2>/dev/null || true
        if [[ -s "$out_txt_left" && -s "$out_txt_right" ]]; then
          out_txts=("$out_txt_left" "$out_txt_right")
        else
          pdftotext -layout "$pdf" "$out_txt" || true
          out_txts=("$out_txt")
        fi
      else
        pdftotext -layout "$pdf" "$out_txt" || true
        out_txts=("$out_txt")
      fi
    else
      pdftotext -layout "$pdf" "$out_txt" || true
      out_txts=("$out_txt")
    fi
  else
    pdftotext -layout "$pdf" "$out_txt" || true
    out_txts=("$out_txt")
  fi

  # Build a python-friendly list of text file paths (raw triple-quoted strings)
  # Use printf so the variable contains actual newlines (valid Python list items)
  TXT_LIST=$(printf 'r"""%s""",\n' "${out_txts[@]}")

  # Use embedded python to parse the text(s) into CSV
  # NOTE: heredoc is unquoted so shell variables are expanded
  python3 - <<PY
import sys, csv, re
txt_paths = [
$TXT_LIST
]
txt_paths = [p for p in txt_paths if p]
txt_path = txt_paths[0] if txt_paths else r"""$out_txt"""
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

def find_book_anywhere(window_lines):
  """Search a list of lines (window_lines) for any known book name.

  Returns the canonical BOOK string if found, otherwise None.
  """
  # Prefer short lines that look like headings (few words), all-caps lines,
  # or lines starting with a numeric prefix + book token. This avoids matching
  # book-name tokens that appear inside normal verse/prose text.
  for l in window_lines:
    if not l:
      continue
    s = l.strip()
    if not s:
      continue
    low = s.lower()
    words = re.findall(r"[a-z0-9]+", low)
    # Heading-like: short (<=6 words) and short length
    is_short_heading = len(words) <= 6 and len(s) <= 60
    # All-caps centered headings
    is_all_caps = s.upper() == s and any(c.isalpha() for c in s)

    # 1) direct full-name match but prefer when line looks like a heading
    for b, bn in zip(BOOKS, BOOKS_NORMAL):
      if re.match(rf'^\s*{re.escape(bn)}\b', low):
        # strong match when at start of line
        if is_short_heading or is_all_caps or re.match(r'^(?:\d+|[ivx]+)\b', low):
          return b

    # 2) numeric-prefix + book token (e.g., '1 Samuel' split across columns)
    m = re.match(r'^(?:(?P<prefix>\d+|[ivx]+|first|second|third)\s+)?(?P<rest>.+)$', low)
    if m:
      rest = m.group('rest')
      for b, bn in zip(BOOKS, BOOKS_NORMAL):
        if rest.startswith(bn.split()[-1]):
          if is_short_heading or is_all_caps or m.group('prefix'):
            return b

    # 3) fallback: check for last-word tokens but only when the line is heading-like
    if is_short_heading or is_all_caps:
      for t in words:
        if t in BOOKS_TOKENS:
          for b, bn in zip(BOOKS, BOOKS_NORMAL):
            if bn.split()[-1] == t:
              return b

  return None

rows = []
last_row = None
current_book = ''
current_chapter = ''
started = False   # don't emit rows until we see a reliable verse with book context
preface = []      # collect initial lines (TOC, title pages) -- will be discarded to avoid polluting CSV

raw_lines = []
# If we have two column-extracted text files, merge them per page and per
# line so that book names split across the left/right columns are stitched
# together (e.g. "1" on left and "Samuel" on right -> "1 Samuel").
if len(txt_paths) >= 2:
  def read_pages(path):
    try:
      with open(path, 'r', encoding='utf-8', errors='replace') as f:
        content = f.read()
    except Exception:
      return []
    # pdftotext uses form feed (\f) to separate pages
    pages = content.split('\f')
    # convert each page into list of normalized lines
    return [[normalize_space(l) for l in p.splitlines()] for p in pages]

  left_pages = read_pages(txt_paths[0])
  right_pages = read_pages(txt_paths[1])
  max_pages = max(len(left_pages), len(right_pages))
  for pi in range(max_pages):
    left_lines = left_pages[pi] if pi < len(left_pages) else []
    right_lines = right_pages[pi] if pi < len(right_pages) else []
    # Append left column lines first (in reading order), then right column lines.
    # Do NOT merge left+right lines here; keep them separate so both are written
    # to the resulting CSV. The parser will consult nearby lines (including
    # the other column) when trying to detect book headings.
    for l in left_lines:
      if l:
        raw_lines.append(l)
    for r in right_lines:
      if r:
        raw_lines.append(r)
else:
  # fallback: read each file line-by-line (single-column extraction)
  for tp in txt_paths:
    try:
      with open(tp, 'r', encoding='utf-8', errors='replace') as f:
        for line in f:
          raw_lines.append(normalize_space(line))
    except Exception:
      continue

# Pre-process raw_lines: split any lines that contain multiple verse markers
# (e.g., "1 In the beginning... 2 Now the earth...") into separate lines
# that start with the verse number. This prevents a single CSV DESCRIPTION
# from containing multiple verses collapsed into one long paragraph.
processed_lines = []
verse_split_re = re.compile(r'(?=(?:\b\d{1,3}\b))')
for rl in raw_lines:
  s = rl.strip()
  if not s:
    continue
  # If the line contains more than one standalone verse number, split it
  # into multiple lines starting at each verse number.
  numbers = re.findall(r'\b\d{1,3}\b', s)
  if len(numbers) >= 2:
    parts = [p.strip() for p in verse_split_re.split(s) if p.strip()]
    processed_lines.extend(parts)
  else:
    processed_lines.append(s)

# iterate with index so we can look ahead and skip page numbers / TOC blocks
i = 0
while i < len(processed_lines):
  line = processed_lines[i]
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
  # If we didn't find a book name on this line, try a heuristic: if a recent
  # previous line is a numeric prefix (e.g., '1' or 'I' or 'First') and this
  # line begins with a book token (e.g., 'Samuel'), attempt to combine them
  # conceptually for book detection without merging the source lines.
  if not book_found:
    # look back up to 3 previous non-empty lines for a numeric prefix
    for back in range(1,4):
      idx_back = i-1-back
      if idx_back < 0 or idx_back >= len(processed_lines):
        break
      prev_line = processed_lines[idx_back].strip()
      if not prev_line:
        continue
      mnum = re.match(r'^(?P<prefix>\d+|[ivx]+|\w+st|\w+nd|\w+rd|first|second|third)\.?$', prev_line, re.I)
      if not mnum:
        continue
      pk = mnum.group('prefix')
      # construct a candidate by prepending the prefix to the current line
      candidate = (pk + ' ' + line).strip()
      bf = find_book_in_line(candidate)
      if bf:
        book_found = bf
        # treat the previous numeric-only line as a chapter/heading indicator
        current_book = book_found
        # try to extract chapter number from the rest of the candidate
        rest = candidate[len(book_found):].strip()
        m = re.match(r'^(?:\s*)(\d{1,3})(?:[:.\-\s]+(\d{1,3}))?', rest)
        if m:
          current_chapter = m.group(1) or current_chapter
        break
    # as a fallback, scan a small window of previous lines for any known book name
    if not book_found:
      win_k = max(0, i-6)
      bf = find_book_anywhere(processed_lines[win_k:i])
      if bf:
        book_found = bf
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
    while j < len(processed_lines) and not processed_lines[j]:
      j += 1
    next_line = processed_lines[j] if j < len(processed_lines) else ''
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
      bf = find_book_anywhere(processed_lines[k:i])
      if bf:
        current_book = bf

    # still ambiguous? skip numeric-looking lines without context
    if not current_book and not current_chapter and not find_book_in_line(line):
      if not started:
        preface.append(line)
      continue
    # Create a new row per verse. Do not allow arbitrary following lines to
    # accumulate into DESCRIPTION beyond the verse text itself. Continuation
    # lines (when verses are split across physical lines) should have been
    # split by the pre-processing above; but for small wrapped continuations
    # we still allow appending the immediately following non-verse line if it
    # begins with lowercase (likely a continuation) — otherwise treat as new.
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
    # Only append as continuation when the line looks like a true wrap of
    # the previous verse (e.g., starts with a lowercase word or is short).
    if re.match(r'^[a-z\"\'\(]', line) or len(line.split()) < 6:
      last_row[3] = normalize_space(last_row[3] + ' ' + line)
    else:
      # Treat as standalone description-only line (no verse number): create
      # a separate row with empty verse but keep current book/chapter context.
      rows.append([current_book, current_chapter, '', normalize_space(line)])
      last_row = rows[-1]
  else:
    rows.append(['', '', '', normalize_space(line)])
    last_row = rows[-1]

with open(csv_path, 'w', newline='', encoding='utf-8') as cf:
  writer = csv.writer(cf, quoting=csv.QUOTE_MINIMAL)
  writer.writerow(['BOOK', 'CHAPTER', 'VERSE', 'DESCRIPTION'])
  # Post-process rows to assign chapter/verse counters when originals are
  # missing or when a deterministic sequential numbering is desired.
  # Behavior implemented here:
  # - chapter_counter increments when we detect an explicit chapter marker
  #   (either an original chapter value present, or a DESCRIPTION that begins
  #   with the word 'chapter' + number). When chapter_counter increments,
  #   verse_counter resets to 1.
  # - verse_counter increments by 1 for each output row and is used to set
  #   the VERSE field (overriding parsed values). This gives a stable, simple
  #   numbering across the exported CSV.
  chapter_counter = 1
  verse_counter = 1
  last_seen_original_chapter = None
  for r in rows:
    # normalize description
    r[3] = normalize_space(r[3]) if r[3] else ''

    # detect explicit chapter markers in the parsed fields or description
    explicit_ch = None
    if r[1]:
      try:
        explicit_ch = int(re.sub(r"[^0-9]", "", r[1]))
      except Exception:
        explicit_ch = None
    else:
      mch = re.match(r'^chapter\s+(\d{1,3})', r[3], re.I)
      if mch:
        explicit_ch = int(mch.group(1))

    # if we see a new explicit chapter (different from last seen), bump counters
    if explicit_ch is not None and explicit_ch != last_seen_original_chapter:
      chapter_counter = chapter_counter + 1 if last_seen_original_chapter is not None else chapter_counter
      last_seen_original_chapter = explicit_ch
      verse_counter = 1

    # assign the computed chapter and verse
    r[1] = str(chapter_counter)
    r[2] = str(verse_counter)
    verse_counter += 1

    # remove leading 'Chapter N' from description if present
    r[3] = re.sub(r'(?i)^chapter\s+\d{1,3}[:.\-\s]*', '', r[3]).strip()

    writer.writerow(r)

print(f"Wrote: {csv_path}")
PY
  # cleanup extracted text files
  for tf in "${out_txts[@]}"; do
    rm -f "$tf"
  done
}

for pdf in "$@"; do
  process_pdf "$pdf"
done

exit 0
