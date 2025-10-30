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
import difflib

in_path = Path(sys.argv[1])
out_path = Path(sys.argv[2])
book = sys.argv[3] if len(sys.argv) > 3 else ''
text = in_path.read_text(encoding='utf-8')

# Normalize newlines
text = text.replace('\r\n', '\n')

# -- book name helpers -------------------------------------------------
# canonical book list used for detection and fuzzy-correction
books = [
    'Genesis','Exodus','Leviticus','Numbers','Deuteronomy','Joshua','Judges','Ruth',
    '1 Samuel','2 Samuel','1 Kings','2 Kings','1 Chronicles','2 Chronicles',
    'Ezra','Nehemiah','Esther','Job','Psalms','Proverbs','Ecclesiastes','Song of Solomon',
    'Isaiah','Jeremiah','Lamentations','Ezekiel','Daniel','Hosea','Joel','Amos','Obadiah',
    'Jonah','Micah','Nahum','Habakkuk','Zephaniah','Haggai','Zechariah','Malachi',
    'Matthew','Mark','Luke','John','Acts','Romans','1 Corinthians','2 Corinthians',
    'Galatians','Ephesians','Philippians','Colossians','1 Thessalonians','2 Thessalonians',
    '1 Timothy','2 Timothy','Titus','Philemon','Hebrews','James','1 Peter','2 Peter',
    '1 John','2 John','3 John','Jude','Revelation'
]

def _normalize_key(s):
    s2 = s.lower()
    s2 = re.sub(r'\b1st\b', '1', s2)
    s2 = re.sub(r'\b2nd\b', '2', s2)
    s2 = re.sub(r'\b3rd\b', '3', s2)
    s2 = re.sub(r'[^a-z0-9]', '', s2)
    return s2

# build a normalized -> canonical mapping (include 1st/2nd/3rd variants)
books_map = {}
for b in books:
    books_map[_normalize_key(b)] = b
    alt = b.replace('1 ', '1st ').replace('2 ', '2nd ').replace('3 ', '3rd ')
    books_map[_normalize_key(alt)] = b

def best_book(candidate):
    """Return canonical book name for candidate using exact or fuzzy match.
    Returns None if no reasonable match found.
    """
    if not candidate:
        return None
    norm = re.sub(r'[^A-Za-z0-9\s]', ' ', candidate).strip()
    # If candidate contains a numeric prefix like '1' or '1st', prefer numbered books
    pref = None
    m = re.search(r'\b([123])(st|nd|rd)?\b', norm, flags=re.I)
    if m:
        pref = m.group(1)
    # direct regex match: prefer prefixed books first when a prefix exists
    if pref:
        for b in books:
            if not b.startswith(pref + ' '):
                continue
            if re.search(r'\b' + re.escape(b) + r'\b', norm, flags=re.I):
                return b
            alt = b.replace('1 ', '1st ').replace('2 ', '2nd ').replace('3 ', '3rd ')
            if re.search(r'\b' + re.escape(alt) + r'\b', norm, flags=re.I):
                return b
    # fallback: check all books (non-preferring)
    for b in books:
        if re.search(r'\b' + re.escape(b) + r'\b', norm, flags=re.I):
            return b
        alt = b.replace('1 ', '1st ').replace('2 ', '2nd ').replace('3 ', '3rd ')
        if re.search(r'\b' + re.escape(alt) + r'\b', norm, flags=re.I):
            return b
    # fuzzy fallback
    cand_key = _normalize_key(norm)
    keys = list(books_map.keys())
    matches = difflib.get_close_matches(cand_key, keys, n=1, cutoff=0.6)
    if matches:
        found = books_map[matches[0]]
        print(f'INFO: fuzzy matched book candidate "{candidate}" -> "{found}"', file=sys.stderr)
        return found
    return None

def find_book_backward(full_text, start_idx, max_lines=6):
    """Scan backward from start_idx to find a candidate line that matches a book.
    Return canonical book name or None.
    """
    if start_idx is None or start_idx <= 0:
        return None
    snippet = full_text[:start_idx]
    # split into lines and walk backwards skipping empties
    lines = [ln.strip() for ln in snippet.splitlines() if ln.strip()]
    if not lines:
        return None
    # consider up to max_lines previous non-empty lines
    for ln in reversed(lines[-max_lines:]):
        fb = best_book(ln)
        if fb:
            print(f'INFO: backward-matched book candidate "{ln}" -> "{fb}"', file=sys.stderr)
            return fb
    return None

