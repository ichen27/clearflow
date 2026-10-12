#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v ffmpeg >/dev/null || { echo 'Install FFmpeg and add it to PATH.' >&2; exit 1; }
command -v ffprobe >/dev/null || { echo 'Install FFprobe with FFmpeg.' >&2; exit 1; }
scripts/build-app.sh
mkdir -p dist/x-reveal
for shape in landscape portrait; do
  frames="work/reveal/$shape"
  mkdir -p "$frames"
  dist/ClearFlow.app/Contents/MacOS/ClearFlow --render-reveal "$frames" "$shape"
  ffmpeg -hide_banner -loglevel warning -y -framerate 24 -start_number 0 -i "$frames/frame-%04d.png" \
    -f lavfi -i anullsrc=channel_layout=stereo:sample_rate=48000 \
    -map 0:v:0 -map 1:a:0 -t 23 -c:v libx264 -preset medium -crf 18 -pix_fmt yuv420p \
    -profile:v high -level 4.0 -c:a aac -b:a 128k -movflags +faststart -map_metadata -1 \
    -metadata title="ClearFlow — sample UI reveal" \
    -metadata comment="Synthetic UI walkthrough. Not live inference or a timing benchmark." \
    "dist/x-reveal/clearflow-demo-$shape.mp4"
  ffprobe -v error -show_entries stream=codec_name,width,height,r_frame_rate -show_entries format=duration,size \
    -of json "dist/x-reveal/clearflow-demo-$shape.mp4"
done
cp docs/media/x-reveal/clearflow-reveal.png dist/x-reveal/
echo 'Reveal assets are in dist/x-reveal. Both videos use a silent AAC track and on-screen captions.'
