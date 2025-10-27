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
        # also produce a full (unsplit) text extraction which we'll use
        # as an unsplit reference for better book detection
        pdftotext -layout "$pdf" "$out_txt" || true
        if [[ -s "$out_txt_left" && -s "$out_txt_right" ]]; then
          out_txts=("$out_txt_left" "$out_txt_right")
        else
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
  # also expose the unsplit full-text file to the parser (used for robust book detection)
  FULL_TXT=$(printf 'r"""%s"""' "$out_txt")

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
full_txt_path = r"""$out_txt"""

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
          # construct candidate like '1 Samuel' and only accept it when it
          # matches a canonical book name from BOOKS. This avoids returning
          # fabricated names such as '3 Joshua'.
          name_parts = b.split(' ', 1)
          candidate = f"{num} {name_parts[-1]}"
          if candidate.lower() in BOOKS_NORMAL:
            # return canonical form from BOOKS
            idx = BOOKS_NORMAL.index(candidate.lower())
            return BOOKS[idx]
          # if the book entry already contains a numeric prefix and matches, return it
          if len(name_parts) == 2 and name_parts[0].isdigit():
            return b
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

def find_book_nearest_from_full(proc_index, proc_len, full_book_positions, full_len):
  """Estimate a corresponding position in the unsplit full text and
  return the nearest book heading found there (or None).

  proc_index: index in processed_lines (0-based)
  proc_len: total processed_lines length
  full_book_positions: list of (idx, book) tuples from full_lines
  full_len: total number of lines in full_lines
  """
  if not full_book_positions:
    return None
  # scale processed index into full-text space
  try:
    scale = float(proc_index) / max(1, proc_len)
  except Exception:
    scale = 0.0
  est = int(scale * max(1, full_len))
  # find the closest book position <= est, else the earliest following one
  before = None
  after = None
  for idx, bk in full_book_positions:
    if idx <= est:
      before = (idx, bk)
    elif after is None and idx > est:
      after = (idx, bk)
  if before:
    return before[1]
  if after:
    return after[1]
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

# Truncate raw_lines early to limit processing for faster runs. This keeps the
# parser from scanning the whole document when you only need a quick sample.
# Adjust MAX_LINES as needed (set to 0 to disable truncation).
MAX_LINES = 1000
if MAX_LINES and len(raw_lines) > MAX_LINES:
  # preserve order but only keep the first MAX_LINES lines
  raw_lines = raw_lines[:MAX_LINES]

# Pre-process raw_lines: split lines that contain multiple verse-like markers
# while avoiding false splits on dates, footnotes or numeric ranges. The
# heuristic below treats a number as a verse marker when it appears at the
# start of the line or is preceded by whitespace/punctuation and is followed
# by whitespace and then a letter or an opening quote/paren (typical verse
# starts). This reduces incorrect splits compared with splitting on any
# digit sequence.
processed_lines = []
# regex to find candidate numeric tokens (1..3 digits)
split_candidate_re = re.compile(r'(\d{1,3})\b')
for rl in raw_lines:
  s = rl.strip()
  if not s:
    continue

  # quick check: if there are fewer than 2 numeric tokens, nothing to do
  numbers = re.findall(r'\b\d{1,3}\b', s)
  if len(numbers) < 2:
    processed_lines.append(s)
    continue

  parts = []
  last_idx = 0
  # iterate over candidate number matches and decide whether each is a
  # plausible verse marker; when it is, start a new segment there.
  for m in split_candidate_re.finditer(s):
    start = m.start()
    end = m.end()

    # character(s) before/after the number
    pre = s[start-1] if start-1 >= 0 else ''

    # Look ahead a short distance to allow for an optional punctuation
    # character (e.g., "10.") before the whitespace and verse text.
    look = s[end:end+6]

    # Heuristic checks:
    is_at_start = (start == 0)
    pre_ok = (pre == '' or pre.isspace() or pre in '([{\-–—:;,.' )
    pre_is_lower = (pre.isalpha() and pre.islower())

    # Post must (after optional punctuation) contain whitespace then an
    # uppercase letter (verse starts are typically capitalized). This
    # avoids splitting inside sentences where numbers may appear mid-line.
    post_ok = bool(re.match(r'^[\.\:\,\)\]\s]*\s*["“\'\(\[]?[A-Z]', look))

    # Accept as a verse marker only when at line start, or when preceded by
    # punctuation/space (not a lowercase letter) AND the post-check matches.
    if is_at_start or (pre_ok and not pre_is_lower and post_ok):
      if last_idx < start:
        segment = s[last_idx:start].strip()
        if segment:
          parts.append(segment)
      last_idx = start

  # append the remaining tail (or the whole string if no markers accepted)
  if last_idx < len(s):
    tail = s[last_idx:].strip()
    if tail:
      parts.append(tail)

  # If heuristic produced at least two parts, use them; otherwise fall back
  # to the original line to avoid accidental corruption.
  if len(parts) >= 2:
    processed_lines.extend(parts)
  else:
    processed_lines.append(s)

