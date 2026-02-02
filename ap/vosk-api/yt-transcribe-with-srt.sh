#!/bin/bash
set -e

# -------------------------------
# Usage: ./yt-transcribe.sh <YouTube-URL>
#
# Requires:
#   yt-dlp
#   ffmpeg
#   vosk-transcriber
#   Vosk model at: /usr/local/share/vosk-models/small-en-us
# -------------------------------

URL="$1"
MODEL="/usr/local/share/vosk-models/small-en-us"
AUDIO="audio.mp3"
WAV="audio.wav"
TRANSCRIPT="transcript.txt"
SRT="transcript.srt"

if [ -z "$URL" ]; then
    echo "Usage: $0 <YouTube-URL>"
    exit 1
fi

if [ ! -d "$MODEL" ]; then
    echo "Error: Vosk model not found at $MODEL"
    exit 1
fi

echo "========== 1. Downloading audio with yt-dlp =========="
yt-dlp -x --audio-format mp3 -o "$AUDIO" "$URL"

echo ""
echo "========== 2. Converting to WAV (16kHz mono) =========="
ffmpeg -y -i "$AUDIO" -ar 16000 -ac 1 -f wav "$WAV"

echo ""
echo "========== 3. Checking if vosk-transcriber supports SRT =========="

# Default: no SRT support
SRT_FLAG=""

if vosk-transcriber --help 2>&1 | grep -q -- "--srt-output"; then
    echo "SRT subtitle output supported — enabling .srt generation."
    SRT_FLAG="--srt-output $SRT"
else
    echo "SRT subtitle output NOT supported — skipping .srt generation."
fi

echo ""
echo "========== 4. Transcribing with Vosk =========="

vosk-transcriber \
    --model "$MODEL" \
    --input "$WAV" \
    --output "$TRANSCRIPT" \
    $SRT_FLAG

echo ""
echo "========== 5. Done =========="
echo "Transcript saved to: $TRANSCRIPT"

if [ -n "$SRT_FLAG" ]; then
    echo "Subtitles saved to: $SRT"
fi

echo ""
