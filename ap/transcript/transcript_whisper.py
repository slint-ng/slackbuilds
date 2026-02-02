#!/usr/bin/env python3
import sys
import os
import subprocess
from faster_whisper import WhisperModel
import signal
# ---- CONFIG ----------------------------------------------------
ALLOWED_MODEL_SIZES = {"tiny", "base", "small", "medium", "large"}
MODEL_SIZE = os.environ.get("MODEL_SIZE", "small").lower()
if MODEL_SIZE not in ALLOWED_MODEL_SIZES:
    print(
        f"Error: invalid MODEL_SIZE='{MODEL_SIZE}'. "
        f"Allowed values are: {', '.join(sorted(ALLOWED_MODEL_SIZES))}.",
        file=sys.stderr
    )
    sys.exit(1)
AUDIO_RAW = "audio_raw.wav"
AUDIO_16K = "audio_16k.wav"
TRANSCRIPT = "transcript.txt"
# ---------------------------------------------------------------
def handle_sigint(signum, frame):
    print("\nInterrupted (Ctrl+C). Cleaning up...")
    sys.exit(130)  # standard exit code for SIGINT

signal.signal(signal.SIGINT, handle_sigint)

def cleanup():
    for f in (AUDIO_RAW, AUDIO_16K):
        if os.path.exists(f):
            try:
                os.remove(f)
                print(f"Removed {f}")
            except Exception as e:
                print(f"Could not remove {f}: {e}")
def run(cmd):
    subprocess.run(cmd, check=True)

def download_audio(url):
    print("[1/4] Downloading audio...")
    run([
        "yt-dlp",
        "-f", "bestaudio",
        "-x",
        "--audio-format", "wav",
        "-o", AUDIO_RAW,
        url
    ])

def convert_audio():
    print("[2/4] Converting audio to 16kHz mono...")
    run([
        "ffmpeg",
        "-y",
        "-i", AUDIO_RAW,
        "-ar", "16000",
        "-ac", "1",
        AUDIO_16K
    ])

def transcribe(lang=None):
    print("[3/4] Transcribing speech...")

    model = WhisperModel(
        MODEL_SIZE,
        device="cpu",
        compute_type="int8"   # critical for CPU speed
    )

    # --- Dynamic language check ---
    # faster-whisper does not expose available languages
    # Invalid language codes will raise an error during transcription

    segments, info = model.transcribe(
        AUDIO_16K,
        language=lang,
        vad_filter=True
    )

    with open(TRANSCRIPT, "w", encoding="utf-8") as f:
        for segment in segments:
            line = segment.text.strip()
            if line:
                f.write(line + "\n")

    print(f"[4/4] Transcript written to {TRANSCRIPT}")
    print(f"Detected language: {info.language}")


def usage():
    print("Usage:")
    print("  [MODEL_SIZE=<whisper_model>] transcript <url> [two letters language]")
    print("  whisper_model can be tiny, base, small, medium or large.")
    print("  The default is small.")
    print("  If the language is not set it will be auto-detected.")
    print("  Invalid language codes will raise an error during transcription.")
    print("  To know more, read /usr/doc/transcript/README")
    sys.exit(1)

def main():
    if len(sys.argv) < 2:
        usage()

    url = sys.argv[1]
    lang = sys.argv[2] if len(sys.argv) > 2 else None

    hf_home = os.path.join(
        os.environ.get("HOME", "."),
        ".local",
        "share",
        "huggingface"
    )
    os.makedirs(hf_home, exist_ok=True)
    os.environ["HF_HOME"] = hf_home

    try:
        download_audio(url)
        convert_audio()
        transcribe(lang)
    finally:
        cleanup()
        import shutil
        shutil.rmtree(hf_home, ignore_errors=True)
        # print(f"Removed temporary HF_HOME: {hf_home}")  # optional log

if __name__ == "__main__":
    main()