# Read the unsplit full-text extraction and index book heading positions
full_lines = []
try:
  with open(full_txt_path, 'r', encoding='utf-8', errors='replace') as f:
    content = f.read()
  pages = content.split('\f')
  for p in pages:
    for l in p.splitlines():
      ll = normalize_space(l)
      if ll:
        full_lines.append(ll)
except Exception:
  full_lines = []

full_book_positions = []
for idx, l in enumerate(full_lines):
  try:
    b = find_book_in_line(l)
  except Exception:
    b = None
  if b:
    full_book_positions.append((idx, b))

# Map each processed line to a best-guess full_text line index so we can
# consult the unsplit full-text per-processed-line when deciding the book.
mapped_full_indices = []
for p_idx in range(len(processed_lines)):
  try:
    mapped_full_indices.append(map_processed_index_to_full(p_idx, processed_lines, full_lines))
  except Exception:
    mapped_full_indices.append(0)

def find_book_from_full_by_mapped_idx(mapped_idx):
  if not full_book_positions:
    return None
  for idx_bk, bk in reversed(full_book_positions):
    if idx_bk <= mapped_idx:
      return bk
  return full_book_positions[0][1]

# Determine where verses start in processed_lines and map that position
# into the unsplit full_text using exact-matching or a simple token-overlap
# fallback. This improves the seed so book detection begins immediately
# before the first verse.
def map_processed_index_to_full(proc_idx, processed_lines, full_lines):
  # try exact match of the processed line in full_lines
  target = processed_lines[proc_idx] if 0 <= proc_idx < len(processed_lines) else ''
  if not target:
    return 0
  # exact first match
  for i, fl in enumerate(full_lines):
    if fl == target:
      return i
  # try substring match (processed line may be a trimmed segment of a full line)
  for i, fl in enumerate(full_lines):
    if target in fl or fl in target:
      return i
  # fallback: use token-overlap scoring in a sliding window around estimated position
  proc_len = max(1, len(processed_lines))
  scale = float(proc_idx) / proc_len
  est = int(scale * max(1, len(full_lines)))
  # consider a ±200 line window (bounded)
  win = 200
  best_i = None
  best_score = 0
  t_tokens = set(re.findall(r"[a-z0-9]+", target.lower()))
  if not t_tokens:
    return max(0, min(est, len(full_lines)-1))
  lo = max(0, est-win)
  hi = min(len(full_lines)-1, est+win)
  for i in range(lo, hi+1):
    fl = full_lines[i]
    f_tokens = set(re.findall(r"[a-z0-9]+", fl.lower()))
    if not f_tokens:
      continue
    score = len(t_tokens & f_tokens)
    if score > best_score:
      best_score = score
      best_i = i
  if best_i is not None:
    return best_i
  return max(0, min(est, len(full_lines)-1))

# find first verse-like processed index
first_verse_idx = None
for idx_p, l in enumerate(processed_lines):
  if re.match(r'^(\d{1,3})[:\.\-]\s*(\d{1,3})(?:\s+(.*))?$', l):
    first_verse_idx = idx_p
    break
  m_v_tmp = re.match(r'^(\d{1,3})\s*(.*)$', l)
  if m_v_tmp and m_v_tmp.group(2).strip():
    first_verse_idx = idx_p
    break
if first_verse_idx is None:
  first_verse_idx = 0

