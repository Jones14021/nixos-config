#!/usr/bin/env bash
set -euo pipefail

# This bash script walks you through creating a Google Photos Takeout,
# downloading 1+ archive parts, merging them into the single extracted “Takeout/…”
# input layout GPTH expects, then running gpth with album symlinks and a basic completeness sanity check.



TAKEOUT_URL="https://takeout.google.com/settings/takeout/custom/photos?utm_medium=organic-nav&utm_source=google-photos&hl=en&pli=1"

die() { echo "Error: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "Missing dependency: $1"; }

open_url() {
  local url="$1"
  if command -v xdg-open >/dev/null 2>&1; then xdg-open "$url" >/dev/null 2>&1 || true
  elif command -v gio >/dev/null 2>&1; then gio open "$url" >/dev/null 2>&1 || true
  elif command -v open >/dev/null 2>&1; then open "$url" >/dev/null 2>&1 || true
  fi
}

prompt() {
  local varname="$1" default="${2:-}" msg="$3"
  local val
  if [[ -n "$default" ]]; then
    read -r -p "$msg [$default]: " val || true
    val="${val:-$default}"
  else
    read -r -p "$msg: " val || true
  fi
  printf -v "$varname" '%s' "$val"
}

confirm() {
  local msg="$1"
  local ans
  read -r -p "$msg [y/N]: " ans || true
  [[ "${ans,,}" == "y" || "${ans,,}" == "yes" ]]
}

normalize_outdir() {
  local p="$1"
  mkdir -p "$p"
  (cd "$p" && pwd -P)
}

download_one() {
  local url="$1" dl_dir="$2" log_dir="$3"
  local ts logf
  ts="$(date +%Y%m%d-%H%M%S)"
  logf="$log_dir/curl-$ts.$$.log"

  # Accept accidental surrounding spaces.
  url="${url#"${url%%[![:space:]]*}"}"
  url="${url%"${url##*[![:space:]]}"}"

  # If the user pasted a "curl '...'" command, try to extract the first URL-like token.
  if [[ "$url" == curl\ * ]]; then
    # shellcheck disable=SC2001
    url="$(echo "$url" | sed -nE "s/.*(https?:\/\/[^'\"[:space:]]+).*/\1/p")"
    [[ -n "$url" ]] || die "Couldn't parse URL from pasted curl command."
  fi

  (
    cd "$dl_dir"

    # Use a stable per-URL filename so retries/reruns can resume into the same file.
    # We cannot use -C - (resume) together with -J (remote-header-name), so we choose our own name.
    # -f fails on HTTP errors, -L follows redirects, -C - resumes partial downloads.
    # Keep output quiet-ish; log details to file.
    local name
    name="takeout-$(echo -n "$url" | sha256sum | awk '{print $1}').tgz"
    echo "Downloading to: $dl_dir/$name ..."

    curl -fL -C - \
      --retry 6 --retry-all-errors --retry-delay 2 \
      --connect-timeout 20 --max-time 0 \
      -o "$name" \
      "$url" \
      >"$logf" 2>&1
    
    # Fast check: is it at least valid gzip?
    if ! gzip -t "$name" >/dev/null 2>&1; then
      die "Download is not a valid gzip stream (likely HTML/login page or truncated)."
    fi

    # Then: is the tar inside readable (still no extraction; just list to /dev/null)?
    if ! tar -tf "$name" >/dev/null 2>&1; then
      die "Download is not a valid tar archive (likely wrong content)."
    fi
    
    echo "Downloaded: $name (log: $logf)"
  )
}

extract_one() {
  local archive="$1" dest="$2"
  mkdir -p "$dest"

  case "$archive" in
    *.tar.gz|*.tgz)
      tar -xzf "$archive" -C "$dest"
      ;;
    *.zip)
      need unzip
      unzip -q "$archive" -d "$dest"
      ;;
    *)
      die "Unsupported archive type: $archive"
      ;;
  esac
}

find_takeout_dir() {
  local root="$1"
  # Typical: <root>/Takeout/...
  if [[ -d "$root/Takeout" ]]; then
    echo "$root/Takeout"
    return 0
  fi
  # Sometimes nested: <root>/<something>/Takeout/...
  local t
  t="$(find "$root" -maxdepth 3 -type d -name Takeout -print -quit 2>/dev/null || true)"
  [[ -n "$t" ]] || return 1
  echo "$t"
}

count_media_files() {
  local root="$1"
  # Exclude JSON sidecars; count regular files only.
  find "$root" -type f ! -name '*.json' -printf '.' 2>/dev/null | wc -c | tr -d ' '
}

du_bytes() {
  local path="$1"
  if du -sb "$path" >/dev/null 2>&1; then
    du -sb "$path" | awk '{print $1}'
  else
    # Fallback (KiB)
    du -sk "$path" | awk '{print $1 * 1024}'
  fi
}

main() {
  if [[ $# -ne 1 ]]; then
    cat >&2 <<EOF
Usage: $(basename "$0") OUTPUT_DIR

This will create:
  OUTPUT_DIR/_gpth_work/   (downloads, extraction, merged input, logs, manifest)
  OUTPUT_DIR/gpth_output/  (final organized photos)
EOF
    exit 2
  fi

  need bash
  need curl
  need tar
  need find
  need awk
  need sed

  local outdir work dl_dir ex_dir merged_dir log_dir final_dir
  outdir="$(normalize_outdir "$1")"
  work="$outdir/_gpth_work"
  dl_dir="$work/downloads"
  ex_dir="$work/extracted"
  merged_dir="$work/merged_input"
  log_dir="$work/logs"
  final_dir="$outdir/gpth_output"

  mkdir -p "$dl_dir" "$ex_dir" "$merged_dir" "$log_dir" "$final_dir"

  echo "Step 1/5: Start Google Takeout (manual)"
  echo "Open: $TAKEOUT_URL"
  echo "Set: export type .tgz, frequency once, service Google Photos only, and do NOT deselect any albums."
  open_url "$TAKEOUT_URL"
  echo
  confirm "Continue once Takeout is created and the email with download link(s) arrived?" || exit 0
  echo

  echo "Step 2/5: Enter Takeout download URL(s)"
  echo "Paste one URL per line (empty line to finish)."
  echo "Tip: Paste the direct download URLs you get from Takeout; if downloads fail, you may need to grab a direct URL from your browser session."
  local urls=()
  while true; do
    local line
    read -r -p "> " line || true
    [[ -n "${line// /}" ]] || break
    urls+=("$line")
  done
  [[ ${#urls[@]} -ge 1 ]] || die "No URLs provided."

  local jobs
  prompt jobs "3" "Parallel downloads"
  [[ "$jobs" =~ ^[0-9]+$ ]] || die "Parallel downloads must be an integer."
  (( jobs >= 1 )) || die "Parallel downloads must be >= 1."

  echo
  echo "Step 3/5: Downloading ${#urls[@]} part(s) ..."
  # Run parallel downloads via xargs.
    printf '%s\0' "${urls[@]}" | xargs -0 -n1 -P "$jobs" -I{} bash -c '
    set -euo pipefail
    url="$1"; dl_dir="$2"; log_dir="$3"
    '"$(declare -f die need download_one)"'
    download_one "$url" "$dl_dir" "$log_dir"
  ' _ "{}" "$dl_dir" "$log_dir"

  echo "Downloads complete."
  echo

  echo "Step 4/5: Extract + merge into single Takeout/ tree (GPTH input)"
  rm -rf "$merged_dir/Takeout"
  mkdir -p "$merged_dir/Takeout"

  mapfile -t archives < <(find "$dl_dir" -maxdepth 1 -type f \( -name '*.tgz' -o -name '*.tar.gz' -o -name '*.zip' \) | sort)
  [[ ${#archives[@]} -ge 1 ]] || die "No archives found in $dl_dir (expected .tgz/.tar.gz/.zip)."

  local i=0
  for a in "${archives[@]}"; do
    i=$((i+1))
    local part_dir="$ex_dir/part_$(printf '%03d' "$i")"
    rm -rf "$part_dir"
    mkdir -p "$part_dir"

    echo "  Extracting $(basename "$a") ..."
    extract_one "$a" "$part_dir"

    local tdir
    tdir="$(find_takeout_dir "$part_dir")" || die "Could not find Takeout/ inside extracted $(basename "$a")"

    # Merge contents of Takeout/ into merged_dir/Takeout/
    if command -v rsync >/dev/null 2>&1; then
      rsync -a "$tdir"/ "$merged_dir/Takeout"/
    else
      # cp -a fallback
      cp -a "$tdir"/. "$merged_dir/Takeout"/
    fi
  done

  [[ -d "$merged_dir/Takeout/Google Photos" ]] || {
    echo "Warning: '$merged_dir/Takeout/Google Photos' not found."
    echo "         GPTH may still work if Google changed naming, but this is a red flag."
  }

  local src_root="$merged_dir/Takeout/Google Photos"
  local src_count src_bytes
  if [[ -d "$src_root" ]]; then
    src_count="$(count_media_files "$src_root")"
    src_bytes="$(du_bytes "$src_root")"
  else
    src_count="0"
    src_bytes="0"
  fi

  {
    echo "timestamp=$(date -Is)"
    echo "source_root=$src_root"
    echo "source_media_files=$src_count"
    echo "source_bytes=$src_bytes"
    echo "archives_downloaded=${#archives[@]}"
  } > "$work/manifest.txt"

  echo "Merged input ready at: $merged_dir"
  echo

  echo "Step 5/5: Run GooglePhotosTakeoutHelper (gpth)"
  need gpth

  echo "Note: gpth moves files by default; your merged input may be emptied after it runs."
  confirm "Run gpth now?" || exit 0

  local divide
  divide="no"
  if confirm "Divide output into date folders (month/year)?" ; then
    divide="yes"
  fi

  rm -rf "$final_dir"
  mkdir -p "$final_dir"

  if [[ "$divide" == "yes" ]]; then
    gpth --input "$merged_dir" --output "$final_dir" --albums shortcut --divide-to-dates
  else
    gpth --input "$merged_dir" --output "$final_dir" --albums shortcut
  fi

  echo
  echo "Sanity checks"
  local out_count out_bytes
  out_count="$(find "$final_dir" -type f -printf '.' 2>/dev/null | wc -c | tr -d ' ')"
  out_bytes="$(du_bytes "$final_dir")"

  echo "  Source media files (excluding .json): $src_count"
  echo "  Output regular files:               $out_count"
  echo "  Source bytes (approx):              $src_bytes"
  echo "  Output bytes (approx):              $out_bytes"

  # Basic indicators
  local syms
  syms="$(find "$final_dir" -type l -printf '.' 2>/dev/null | wc -c | tr -d ' ')"
  echo "  Album symlinks found:               $syms"

  if [[ "$src_count" != "0" && "$out_count" != "0" && "$out_count" -lt "$src_count" ]]; then
    echo "Warning: Output file count is lower than source media count."
    echo "         Possible reasons: duplicates removed, unsupported files skipped, or a bad/partial Takeout download."
    echo "         Inspect logs in: $log_dir and manifest: $work/manifest.txt"
  else
    echo "Looks OK: output is non-empty and counts aren't obviously wrong."
  fi

  echo
  echo "Done."
  echo "  GPTH output:   $final_dir"
  echo "  Work dir:      $work"
}

main "$@"
