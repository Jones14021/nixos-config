#!/usr/bin/env bash
set -euo pipefail

show_help() {
cat << 'EOF'
png2svg — PNG → real SVG vectorization (ImageMagick v7 + Potrace)

USAGE
  png2svg [OPTIONS] <file.png | dir | *.png>

OPTIONS
  --preprocess <use-case>
      lasercutting   Clean silhouettes, CNC / laser
      logo           Flat colors, crisp edges
      art            Stylized illustrations
      real           Maximal detail from photos

      Default: logo

  --threshold <percent>
      Override binarization threshold.
      Always takes precedence over presets.

  --output <file|dir>
      Optional output path.
      - File: single input
      - Directory: batch mode

  --help
      Show this help.

BEHAVIOR
  - Single PNG → same-name .svg
  - Multiple PNGs → batch to current dir
  - Directory input → batch
  - SVGs contain real vector paths only

EOF
}

# Defaults
USECASE="logo"
THRESHOLD_OVERRIDE=""
OUTPUT=""
INPUTS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --preprocess)
      USECASE="$2"; shift 2 ;;
    --threshold)
      THRESHOLD_OVERRIDE="$2"; shift 2 ;;
    --output)
      OUTPUT="$2"; shift 2 ;;
    --help)
      show_help; exit 0 ;;
    *)
      INPUTS+=("$1"); shift ;;
  esac
done

if [[ "${#INPUTS[@]}" -eq 0 ]]; then
  echo "No input provided. See --help." >&2
  exit 1
fi

# Expand directories
EXPANDED=()
for i in "${INPUTS[@]}"; do
  if [[ -d "$i" ]]; then
    EXPANDED+=("$i"/*.png)
  else
    EXPANDED+=("$i")
  fi
done
INPUTS=("${EXPANDED[@]}")

# Use-case presets
case "$USECASE" in
  lasercutting)
    COLORS=2
    THRESHOLD=70
    IM_ARGS=(-colorspace Gray)
    POTRACE_ARGS=(--turdsize 10 --alphamax 1 --opttolerance 0.3)
    ;;
  logo)
    COLORS=6
    THRESHOLD=60
    IM_ARGS=(-colors "$COLORS")
    POTRACE_ARGS=(--turdsize 5 --alphamax 1.2)
    ;;
  art)
    COLORS=10
    THRESHOLD=50
    IM_ARGS=(-colorspace Gray -colors "$COLORS")
    POTRACE_ARGS=(--turdsize 3 --alphamax 1.4)
    ;;
  real)
    COLORS=12
    THRESHOLD=45
    IM_ARGS=(-colorspace Gray -edge 1)
    POTRACE_ARGS=(--turdsize 1 --alphamax 1.6)
    ;;
  *)
    echo "Unknown use-case: $USECASE" >&2
    exit 1
    ;;
esac

# Override threshold if user supplied it
if [[ -n "$THRESHOLD_OVERRIDE" ]]; then
  THRESHOLD="$THRESHOLD_OVERRIDE"
fi

process_one() {
  local input="$1"
  local output="$2"
  local tmp
  tmp="$(mktemp --suffix=.pbm)"
  trap 'rm -f "$tmp"' RETURN

  magick "$input" \
    "${IM_ARGS[@]}" \
    -threshold "${THRESHOLD}%" \
    -compress none \
    "$tmp"

  potrace -b svg "${POTRACE_ARGS[@]}" "$tmp" -o "$output"
}

# Output resolution
if [[ -n "$OUTPUT" ]]; then
  if [[ "${#INPUTS[@]}" -gt 1 || -d "$OUTPUT" ]]; then
    mkdir -p "$OUTPUT"
    for f in "${INPUTS[@]}"; do
      base="$(basename "$f" .png)"
      process_one "$f" "$OUTPUT/$base.svg"
    done
  else
    process_one "${INPUTS[0]}" "$OUTPUT"
  fi
else
  for f in "${INPUTS[@]}"; do
    base="$(basename "$f" .png)"
    process_one "$f" "./$base.svg"
  done
fi
exit 0