# Map to full_lines index
mapped_full_idx = 0
try:
  if full_lines:
    mapped_full_idx = map_processed_index_to_full(first_verse_idx, processed_lines, full_lines)
except Exception:
  mapped_full_idx = 0

# Prefer any explicit book heading that appears in the processed (split)
# text immediately before the first verse. This prevents distant front/back
# matter book headings (e.g., in headers/TOC) from being used when a clear
# local heading like 'Genesis' exists near the verse start.
local_book_candidate = None
try:
  search_lo = max(0, first_verse_idx - 120)
  search_hi = max(0, first_verse_idx)
  # scan backwards so we prefer the most-recent nearby heading
  for pi in range(search_hi-1, search_lo-1, -1):
    try:
      lb = find_book_in_line(processed_lines[pi])
    except Exception:
      lb = None
    if lb:
      local_book_candidate = lb
      break
  if not local_book_candidate:
    # try a small window-based search using find_book_anywhere
    win_lo = max(0, first_verse_idx - 20)
    win_hi = first_verse_idx
    bf = find_book_anywhere(processed_lines[win_lo:win_hi])
    if bf:
      local_book_candidate = bf
except Exception:
  local_book_candidate = None

# Now find the nearest preceding book heading in full_book_positions
# but only seed when the heading is reasonably close to the mapped index
# (avoid picking distant headings from front/back matter). If no nearby
# heading is found, skip seeding and allow local heuristics to determine
# the book.
seed_book = None
PRESEED_BACK_WINDOW = 200  # lines before mapped index considered "nearby"
PRESEED_FORWARD_WINDOW = 40 # lines after mapped index to consider if nothing before
if full_book_positions:
  # find the closest preceding heading index
  chosen = None
  for idx_bk, bk in reversed(full_book_positions):
    if idx_bk <= mapped_full_idx:
      chosen = (idx_bk, bk)
      break
  if chosen:
    if (mapped_full_idx - chosen[0]) <= PRESEED_BACK_WINDOW:
      seed_book = chosen[1]
  else:
    # no preceding heading; try a small forward window
    for idx_bk, bk in full_book_positions:
      if idx_bk > mapped_full_idx and (idx_bk - mapped_full_idx) <= PRESEED_FORWARD_WINDOW:
        seed_book = bk
        break

seed_applied = False
if seed_book:
  # Only accept the seed when the same book token appears in the nearby
  # processed_lines window; this avoids using distant headings from headers
  # or TOC that don't reflect the local column text.
  proc_window_back = 20
  proc_window_forward = 5
  found_in_proc = False
  start_p = max(0, first_verse_idx - proc_window_back)
  end_p = min(len(processed_lines)-1, first_verse_idx + proc_window_forward)
  for pi in range(start_p, end_p+1):
    try:
      b2 = find_book_in_line(processed_lines[pi])
    except Exception:
      b2 = None
    if b2 == seed_book:
      found_in_proc = True
      break
  if found_in_proc:
    current_book = seed_book
    seed_applied = True

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
  # conceptually for book detection without merging the source lines. As a
  # stronger fallback, consult the unsplit full-text extraction for nearby
  # detected book headings.
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
      if not bf:
        # fallback: consult the mapped full-text index for the last processed
        # line and choose the nearest preceding book heading there.
        try:
          proc_idx = i-1
          if proc_idx < len(mapped_full_indices):
            mapped_idx = mapped_full_indices[proc_idx]
          else:
            mapped_idx = 0
          bf = find_book_from_full_by_mapped_idx(mapped_idx)
        except Exception:
          bf = None
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

  # Detect 'chapter:verse' patterns first (e.g., '3:16 In the beginning')
  m_cv = re.match(r'^(\d{1,3})[:\.\-]\s*(\d{1,3})(?:\s+(.*))?$', line)
  if m_cv:
    chap = m_cv.group(1)
    verse = m_cv.group(2)
    desc = normalize_space(m_cv.group(3) or '')
    # set current chapter from explicit marker
    current_chapter = chap
    # If the description looks like a heading/TOC, skip it until started
    if is_description_heading(desc) or sum(1 for t in re.findall(r"[a-z0-9]+", desc.lower()) if t in BOOKS_TOKENS) >= 2:
      if not started:
        preface.append(line)
      continue

    # Prefer a locally-detected book heading (from nearby processed lines)
    # for initial verses — this overrides any seeded book if we haven't
    # begun emitting rows yet.
    k = max(0, i-6)
    bf = find_book_anywhere(processed_lines[k:i])
    if not bf:
      try:
        proc_idx = i-1
        if proc_idx < len(mapped_full_indices):
          mapped_idx = mapped_full_indices[proc_idx]
        else:
          mapped_idx = 0
        bf = find_book_from_full_by_mapped_idx(mapped_idx)
      except Exception:
        bf = None
    if bf and (not started or (seed_applied and not started)):
      current_book = bf
    if not current_book and not started:
      preface.append(line)
      continue
    started = True
    preface = []
    rows.append([current_book, current_chapter, verse, desc])
    last_row = rows[-1]
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
    # Also prefer a locally-detected book over a seeded book if we haven't
    # actually started emitting rows yet.
    if not current_book or (seed_applied and not started):
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