# ----------------------------------------------------------------------

def _strip_trailing_book(desc):
    """If the description ends with a single word that exactly matches a
    canonical single-word book name (case-insensitive) and there's no
    punctuation after it, strip that trailing word and return the cleaned
    description. Otherwise return desc unchanged.
    """
    if not desc:
        return desc
    # match a trailing alpha word with only optional whitespace after it
    m = re.search(r'([A-Za-z]+)\s*$', desc)
    if not m:
        return desc
    last = m.group(1)
    # ensure there's no punctuation immediately after (we matched to EOL so ok)
    # consider single-word canonical books
    for b in books:
        if ' ' in b:
            continue
        if last.lower() == b.lower():
            # strip the trailing word (and preceding space)
            return desc[:m.start(1)].rstrip()
    return desc


# We'll scan for numeric markers at line starts (multiline mode). We'll first attempt to
# interpret a match as a verse by comparing to the last seen verse. If it doesn't follow
# the expected verse sequence (last_verse + 1), we'll treat it as a chapter marker.
pattern = re.compile(r'(?m)^\s*(\d+)(\s*)')

rows = []
current_chapter = ''
matches = list(pattern.finditer(text))
# If book not provided, attempt to auto-detect by looking for a book-name line
# immediately before the first numeric marker. Use a small whitelist of common
# book names including numeric prefixes (1/2/3) to match variants like "2 Corinthians".
if not book and matches:
    m0 = matches[0]
    # take text before first marker, find last non-empty line/paragraph
    before = text[:m0.start()].rstrip()
    candidate = ''
    if before:
        # look for last paragraph (split by blank line) then last line
        parts = [p.strip() for p in re.split(r'\n\s*\n', before) if p.strip()]
        if parts:
            last_para = parts[-1]
            # take last non-empty line from that paragraph
            lines = [l.strip() for l in last_para.splitlines() if l.strip()]
            if lines:
                candidate = lines[-1]
            else:
                candidate = last_para.strip().splitlines()[-1].strip()

    # Normalize candidate and check against common book names. If no direct match
    # is found, use a fuzzy nearest-match lookup to pick the closest canonical
    # book name (e.g. "1st Chronicl" -> "1 Chronicles").
    if candidate:
        norm = re.sub(r'[^A-Za-z0-9\s]', ' ', candidate).strip()
        # common names (not exhaustive) — include numeric prefixes
        books = [
            'Genesis','Exodus','Leviticus','Numbers','Deuteronomy','Joshua','Judges','Ruth',
            '1 Samuel','2 Samuel','1 Kings','2 Kings','1 Chronicles','2 Chronicles',
            'Ezra','Nehemiah','Esther','Job','Psalms','Proverbs','Ecclesiastes','Song of Solomon',
            'Isaiah','Jeremiah','Lamentations','Ezekiel','Daniel','Hosea','Joel','Amos','Obadiah',
            'Jonah','Micah','Nahum','Habakkuk','Zephaniah','Haggai','Zechariah','Malachi',
            'Matthew','Mark','Luke','John','Acts','Romans','1 Corinthians','2 Corinthians',
            'Galatians','Ephesians','Philippians','Colossians','1 Thessalonians','2 Thessalonians',
            '1 Timothy','2 Timothy','Titus','Philemon','Hebrews','James','1 Peter','2 Peter',
            '1 John','2 John','3 John','Jude','Revelation'
        ]

        # Helper: normalize strings to compact alphanumeric key for fuzzy matching
        import difflib
        def _normalize_key(s):
            s2 = s.lower()
            # normalize ordinal prefixes like '1st' -> '1'
            s2 = re.sub(r'\b1st\b', '1', s2)
            s2 = re.sub(r'\b2nd\b', '2', s2)
            s2 = re.sub(r'\b3rd\b', '3', s2)
            s2 = re.sub(r'[^a-z0-9]', '', s2)
            return s2

        # Build mapping of normalized keys -> canonical book name (include alt forms)
        books_map = {}
        for b in books:
            books_map[_normalize_key(b)] = b
            alt = b.replace('1 ', '1st ').replace('2 ', '2nd ').replace('3 ', '3rd ')
            books_map[_normalize_key(alt)] = b

        # Try direct regex match first (case-insensitive, word boundaries)
        found = ''
        for b in books:
            if re.search(r'\b' + re.escape(b) + r'\b', norm, flags=re.I):
                found = b
                break
            alt = b.replace('1 ', '1st ').replace('2 ', '2nd ').replace('3 ', '3rd ')
            if re.search(r'\b' + re.escape(alt) + r'\b', norm, flags=re.I):
                found = b
                break

        # Fallback: fuzzy match the normalized candidate against the normalized book keys
        if not found:
            cand_key = _normalize_key(norm)
            keys = list(books_map.keys())
            matches = difflib.get_close_matches(cand_key, keys, n=1, cutoff=0.6)
            if matches:
                found = books_map[matches[0]]
                print(f'INFO: fuzzy matched book candidate "{candidate}" -> "{found}"', file=sys.stderr)

        if found:
            book = found
