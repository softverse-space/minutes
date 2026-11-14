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

video=""
for extension in mov mp4 mkv; do
  if [[ -f "$session_dir/recording.$extension" ]]; then video="$session_dir/recording.$extension"; break; fi
done
[[ -n "$video" ]] || { echo "No recording in the working folder. Run the command in the session folder." >&2; exit 1; }

frames_dir="$session_dir/frames"
mkdir -p "$frames_dir"
[[ ! -L "$frames_dir" ]] || { echo "The frames folder must not be a link" >&2; exit 1; }

out="$frames_dir/at_${timestamp//:/-}.jpg"
[[ -f "$out" ]] || ffmpeg -nostdin -loglevel error -ss "$timestamp" -i "$video" -frames:v 1 -q:v 3 "$out"
echo "$out"
