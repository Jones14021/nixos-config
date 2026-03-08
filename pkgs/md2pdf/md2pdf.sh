#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e

# Print usage if no arguments are provided
if [ $# -eq 0 ]; then
    echo "Usage: $0 <input_file.md> [output_file.pdf]"
    echo "Example: $0 input.md"
    echo "Example: $0 input.md custom_output.pdf"
    exit 1
fi

INPUT_FILE="$1"

# Check if the input file exists
if [ ! -f "$INPUT_FILE" ]; then
    echo "Error: Input file '$INPUT_FILE' not found!" >&2
    exit 1
fi

# Determine the output file name
if [ -n "$2" ]; then
    # If a second argument is provided, use it
    OUTPUT_FILE="$2"
else
    # If no second argument, replace the input file's extension with .pdf
    # The %.* removes the extension (e.g., .md), then we append .pdf
    OUTPUT_FILE="${INPUT_FILE%.*}.pdf"
fi

# 1. Pre-process the Markdown file
# We capture the resulting file path from stdout. Prompts and warnings go to stderr.
PROCESSED_FILE=$(./fix_lists.py "$INPUT_FILE")

# 2. Generate the PDF using Pandoc and Typst
echo "🚀 Starting Pandoc/Typst conversion on '$PROCESSED_FILE'..."

pandoc "$PROCESSED_FILE" -o "$OUTPUT_FILE" \
  --pdf-engine=typst \
  -f markdown+tex_math_single_backslash+tex_math_dollars+task_lists \
  -V papersize=a4 \
  -V mainfont="Libertinus Serif" \
  -V margin.x=2.5cm \
  -V margin.y=2.5cm \
  -V header-includes="#show link: set text(fill: rgb(\"#1E90FF\"))" \
  -V header-includes="#show raw.where(block: true): block.with(fill: luma(240), inset: 10pt, radius: 4pt)" \
  -V header-includes="#show quote.where(block: true): it => block(stroke: (left: 4pt + luma(200)), inset: (left: 1em, rest: 0.5em), fill: luma(250), width: 100%, it.body)" \
  -V header-includes="#show figure.where(kind: table): set block(radius: 6pt, stroke: 0.5pt + luma(200), clip: true)" \
  -V header-includes="#show table: set table(stroke: (x,y) => (bottom: 0.5pt + luma(220)), fill: (x, y) => if y == 0 { luma(235) } else if calc.odd(y) { white } else { luma(248) })" \
  -V header-includes="#let checkbox(checked) = box(width: 0.9em, height: 0.9em, stroke: 1pt + luma(120), radius: 2pt, inset: 1pt, baseline: 15%, if checked { align(center + horizon, text(size: 0.8em, weight: \"bold\")[✓]) })" \
  -V header-includes="#show \"☐\": checkbox(false)" \
  -V header-includes="#show \"☒\": checkbox(true)"

echo "✨ PDF successfully created: $OUTPUT_FILE"
