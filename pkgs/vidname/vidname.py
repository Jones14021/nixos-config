#!/usr/bin/env python3
"""vidname — auto-title MP4 files via local transcription + GitHub Models API."""

import sys
import os
import json
import re
import subprocess
import tempfile
import urllib.request
import urllib.error

# ── Config ───────────────────────────────────────────────────────────────────
CONFIG_DIR   = os.path.join(os.path.expanduser("~"), ".config", "vidname")
CONFIG_FILE  = os.path.join(CONFIG_DIR, "config.json")
MODELS_URL   = "https://models.inference.ai.azure.com/models"
CHAT_URL     = "https://models.inference.ai.azure.com/chat/completions"

TITLE_PROMPT = """\
You are a file-naming assistant. Given a raw transcript of a short exercise/fitness video, \
produce a concise, descriptive English filename (without extension) that:
- Is 3–7 words long
- Uses underscores instead of spaces
- Is lowercase
- Captures the main exercise or topic (e.g. tibialis_raise_shin_splint_fix)
- Contains NO special characters except underscores

Always respond with ONLY the filename, nothing else. No markdown, no quotes."""

_WHISPER_MODEL = None


# ── Model selection ───────────────────────────────────────────────────────────
def pick_best_model() -> str:
    try:
        req = urllib.request.Request(MODELS_URL, headers={"Accept": "application/json"})
        with urllib.request.urlopen(req, timeout=10) as resp:
            models = json.loads(resp.read())
    except Exception as exc:
        print(f"[vidname] Warning: could not fetch model list ({exc}). Falling back to gpt-4o.")
        return "gpt-4o"

    chat_models = [m for m in models if m.get("task") == "chat-completion"]
    if not chat_models:
        print("[vidname] Warning: no chat-completion models returned. Falling back to gpt-4o.")
        return "gpt-4o"

    def rank(m):
        is_openai = "openai" in (m.get("publisher") or "").lower()
        is_gpt    = "gpt" in (m.get("name") or "").lower()
        return (is_openai and is_gpt, m.get("model_version", 0))

    best = sorted(chat_models, key=rank, reverse=True)[0]
    name = best["name"]
    print(f"[vidname] Selected model: {name} (v{best.get('model_version','?')}, {best.get('friendly_name', name)})")
    return name


# ── API key helpers ───────────────────────────────────────────────────────────
def load_api_key() -> str | None:
    if not os.path.exists(CONFIG_FILE):
        return None
    try:
        with open(CONFIG_FILE) as f:
            return json.load(f).get("github_token")
    except (json.JSONDecodeError, OSError):
        return None


def save_api_key(key: str) -> None:
    os.makedirs(CONFIG_DIR, mode=0o700, exist_ok=True)
    with open(CONFIG_FILE, "w") as f:
        json.dump({"github_token": key}, f)
    os.chmod(CONFIG_FILE, 0o600)
    print(f"[vidname] Token saved to {CONFIG_FILE}")


def prompt_api_key() -> str:
    print(
        "\n[vidname] A GitHub Personal Access Token (PAT) is required."
        "\n  Create one at: https://github.com/settings/tokens?type=beta"
        "\n  No special permissions needed — just an active GitHub Copilot subscription."
    )
    key = input("\nPaste your GitHub PAT (github_pat_...): ").strip()
    if not key:
        sys.exit("[vidname] No token provided — aborting.")
    save_api_key(key)
    return key


def get_api_key(force_prompt=False) -> str:
    key = load_api_key()
    if not key or key.startswith("ghu_") or force_prompt:
        if key and not force_prompt:
            print("[vidname] Stale IDE token (ghu_...) found — the Models API requires a PAT.")
        key = prompt_api_key()
    return key


# ── Whisper helpers ───────────────────────────────────────────────────────────
def get_whisper_model():
    global _WHISPER_MODEL
    if _WHISPER_MODEL is None:
        try:
            from faster_whisper import WhisperModel
        except ImportError:
            sys.exit("[vidname] faster-whisper not found. Ensure it is in your Nix environment.")
        print("[vidname] Loading Whisper model (base) …")
        _WHISPER_MODEL = WhisperModel("base", device="cpu", compute_type="int8")
    return _WHISPER_MODEL


