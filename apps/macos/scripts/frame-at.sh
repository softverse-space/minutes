#!/usr/bin/env bash
# Usage: frame-at.sh <hh:mm:ss>
# Extracts one frame from the recording of the session in the working folder and prints its path.
#
# The script takes no folder argument on purpose. A model calls it, and the transcript that the model
# reads is not trusted. The session is the working folder (or its parent, when the working folder is
# `frames`), so the model cannot point the script at another folder.
set -euo pipefail

[[ $# -eq 1 ]] || { echo "Usage: frame-at.sh <hh:mm:ss>" >&2; exit 2; }
timestamp="$1"
[[ "$timestamp" =~ ^[0-9]{2}:[0-5][0-9]:[0-5][0-9]$ ]] || { echo "The time must be hh:mm:ss, for example 00:07:42" >&2; exit 2; }

session_dir="$(pwd -P)"
[[ "$(basename "$session_dir")" == frames ]] && session_dir="$(dirname "$session_dir")"

# A session with parts (ADR-0029): `parts.tsv` maps the time on the combined timeline to one part.
# The app writes the file. Each line is checked, and the script builds the part path itself.
video_dir="$session_dir"
seek="$timestamp"
map="$session_dir/parts.tsv"
if [[ -e "$map" ]]; then
  [[ -f "$map" && ! -L "$map" && ! -L "$session_dir/parts" ]] || { echo "The part map must be a file, not a link" >&2; exit 1; }
  seconds=$((10#${timestamp:0:2} * 3600 + 10#${timestamp:3:2} * 60 + 10#${timestamp:6:2}))
  number=""
  while IFS=$'\t' read -r offset duration part rest || [[ -n "$offset" ]]; do
    if [[ -n "$rest" || ! "$offset" =~ ^[0-9]+(\.[0-9]+)?$ || ! "$duration" =~ ^[0-9]+(\.[0-9]+)?$ || ! "$part" =~ ^[0-9]{2}$ ]]; then
      echo "The part map is damaged" >&2; exit 1
    fi
    if awk -v t="$seconds" -v o="$offset" -v d="$duration" 'BEGIN { exit !(t >= o && t < o + d) }'; then
      number="$part"
      seek="$(awk -v t="$seconds" -v o="$offset" 'BEGIN { printf "%.3f", t - o }')"
      break
    fi
  done < "$map"
  [[ -n "$number" ]] || { echo "No recording at this time. The time is in a break between parts." >&2; exit 1; }
  video_dir="$session_dir/parts/$number"
  [[ -d "$video_dir" && ! -L "$video_dir" ]] || { echo "The part folder is missing" >&2; exit 1; }
fi

video=""
for extension in mov mp4 mkv; do
  if [[ -f "$video_dir/recording.$extension" ]]; then video="$video_dir/recording.$extension"; break; fi
done
[[ -n "$video" ]] || { echo "No recording in the working folder. Run the command in the session folder." >&2; exit 1; }

frames_dir="$session_dir/frames"
mkdir -p "$frames_dir"
[[ ! -L "$frames_dir" ]] || { echo "The frames folder must not be a link" >&2; exit 1; }

out="$frames_dir/at_${timestamp//:/-}.jpg"
[[ -f "$out" ]] || ffmpeg -nostdin -loglevel error -ss "$seek" -i "$video" -frames:v 1 -q:v 3 "$out"
echo "$out"
