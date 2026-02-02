#!/bin/bash
set -e

# -------------------------------
# Usage: ./yt-transcribe.sh <YouTube-URL>
#
# Requires:
#   yt-dlp
#   ffmpeg
#   vosk-transcriber  (provided by your Slint package)
#   Vosk model at: /usr/local/share/vosk-models/small-en-us
# -------------------------------

URL="$1"
MODEL="/usr/local/share/vosk-models/small-en-us"
AUDIO="audio.mp3"
WAV="audio.wav"
TRANSCRIPT="transcript.txt"

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
echo "========== 3. Transcribing with Vosk =========="
vosk-transcriber \
    --model "$MODEL" \
    --input "$WAV" \
    --output "$TRANSCRIPT"

echo ""
echo "========== 4. Done =========="
echo "Transcript saved to: $TRANSCRIPT"
echo ""

exit
==============
🔧 Optional: Enable SRT subtitle output

If your vosk-transcriber supports --srt-output, add:

    --srt-output transcript.srt

Example:

vosk-transcriber \
    --model "$MODEL" \
    --input "$WAV" \
    --output "$TRANSCRIPT" \
    --srt-output transcript.srt

If you'd like, I can update the script to detect automatically whether SRT output is supported.