if matches:
    last_verse = None
    previous_chapter = ''
    for i, m in enumerate(matches):
        num = int(m.group(1))
        has_space = bool(m.group(2))
        # peek next non-quote character after the match (skip quotation marks)
        def _next_non_quote(s, idx):
            q = '"“”‘’\'\n\r\t'
            i = idx
            while i < len(s) and s[i] in q:
                i += 1
            return s[i] if i < len(s) else ''

        nxt_idx = m.end()
        next_char = _next_non_quote(text, nxt_idx)

        # compute description span
        start = m.end()
        end = matches[i+1].start() if i+1 < len(matches) else len(text)
        desc = text[start:end].strip().replace('\n', ' ')
        # a quote-stripped version of desc for condition checks
        desc_check = re.sub(r'[\"“”‘’]', '', desc)

        # We'll split the description if there are inline numeric markers (e.g. "2And...")
        # Inline markers may be followed by lowercase or uppercase; however, when
        # promoting a numeric token to a chapter we require the following character to
        # be uppercase (user rule). We therefore match any letter here and check case
        # at decision time.
        inline_pat = re.compile(r'(\d+)(\s*)(?=[A-Za-z])')

        # Glue chapter override: numbers immediately followed by letters with no space
        # (e.g. "17When Abram...") are guaranteed chapter markers per user rule.
        if not has_space and next_char.isupper():
            # immediate chapter marker
            current_chapter = str(num)
            # If book wasn't provided, or we've rolled over to a new book (chapter resets to 1),
            # try to detect the book name from text. If chapter==1 and previous_chapter indicates
            # we were in a prior book, overwrite the book name.
            if (not book) or (current_chapter == '1' and previous_chapter and previous_chapter != '1'):
                try:
                    para_start = text.rfind('\n\n', 0, m.start())
                    if para_start == -1:
                        para_start = text.rfind('\n', 0, m.start())
                        if para_start == -1:
                            para_start = max(0, m.start() - 300)
                    snippet = text[para_start:m.start()].strip()
                    lines = [ln.strip() for ln in snippet.splitlines() if ln.strip()]
                    if lines:
                        candidate = lines[-1]
                        # strip surrounding punctuation
                        candidate = re.sub(r'^[^A-Za-z0-9]*(.*?)[^A-Za-z0-9]*$', r'\1', candidate)
                        found_book = best_book(candidate)
                        if not found_book:
                            # try scanning backward a few lines for a clearer heading
                            found_book = find_book_backward(text, m.start(), max_lines=6)
                        if found_book:
                            book = found_book
                        else:
                            book = ' '.join(candidate.split())
                except Exception:
                    pass
            current_marker_chapter = current_chapter
            current_marker_verse = 1
            last_verse = 1
        else:
            # Verse-first detection using sequencing
            is_verse = False
            if last_verse is None:
                if num == 1:
                    is_verse = True
            else:
                if num == last_verse + 1:
                    is_verse = True

            if is_verse:
                current_marker_chapter = current_chapter
                current_marker_verse = num
                # warn if first verse is unexpected
                if last_verse is None and current_marker_verse != 1:
                    print(f'WARNING: first verse in chapter {current_chapter or "<unknown>"} is {current_marker_verse} (expected 1)', file=sys.stderr)
                last_verse = current_marker_verse
            else:
                # Verse detection failed (not sequential). Defer to chapter detection rules.
                is_chapter = False
                # Case A: digits immediately followed by an uppercase letter (no space)
                if not has_space and next_char.isupper():
                    is_chapter = True
                # Case B: digits followed by space then an uppercase word — treat as chapter
                # if the number is exactly one greater than the last seen chapter (user heuristic).
                elif has_space and next_char.isupper() and current_chapter:
                    try:
                        if num == int(current_chapter) + 1:
                            is_chapter = True
                    except Exception:
                        pass

                if is_chapter:
                    current_chapter = str(num)
                    # detect book name if not provided OR if chapter resets to 1 (new book)
                    if (not book) or (current_chapter == '1' and previous_chapter and previous_chapter != '1'):
                        try:
                            para_start = text.rfind('\n\n', 0, m.start())
                            if para_start == -1:
                                para_start = text.rfind('\n', 0, m.start())
                                if para_start == -1:
                                    para_start = max(0, m.start() - 300)
                            snippet = text[para_start:m.start()].strip()
                            lines = [ln.strip() for ln in snippet.splitlines() if ln.strip()]
                            if lines:
                                candidate = lines[-1]
                                candidate = re.sub(r'^[^A-Za-z0-9]*(.*?)[^A-Za-z0-9]*$', r'\1', candidate)
                                found_book = best_book(candidate)
                                if not found_book:
                                    # try scanning backward a few lines for a clearer heading
                                    found_book = find_book_backward(text, m.start(), max_lines=6)
                                if found_book:
                                    book = found_book
                                else:
                                    book = ' '.join(candidate.split())
                        except Exception:
                            pass
                    current_marker_chapter = current_chapter
                    current_marker_verse = 1
                    last_verse = 1
                else:
                    # Not a chapter according to rules — treat the numeric token as part of the
                    # description text (do not consume it as a marker). Prepend the numeric token
                    # back onto the description so it remains in-line with the text.
                    token = str(num) + (m.group(2) or '')
                    desc = token + desc
                    # keep current_marker_* unchanged and do not update last_verse

        # Walk through the desc and split at inline markers when they appear
        pos = 0
        for im in inline_pat.finditer(desc):
            im_num = int(im.group(1))
            im_start = im.start()
            im_end = im.end()
            segment = desc[pos:im_start].strip()

            # Inspect the next non-quote character in the description after the inline token
            next_char_inline = _next_non_quote(desc, im_end)
            has_space_inline = bool(im.group(2))

            # Glue-inline override: if digits are immediately followed by a letter
            # with no space and that letter is uppercase, this is a guaranteed chapter marker.
            if not has_space_inline and next_char_inline.isupper():
                # append the text before this inline chapter
                if segment:
                    # If this is the opening verse (1:1), ensure the book hasn't
                    # already been used earlier; if it has, try backward-searching
                    # for the correct book name.
                    if str(current_marker_chapter) == '1' and str(current_marker_verse) == '1':
                        prior_books = set([r[0] for r in rows if r and r[0]])
                        if book and book in prior_books:
                            alt = find_book_backward(text, m.start(), max_lines=8)
                            if alt:
                                book = alt
                    rows.append((book, current_marker_chapter, str(current_marker_verse), ' '.join(segment.split())))
                current_chapter = str(im_num)
                current_marker_chapter = current_chapter
                current_marker_verse = 1
                last_verse = 1
                pos = im_end
                continue

            # Decide if inline token is verse (sequence) or chapter (promote)
            inline_is_verse = False
            if last_verse is None:
                if im_num == 1:
                    inline_is_verse = True
            else:
                if im_num == last_verse + 1:
                    inline_is_verse = True

            if inline_is_verse:
                # append the text before this inline verse
                if segment:
                    if str(current_marker_chapter) == '1' and str(current_marker_verse) == '1':
                        prior_books = set([r[0] for r in rows if r and r[0]])
                        if book and book in prior_books:
                            alt = find_book_backward(text, m.start(), max_lines=8)
                            if alt:
                                book = alt
                    rows.append((book, current_marker_chapter, str(current_marker_verse), ' '.join(segment.split())))
                current_marker_verse = im_num
                last_verse = im_num
                pos = im_end
            else:
                # Verse sequencing failed for inline token; defer to chapter detection
                is_chapter_inline = False
                if not has_space_inline and next_char_inline.isupper():
                    is_chapter_inline = True
                elif has_space_inline and next_char_inline.isupper() and current_chapter:
                    try:
                        if im_num == int(current_chapter) + 1:
                            is_chapter_inline = True
                    except Exception:
                        pass

                if is_chapter_inline:
                    # append the text before this inline chapter
                    if segment:
                        if str(current_marker_chapter) == '1' and str(current_marker_verse) == '1':
                            prior_books = set([r[0] for r in rows if r and r[0]])
                            if book and book in prior_books:
                                alt = find_book_backward(text, m.start(), max_lines=8)
                                if alt:
                                    book = alt
                        rows.append((book, current_marker_chapter, str(current_marker_verse), ' '.join(segment.split())))
                    current_chapter = str(im_num)
                    # detect book name if not provided
                    if not book:
                        try:
                            # search back from the overall match start (m.start()) for a title
                            para_start = text.rfind('\n\n', 0, m.start())
                            if para_start == -1:
                                para_start = text.rfind('\n', 0, m.start())
                                if para_start == -1:
                                    para_start = max(0, m.start() - 300)
                            snippet = text[para_start:m.start()].strip()
                            lines = [ln.strip() for ln in snippet.splitlines() if ln.strip()]
                            if lines:
                                candidate = lines[-1]
                                candidate = re.sub(r'^[^A-Za-z0-9]*(.*?)[^A-Za-z0-9]*$', r'\1', candidate)
                                found_book = best_book(candidate)
                                if not found_book:
                                    # try scanning backward a few lines for a clearer heading
                                    # (use m.start() because we're inside an inline match branch)
                                    found_book = find_book_backward(text, m.start(), max_lines=6)
                                if found_book:
                                    book = found_book
                                else:
                                    book = ' '.join(candidate.split())
                        except Exception:
                            book = book
                    current_marker_chapter = current_chapter
                    current_marker_verse = 1
                    last_verse = 1
                    pos = im_end
                else:
                    # Not a chapter: treat as part of the description (do not split)
                    # leave pos unchanged so the numeric token remains in subsequent segment
                    continue

        # trailing segment after last inline marker
        tail = desc[pos:].strip()
        if tail:
            if str(current_marker_chapter) == '1' and str(current_marker_verse) == '1':
                prior_books = set([r[0] for r in rows if r and r[0]])
                if book and book in prior_books:
                    alt = find_book_backward(text, m.start(), max_lines=8)
                    if alt:
                        book = alt
            rows.append((book, current_marker_chapter, str(current_marker_verse), ' '.join(tail.split())))

        # update previous_chapter tracker for detecting book rollovers
        if current_chapter:
            previous_chapter = current_chapter

