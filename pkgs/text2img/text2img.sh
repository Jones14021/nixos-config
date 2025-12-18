#!/usr/bin/env bash
set -euo pipefail

show_help() {
cat << 'EOF'
text2img — render text to image (default SVG) for laser cutting

USAGE
  text2img [OPTIONS] "<text>" [--output <file|dir>]
  text2img [OPTIONS] <file1.txt> <file2.txt> ... [--output <dir>]

OPTIONS
  --font <fontname|path>   Font to use (default: "DejaVuSans")
  --size <px>              Font size (default: 100)
  --format <svg|png>       Output format (default: svg)
  --output <file|dir>      Optional output file or directory
  --list                   List all fonts in a single preview window
  --help                   Show this help

BATCH MODE
  - Multiple text arguments or files produce multiple images
  - Output directory can be specified with --output
  - If omitted, current directory is used

EXAMPLES
  text2img "Hello World"
  text2img --font "Comic Sans MS" "My Text" --output out.svg
  text2img file1.txt file2.txt --output out/
  text2img --list
EOF
}

# Defaults
FONT="DejaVuSans"
SIZE=100
FORMAT="svg"
LIST_FONTS=0
OUTPUT=""
INPUTS=()

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --font) FONT="$2"; shift 2 ;;
    --size) SIZE="$2"; shift 2 ;;
    --format) FORMAT="$2"; shift 2 ;;
    --output) OUTPUT="$2"; shift 2 ;;
    --list) LIST_FONTS=1; shift ;;
    --help) show_help; exit 0 ;;
    *) INPUTS+=("$1"); shift ;;
  esac
done

# Function to resolve font path
resolve_font() {
    local f="$1"
    if [[ -f "$f" ]]; then
        echo "$f"
    else
        local path
        path=$(fc-match -f "%{file}\n" "$f" 2>/dev/null || true)
        if [[ -z "$path" || ! -f "$path" ]]; then
            echo "Error: Font '$f' not found" >&2
            exit 1
        fi
        echo "$path"
    fi
}

FONT_PATH=$(resolve_font "$FONT")

# --list: all fonts
if [[ $LIST_FONTS -eq 1 ]]; then
    echo "Available fonts (fontconfig names):"
    fc-list : family | sed 's/:.*//' | sort -u
    exit 0
fi

# No input check
if [[ "${#INPUTS[@]}" -eq 0 ]]; then
    echo "No input text or files provided. See --help." >&2
    exit 1
fi

process_one() {
    local text="$1"
    local output="$2"

    mkdir -p "$(dirname "$output")"

    # Render text to image, auto-sizing canvas to text
    magick \
        -background white \
        -fill black \
        -font "$FONT_PATH" \
        -pointsize "$SIZE" \
        label:"$text" \
        "$output"

    echo "Saved: $output"
}

# Expand directories
EXPANDED=()
for i in "${INPUTS[@]}"; do
    if [[ -d "$i" ]]; then
        EXPANDED+=("$i"/*)
    else
        EXPANDED+=("$i")
    fi
done
INPUTS=("${EXPANDED[@]}")

# Determine outputs
if [[ -n "$OUTPUT" ]]; then
    if [[ "${#INPUTS[@]}" -gt 1 || -d "$OUTPUT" ]]; then
        # batch mode to directory
        mkdir -p "$OUTPUT"
        for t in "${INPUTS[@]}"; do
            base="$(basename "$t")"
            [[ "$base" == *.txt ]] && base="${base%.txt}"
            process_one "$t" "$OUTPUT/$base.$FORMAT"
        done
    else
        # single output file
        process_one "${INPUTS[0]}" "$OUTPUT"
    fi
else
    # No output specified, use current dir
    for t in "${INPUTS[@]}"; do
        base="$(basename "$t")"
        [[ "$base" == *.txt ]] && base="${base%.txt}"
        process_one "$t" "./$base.$FORMAT"
    done
fi
