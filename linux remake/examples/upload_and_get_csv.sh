#!/usr/bin/env bash
if [ "$#" -ne 2 ]; then
  echo "Usage: $0 /path/to/file.pdf /path/to/out.csv"
  exit 1
fi
PDF="$1"
OUT="$2"

if ! command -v curl >/dev/null 2>&1; then
  echo "curl required" >&2
  exit 1
fi

curl -v -F "file=@${PDF}" http://localhost:8080/convert -o "${OUT}"
echo "Saved CSV to ${OUT}"