# If we detected a local book candidate near the first verse, ensure any
# earlier rows (that were mis-assigned from headers/TOC) inherit that book
# up to the first occurrence of the candidate in `rows`.
if 'local_book_candidate' in globals() and local_book_candidate:
  first_idx = None
  for idx_r, rr in enumerate(rows):
    try:
      if rr[0] == local_book_candidate:
        first_idx = idx_r
        break
    except Exception:
      continue
  if first_idx is not None and first_idx > 0:
    for j in range(0, first_idx):
      # only override when a different BOOK is present (avoid clobbering blanks)
      if rows[j][0] and rows[j][0] != local_book_candidate:
        rows[j][0] = local_book_candidate

with open(csv_path, 'w', newline='', encoding='utf-8') as cf:
    writer = csv.writer(cf, quoting=csv.QUOTE_MINIMAL)
    writer.writerow(['BOOK', 'CHAPTER', 'VERSE', 'DESCRIPTION'])
    # Post-process rows to preserve detected chapter numbers and fill
    # missing verse numbers sequentially within each chapter. Behavior:
    # - If a row has an explicit numeric chapter, use that and reset verse
    #   numbering for the chapter.
    # - If a row has an explicit numeric verse, use it and set the next
    #   verse counter accordingly.
    # - Otherwise assign incremental verses within the current chapter.
    last_chapter = None
    verse_counter = 1
    # fallback sequential chapter counter when explicit chapters aren't found
    chapter_counter = 1
    last_book_name = None
    # Track last assigned verse to detect resets which imply a chapter change
    last_assigned_verse = None
    prev_assigned_chapter = None
    prev_output = None
    # track used verse numbers per (BOOK, CHAPTER) to ensure duplicates
    # are given their own verse number (uniqueness within a chapter)
    used_verses = {}
    for r in rows:
      # normalize description
      r[3] = normalize_space(r[3]) if r[3] else ''

      # reset chapter counter when book changes
      if r[0] and r[0] != last_book_name:
        last_book_name = r[0]
        chapter_counter = 1
        last_chapter = None
        verse_counter = 1
        last_assigned_verse = None

      # detect explicit chapter in field or leading description
      explicit_ch = None
      if r[1]:
        mch = re.search(r"(\d{1,3})", r[1])
        if mch:
          explicit_ch = int(mch.group(1))
      # also accept 'Chapter N' or a bare leading 'N' at the start of DESCRIPTION
      if explicit_ch is None and r[3]:
        mch = re.match(r'^chapter\s+(\d{1,3})', r[3], re.I)
        if mch:
          explicit_ch = int(mch.group(1))
          # remove the 'Chapter N' prefix from description
          r[3] = re.sub(r'(?i)^chapter\s+\d{1,3}[:.\-\s]*', '', r[3]).strip()
        else:
          # bare number at start of description likely indicates chapter
          mch2 = re.match(r'^(\d{1,3})\b[:.\-\s]*(.*)$', r[3])
          if mch2:
            explicit_ch = int(mch2.group(1))
            r[3] = mch2.group(2).strip()

      if explicit_ch is not None:
        last_chapter = explicit_ch
        chapter_counter = explicit_ch
        verse_counter = 1
        last_assigned_verse = None

      # determine the chapter that will be assigned to this row
      if explicit_ch is not None:
        assigned_chapter = explicit_ch
      elif last_chapter is not None:
        assigned_chapter = last_chapter
      else:
        assigned_chapter = chapter_counter

      # if chapter changed compared to previous output row, reset verse numbering
      if prev_assigned_chapter is None or assigned_chapter != prev_assigned_chapter:
        verse_counter = 1
        last_assigned_verse = None
        prev_assigned_chapter = assigned_chapter

      # detect explicit verse if present
      explicit_verse = None
      if r[2]:
        mv = re.search(r"(\d{1,3})", r[2])
        if mv:
          explicit_verse = int(mv.group(1))

      # If verse numbers are present and appear to reset/decrease, treat as new chapter
      if explicit_verse is not None:
        if last_assigned_verse is not None and explicit_verse <= last_assigned_verse:
          # verse restarted: assume a new chapter (increment fallback if needed)
          chapter_counter = (last_chapter + 1) if last_chapter is not None else chapter_counter + 1
          last_chapter = chapter_counter
          # when we deduce a new chapter, ensure verse_counter and last_assigned_verse reset
          verse_counter = 1
          last_assigned_verse = None

      # assign chapter: prefer explicit, then last seen, else use running counter
      if explicit_ch is not None:
        r[1] = str(explicit_ch)
      elif last_chapter is not None:
        r[1] = str(last_chapter)
      else:
        r[1] = str(chapter_counter)

      # assign verse: if chapter just changed, always reset to 1; otherwise
      # prefer explicit verse if present, else increment sequentially
      if prev_assigned_chapter is not None and int(r[1]) != prev_assigned_chapter:
        # chapter change detected for this row — reset to 1
        r[2] = '1'
        last_assigned_verse = 1
        verse_counter = 2
      else:
        if explicit_verse is not None:
          r[2] = str(explicit_verse)
          last_assigned_verse = explicit_verse
          verse_counter = explicit_verse + 1
        else:
          if last_assigned_verse is None:
            r[2] = str(verse_counter)
            last_assigned_verse = int(r[2])
            verse_counter = last_assigned_verse + 1
          else:
            r[2] = str(last_assigned_verse + 1)
            last_assigned_verse = int(r[2])
            verse_counter = last_assigned_verse + 1

      # remove leading 'Chapter N' from description if present
      r[3] = re.sub(r'(?i)^chapter\s+\d{1,3}[:.\-\s]*', '', r[3]).strip()

      # Defensive check: if a verse value is suspiciously large (>100),
      # it's likely a mis-detection (ages, years, page numbers). Treat the
      # detected number as not a real verse: move it back into DESCRIPTION
      # and reset the verse to 1. Update counters so sequencing continues.
      try:
        vcheck = int(r[2]) if r[2] else None
      except Exception:
        vcheck = None

      if vcheck is not None and vcheck > 100:
        # prepend the spurious number into the description so it's retained
        r[3] = (str(vcheck) + ' ' + r[3]).strip() if r[3] else str(vcheck)
        # if chapter is empty or non-numeric, promote the detected number
        # to chapter; otherwise leave chapter as-is but reset verse to 1
        try:
          chapnum = int(r[1]) if r[1] else None
        except Exception:
          chapnum = None
        if chapnum is None:
          r[1] = str(vcheck)
        # reset verse to 1 and update counters
        r[2] = '1'
        last_assigned_verse = 1
        verse_counter = 2

      # Ensure verse uniqueness within the (BOOK, CHAPTER).
      bk = r[0] or ''
      ch = r[1] or ''
      key = (bk, ch)
      try:
        curv = int(r[2]) if r[2] else None
      except Exception:
        curv = None
      if key not in used_verses:
        used_verses[key] = set()

      # If current verse is missing, fill from counter
      if curv is None:
        curv = verse_counter
        r[2] = str(curv)
        last_assigned_verse = curv
        verse_counter = curv + 1

      # If the verse number is already used in this chapter, bump until unique
      while curv in used_verses[key]:
        curv += 1
        r[2] = str(curv)
        last_assigned_verse = curv
        verse_counter = curv + 1

      used_verses[key].add(curv)
      writer.writerow(r)
      prev_output = [r[0], r[1], r[2], r[3]]

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