else:
    # No clear markers: split into paragraphs
    paras = [p.strip() for p in re.split(r'\n\s*\n', text) if p.strip()]
    for p in paras:
        rows.append((book, '', '', ' '.join(p.split())))

# Option: drop any rows before the first real chapter (e.g., Genesis 1:1)
# User requested to ignore everything before the first chapter. Find the first row
# where CHAPTER=='1' and VERSE=='1' and DESCRIPTION looks like the opening verse,
# and trim earlier rows.
start_idx = 0
for i, r in enumerate(rows):
    ch = r[1]
    v = r[2]
    desc = (r[3] or '').lower()
    if ch == '1' and v == '1' and 'in the beginning' in desc:
        start_idx = i
        break

rows = rows[start_idx:]

# Merge adjacent rows that share BOOK, CHAPTER, VERSE by concatenating DESCRIPTION
merged = []
for r in rows:
    if merged:
        prev = merged[-1]
        if prev[0] == r[0] and prev[1] == r[1] and prev[2] == r[2]:
            # combine descriptions
            combined_desc = (prev[3] + ' ' + r[3]).strip()
            merged[-1] = (prev[0], prev[1], prev[2], combined_desc)
            continue
    merged.append(r)

with out_path.open('w', encoding='utf-8', newline='') as f:
    w = csv.writer(f)
    w.writerow(['BOOK','CHAPTER','VERSE','DESCRIPTION'])
    for r in merged:
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
