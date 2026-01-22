#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "Usage: textconnect <input.svg> [output.svg]"
  exit 1
fi

INPUT="$1"
OUTPUT="${2:-laser_ready.svg}"

if [ ! -f "$INPUT" ]; then
  echo "Error: Input file does not exist"
  exit 1
fi

echo "Processing SVG for laser cutting..."
echo "Input : $INPUT"
echo "Output: $OUTPUT"
echo

inkscape "$INPUT" \
  --batch-process \
  --actions="
    select-all:all;
    object-to-path;
    select-all:all;
    path-union;
    select-all:all;
    path-outset;
    export-filename:$OUTPUT
  "

echo "Done."
echo
echo "Resulting file: $OUTPUT"
echo "Open once in Inkscape to visually confirm fine details."