def extract_audio(mp4_path: str) -> str:
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
        wav_path = tmp.name
    subprocess.run(
        ["ffmpeg", "-y", "-i", mp4_path, "-ar", "16000", "-ac", "1", "-f", "wav", wav_path],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    return wav_path


def transcribe_once(audio_path: str, forced_language: str | None = None) -> tuple[str, str | None, float | None]:
    model = get_whisper_model()
    kwargs = {"beam_size": 5}
    if forced_language:
        kwargs["language"] = forced_language

    print("[vidname] Transcribing …")
    if forced_language:
        print(f"[vidname] Forced transcription language: {forced_language}")

    segments, info = model.transcribe(audio_path, **kwargs)
    text = " ".join(seg.text for seg in segments).strip()
    language = getattr(info, "language", None)
    probability = getattr(info, "language_probability", None)

    if language:
        if probability is not None:
            print(f"[vidname] Chosen transcription language: {language} (confidence: {probability:.3f})")
        else:
            print(f"[vidname] Chosen transcription language: {language}")
    else:
        print("[vidname] Chosen transcription language: <unknown>")

    if not text:
        sys.exit("[vidname] Transcription returned empty text — check the video has speech.")
    return text, language, probability


def review_transcription(mp4_path: str) -> tuple[str, str | None]:
    audio_path = extract_audio(mp4_path)
    try:
        forced_language = None
        while True:
            transcript, language, probability = transcribe_once(audio_path, forced_language=forced_language)

            print(f"[vidname] Transcript snippet: {transcript[:180]} …")
            print("\nTranscription options:")
            print("  [y]es    : Accept this transcript")
            print("  [r]etry  : Re-run with auto language detection")
            print("  <code>   : Re-run with forced language code, e.g. de / en / fr / es")

            answer = input("\nTranscript action? ").strip()
            ans_lower = answer.lower()

            if ans_lower in ("y", "yes", ""):
                return transcript, language
            if ans_lower in ("r", "retry"):
                forced_language = None
                continue
            if re.fullmatch(r"[a-z]{2,3}(-[a-z]{2})?", ans_lower):
                forced_language = ans_lower
                continue

            print("[vidname] Invalid choice. Use y, r, or a language code like de/en.")
    finally:
        if os.path.exists(audio_path):
            os.unlink(audio_path)


# ── LLM Chat Completion ───────────────────────────────────────────────────────
def chat_completion(messages: list, model: str, force_prompt=False) -> str:
    api_key = get_api_key(force_prompt=force_prompt)

    payload = json.dumps({
        "model": model,
        "messages": messages,
        "max_tokens": 40,
        "temperature": 0.6,
    }).encode()

    req = urllib.request.Request(
        CHAT_URL,
        data=payload,
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        },
    )

    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = json.loads(resp.read())
    except urllib.error.HTTPError as e:
        body = e.read().decode(errors="replace")
        if e.code in (401, 403):
            print(f"\n[vidname] Auth failed ({e.code}).\n{body}")
            return chat_completion(messages, model, force_prompt=True)
        sys.exit(f"\n[vidname] API error {e.code}: {body}")
    except urllib.error.URLError as e:
        sys.exit(f"\n[vidname] Network error: {e.reason}")

    return data["choices"][0]["message"]["content"].strip()


# ── Interactive title loop ────────────────────────────────────────────────────
def process_file(mp4_path: str, transcript: str, model: str, transcript_language: str | None) -> None:
    directory = os.path.dirname(os.path.abspath(mp4_path))

    transcript_context = f"Transcript:\n{transcript[:4000]}"
    if transcript_language:
        transcript_context += f"\n\nDetected transcript language: {transcript_language}"

    messages = [
        {"role": "system", "content": TITLE_PROMPT},
        {"role": "user", "content": transcript_context},
    ]

    while True:
        print("[vidname] Generating title...")
        raw_title = chat_completion(messages, model)

        title = re.sub(r"[^a-z0-9_]+", "_", raw_title.lower())
        title = re.sub(r"_+", "_", title).strip("_")
        if not title:
            title = "exercise_video"

        new_name = f"{title}.mp4"
        new_path = os.path.join(directory, new_name)

        print(f"\n  Suggested title : \033[1;32m{title}\033[0m")
        print(f"  Current file    : {os.path.basename(mp4_path)}")
        print(f"  New filename    : {new_name}")

        if os.path.exists(new_path) and os.path.abspath(new_path) != os.path.abspath(mp4_path):
            print(f"  \033[33mWarning:\033[0m {new_name} already exists in that directory.")

        print("\nOptions:")
        print("  [y]es    : Rename file and move to next")
        print("  [n]o     : Skip file without renaming")
        print("  [r]etry  : Try again (generic different name)")
        print("  <text>   : Type instructions to refine (e.g. 'make it shorter')")

        answer = input("\nAction? ").strip()
        ans_lower = answer.lower()

        if ans_lower in ("y", "yes"):
            os.rename(mp4_path, new_path)
            print(f"[vidname] Renamed → {new_path}")
            break
        elif ans_lower in ("n", "no"):
            print("[vidname] Skipped — file unchanged.")
            break
        elif ans_lower in ("r", "retry"):
            messages.append({"role": "assistant", "content": raw_title})
            messages.append({"role": "user", "content": "Suggest a completely different filename. Remember: ONLY the filename."})
        elif answer:
            messages.append({"role": "assistant", "content": raw_title})
            messages.append({"role": "user", "content": f"{answer}. Remember to output ONLY the filename."})
        else:
            print("[vidname] Please choose an option.")


# ── Entry point ───────────────────────────────────────────────────────────────
def main() -> None:
    if len(sys.argv) < 2:
        prog = os.path.basename(sys.argv[0])
        print(f"Usage: {prog} <video.mp4> [<video2.mp4> …]")
        sys.exit(1)

    get_api_key()
    model = pick_best_model()

    for mp4 in sys.argv[1:]:
        if not os.path.isfile(mp4):
            print(f"[vidname] Skipping — not found: {mp4}")
            continue
        if not mp4.lower().endswith(".mp4"):
            print(f"[vidname] Skipping — not an .mp4: {mp4}")
            continue

        print(f"\n{'═'*60}")
        print(f"[vidname] Processing: {mp4}")

        transcript, transcript_language = review_transcription(mp4)
        process_file(mp4, transcript, model, transcript_language)


if __name__ == "__main__":
    main()
