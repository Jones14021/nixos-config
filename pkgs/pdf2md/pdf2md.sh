set -euo pipefail

MARKER_VERSION="2.0.0"

log() {
  printf '[%s] [INFO] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

warn() {
  printf '[%s] [WARN] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2
}

err() {
  printf '[%s] [ERROR] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2
}

usage() {
  cat <<'EOF'
Usage: pdf2md [--output_dir DIR] <file|directory|glob> [additional-inputs...]

Examples:
  pdf2md ./paper.pdf
  pdf2md "./invoices/*.pdf"
  pdf2md --output_dir ./converted ./paper.pdf
  pdf2md ./docs
  pdf2md ./docs ./more-docs/*.pdf

This command uses marker-pdf v2.0.0 under the hood.
EOF
}

parse_cli_args() {
  INPUT_TOKENS=()
  OUTPUT_DIR=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --output_dir|-o)
        shift
        if [[ $# -eq 0 ]]; then
          err "Missing value for --output_dir"
          usage
          exit 1
        fi
        OUTPUT_DIR="$1"
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      --*)
        err "Unsupported option: $1"
        usage
        exit 1
        ;;
      *)
        INPUT_TOKENS+=("$1")
        ;;
    esac
    shift
  done
}

ensure_output_dir() {
  if [[ -n "$OUTPUT_DIR" ]]; then
    mkdir -p "$OUTPUT_DIR"
    log "Using output directory: $OUTPUT_DIR"
    return 0
  fi

  if [[ -t 0 ]]; then
    while true; do
      printf 'No output directory provided. Enter output directory path: '
      read -r OUTPUT_DIR
      if [[ -n "$OUTPUT_DIR" ]]; then
        mkdir -p "$OUTPUT_DIR"
        log "Using output directory: $OUTPUT_DIR"
        return 0
      fi
      warn "Output directory cannot be empty."
    done
  fi

  OUTPUT_DIR="./pdf2md-output"
  mkdir -p "$OUTPUT_DIR"
  log "No interactive terminal detected. Using default output directory: $OUTPUT_DIR"
}

prompt_llm_settings() {
  local use_llm_answer llm_choice api_key

  USE_LLM=false
  LLM_SERVICE=""
  LLM_API_FLAG=""
  LLM_KEY_ENV=""
  LLM_EXTRA_FLAGS=()

  if [[ ! -t 0 ]]; then
    log "No interactive terminal detected. Continuing without LLM enhancement."
    return 0
  fi

  printf 'Use an LLM to enhance analysis quality? [y/N]: '
  read -r use_llm_answer

  if [[ ! "$use_llm_answer" =~ ^[Yy]$ ]]; then
    log "LLM enhancement disabled."
    return 0
  fi

  USE_LLM=true

  echo "Choose an LLM service supported by marker:"
  echo "  1) Gemini"
  echo "  2) Google Vertex"
  echo "  3) Ollama"
  echo "  4) Claude"
  echo "  5) OpenAI-compatible"
  echo "  6) Azure OpenAI"
  echo "  7) OpenRouter"

  while true; do
    printf 'Enter choice [1-7]: '
    read -r llm_choice
    case "$llm_choice" in
      1)
        LLM_SERVICE="marker.services.gemini.GoogleGeminiService"
        LLM_API_FLAG="--gemini_api_key"
        LLM_KEY_ENV="GOOGLE_API_KEY"
        break
        ;;
      2)
        LLM_SERVICE="marker.services.vertex.GoogleVertexService"
        LLM_API_FLAG=""
        LLM_KEY_ENV="GOOGLE_API_KEY"
        printf 'Vertex project id (optional, press Enter to skip): '
        read -r vertex_project_id
        if [[ -n "${vertex_project_id}" ]]; then
          LLM_EXTRA_FLAGS+=("--vertex_project_id" "${vertex_project_id}")
        fi
        break
        ;;
      3)
        LLM_SERVICE="marker.services.ollama.OllamaService"
        LLM_API_FLAG=""
        LLM_KEY_ENV=""
        printf 'Ollama model (optional, default gemma3): '
        read -r ollama_model
        if [[ -n "${ollama_model}" ]]; then
          LLM_EXTRA_FLAGS+=("--ollama_model" "${ollama_model}")
        fi
        printf 'Ollama base URL (optional, default http://localhost:11434): '
        read -r ollama_base_url
        if [[ -n "${ollama_base_url}" ]]; then
          LLM_EXTRA_FLAGS+=("--ollama_base_url" "${ollama_base_url}")
        fi
        break
        ;;
      4)
        LLM_SERVICE="marker.services.claude.ClaudeService"
        LLM_API_FLAG="--claude_api_key"
        LLM_KEY_ENV="ANTHROPIC_API_KEY"
        break
        ;;
      5)
        LLM_SERVICE="marker.services.openai.OpenAIService"
        LLM_API_FLAG="--openai_api_key"
        LLM_KEY_ENV="OPENAI_API_KEY"
        printf 'OpenAI base URL (optional, press Enter to skip): '
        read -r openai_base_url
        if [[ -n "${openai_base_url}" ]]; then
          LLM_EXTRA_FLAGS+=("--openai_base_url" "${openai_base_url}")
        fi
        printf 'OpenAI model (optional, press Enter to skip): '
        read -r openai_model
        if [[ -n "${openai_model}" ]]; then
          LLM_EXTRA_FLAGS+=("--openai_model" "${openai_model}")
        fi
        break
        ;;
      6)
        LLM_SERVICE="marker.services.azure_openai.AzureOpenAIService"
        LLM_API_FLAG="--azure_api_key"
        LLM_KEY_ENV="AZURE_API_KEY"
        printf 'Azure endpoint (required by marker for Azure service): '
        read -r azure_endpoint
        if [[ -n "${azure_endpoint}" ]]; then
          LLM_EXTRA_FLAGS+=("--azure_endpoint" "${azure_endpoint}")
        fi
        printf 'Azure deployment name (required by marker for Azure service): '
        read -r azure_deployment
        if [[ -n "${azure_deployment}" ]]; then
          LLM_EXTRA_FLAGS+=("--deployment_name" "${azure_deployment}")
        fi
        break
        ;;
      7)
        LLM_SERVICE="marker.services.openrouter.OpenRouterService"
        LLM_API_FLAG="--openrouter_api_key"
        LLM_KEY_ENV="OPENROUTER_API_KEY"
        printf 'OpenRouter model (optional, default google/gemini-3.5-flash): '
        read -r openrouter_model
        if [[ -n "${openrouter_model}" ]]; then
          LLM_EXTRA_FLAGS+=("--openrouter_model" "${openrouter_model}")
        fi
        break
        ;;
      *)
        warn "Invalid choice. Please select 1-7."
        ;;
    esac
  done

  printf 'Enter API key for selected service (input hidden, leave empty if not needed): '
  read -r -s api_key
  echo

  if [[ -n "${api_key}" ]]; then
    if [[ -n "${LLM_API_FLAG}" ]]; then
      LLM_EXTRA_FLAGS+=("${LLM_API_FLAG}" "${api_key}")
    fi
    if [[ -n "${LLM_KEY_ENV}" ]]; then
      LLM_ENV_VARS+=("${LLM_KEY_ENV}=${api_key}")
    fi
    log "API key captured for this run only (not stored)."
  else
    log "No API key provided. Continuing with service defaults."
  fi
}

add_resolved_path() {
  local p="$1"
  if [[ -d "$p" ]]; then
    RESOLVED_DIRS+=("$p")
  elif [[ -f "$p" ]]; then
    RESOLVED_FILES+=("$p")
  else
    warn "Skipping unsupported path type: $p"
  fi
}

expand_input_token() {
  local token="$1"

  if [[ -e "$token" ]]; then
    add_resolved_path "$token"
    return 0
  fi

  if [[ "$token" == *'*'* || "$token" == *'?'* || "$token" == *'['* ]]; then
    local matches=()
    mapfile -t matches < <(compgen -G "$token" || true)

    if [[ ${#matches[@]} -eq 0 ]]; then
      warn "No matches for wildcard input: $token"
      return 0
    fi

    local m
    for m in "${matches[@]}"; do
      add_resolved_path "$m"
    done
    return 0
  fi

  warn "Input does not exist and is not a wildcard: $token"
}

run_marker_folder() {
  local folder="$1"
  shift

  log "Converting directory with marker: $folder"
  if env "${LLM_ENV_VARS[@]}" uv tool run --from "marker-pdf==${MARKER_VERSION}" marker "$folder" --output_format markdown "$@"; then
    log "Finished directory: $folder"
  else
    err "Directory conversion failed: $folder"
    FAILED_COUNT=$((FAILED_COUNT + 1))
  fi
}

run_marker_file() {
  local file="$1"
  shift

  log "Converting file with marker_single: $file"
  if env "${LLM_ENV_VARS[@]}" uv tool run --from "marker-pdf==${MARKER_VERSION}" marker_single "$file" --output_format markdown "$@"; then
    log "Finished file: $file"
  else
    err "File conversion failed: $file"
    FAILED_COUNT=$((FAILED_COUNT + 1))
  fi
}

main() {
  if [[ $# -lt 1 ]]; then
    usage
    exit 1
  fi

  RESOLVED_FILES=()
  RESOLVED_DIRS=()
  LLM_ENV_VARS=()
  FAILED_COUNT=0

  log "pdf2md starting (marker-pdf v${MARKER_VERSION})."

  parse_cli_args "$@"

  if [[ ${#INPUT_TOKENS[@]} -eq 0 ]]; then
    err "No input paths provided."
    usage
    exit 1
  fi

  ensure_output_dir

  prompt_llm_settings

  local token
  for token in "${INPUT_TOKENS[@]}"; do
    expand_input_token "$token"
  done

  if [[ ${#RESOLVED_FILES[@]} -eq 0 && ${#RESOLVED_DIRS[@]} -eq 0 ]]; then
    err "No valid input files or directories found."
    exit 1
  fi

  MARKER_COMMON_FLAGS=()
  MARKER_COMMON_FLAGS+=("--output_dir" "$OUTPUT_DIR")
  if [[ "$USE_LLM" == true ]]; then
    MARKER_COMMON_FLAGS+=("--use_llm" "--llm_service" "$LLM_SERVICE")
    MARKER_COMMON_FLAGS+=("${LLM_EXTRA_FLAGS[@]}")
    log "LLM enhancement enabled using service: $LLM_SERVICE"
  else
    log "Running without LLM enhancement."
  fi

  if [[ ${#RESOLVED_DIRS[@]} -gt 0 ]]; then
    log "Found ${#RESOLVED_DIRS[@]} directorie(s) to process."
    local d
    for d in "${RESOLVED_DIRS[@]}"; do
      run_marker_folder "$d" "${MARKER_COMMON_FLAGS[@]}"
    done
  fi

  if [[ ${#RESOLVED_FILES[@]} -gt 0 ]]; then
    log "Found ${#RESOLVED_FILES[@]} file(s) to process."
    local f
    for f in "${RESOLVED_FILES[@]}"; do
      run_marker_file "$f" "${MARKER_COMMON_FLAGS[@]}"
    done
  fi

  if [[ $FAILED_COUNT -gt 0 ]]; then
    err "Completed with $FAILED_COUNT failure(s)."
    exit 2
  fi

  log "All conversions finished successfully."
}

main "$@"
