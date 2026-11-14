#!/usr/bin/env bash
# Phase 0: process an existing recording (e.g. from OBS) end-to-end.
#
# Usage: process-session.sh <video> [template-id] [detail] [extra instructions]
#   template-id  standard | <custom id>   (default: standard)
#   detail       strucna | stredna | detailna   (default: from template)
#
# Environment:
#   OMS_SESSIONS_DIR     where sessions are created (default: ~/Meetings)
#   OMS_ASR              local | server (default: local; "internal" still works)
#   OMS_WHISPER_MODEL    ggml model for local ASR (default: ~/.local/share/oms/models/ggml-large-v3-turbo.bin)
#   OMS_LANGUAGE         spoken language: auto | sk | cs | en (default: auto)
#   OMS_ASR_URL          OpenAI-compatible /v1/audio/transcriptions endpoint (required when OMS_ASR=server)
#   OMS_ASR_MODEL        model on the server (required when OMS_ASR=server)
#   OMS_ASR_API_KEY      API key for the server (required when OMS_ASR=server)
#   OMS_OUTPUT_LANGUAGE  output language: sk | en | ... (default: template language, else sk)
#   OMS_MODEL            opencode model provider/model (default: opencode config)
# The OpenCode agent meeting-summary is created by the app (apps/macos/prompts/meeting-summary.md).
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
app_dir="$(dirname "$script_dir")"

video="${1:?usage: process-session.sh <video> [template-id] [detail] [extra instructions]}"
template_id="${2:-standard}"
detail="${3:-}"
extra="${4:-}"

sessions_dir="${OMS_SESSIONS_DIR:-$HOME/Meetings}"
asr="${OMS_ASR:-local}"; [[ "$asr" == internal ]] && asr=server  # old name
whisper_model="${OMS_WHISPER_MODEL:-$HOME/.local/share/oms/models/ggml-large-v3-turbo.bin}"
language="${OMS_LANGUAGE:-auto}"

# --- Template ---------------------------------------------------------------
user_templates="$HOME/Library/Application Support/OfflineMeetingSummary/templates"
template_file="$user_templates/$template_id.md"
[[ -f "$template_file" ]] || template_file="$app_dir/templates/$template_id.md"
[[ -f "$template_file" ]] || { echo "Template not found: $template_id" >&2; exit 1; }

front_matter_value() { awk -v key="$1" 'NR==1 && /^---$/ {fm=1; next} fm && /^---$/ {exit} fm && $1==key":" {sub(/^[^:]*:[ ]*/, ""); print}' "$template_file"; }
detail="${detail:-$(front_matter_value detail)}"; detail="${detail:-stredna}"
out_language="${OMS_OUTPUT_LANGUAGE:-$(front_matter_value language)}"; out_language="${out_language:-sk}"

detail_text="$(awk -v lvl="## $detail" '$0==lvl {on=1; next} /^## / {on=0} on' "$app_dir/templates/_detail-levels.md")"
[[ -n "$detail_text" ]] || { echo "Unknown detail level: $detail (strucna | stredna | detailna)" >&2; exit 1; }

# --- Tools -----------------------------------------------------------------
required=(ffmpeg opencode)
[[ "$asr" == local ]] && required+=(whisper-cli)
[[ "$asr" == server ]] && required+=(curl python3)
for tool in "${required[@]}"; do
  command -v "$tool" >/dev/null || { echo "Missing tool: $tool (see apps/macos/docs/install.md)" >&2; exit 1; }
done
if [[ "$asr" == local && ! -f "$whisper_model" ]]; then echo "Missing whisper model: $whisper_model" >&2; exit 1; fi
if [[ "$asr" == server && -z "${OMS_ASR_API_KEY:-}" ]]; then echo "OMS_ASR_API_KEY is not set" >&2; exit 1; fi

# --- 1. Session folder -------------------------------------------------------
stamp="$(date +%Y-%m-%d_%H-%M-%S)"
name="$(basename "${video%.*}")"
session="$sessions_dir/${stamp}_${name// /_}"
mkdir -p "$session"/{frames,outputs}
ext="${video##*.}"
ln -sf "$(cd "$(dirname "$video")" && pwd)/$(basename "$video")" "$session/recording.$ext"
echo "Session: $session"

# --- 2. Audio (all audio tracks mixed, 16 kHz mono PCM) ---------------------
echo "→ Extracting audio"
tracks="$(ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 "$session/recording.$ext" | wc -l | tr -d ' ')"
if (( tracks > 1 )); then
  ffmpeg -loglevel error -y -i "$session/recording.$ext" -filter_complex "amix=inputs=$tracks:normalize=0" -ac 1 -ar 16000 -c:a pcm_s16le "$session/${stamp}_audio.wav"
else
  ffmpeg -loglevel error -y -i "$session/recording.$ext" -map 0:a:0 -ac 1 -ar 16000 -c:a pcm_s16le "$session/${stamp}_audio.wav"
fi

# --- 3. Transcription --------------------------------------------------------
base="$session/${stamp}_transcript"
if [[ "$asr" == local ]]; then
  echo "→ Transcribing locally (whisper.cpp, language: $language)"
  whisper-cli -m "$whisper_model" -l "$language" -oj -osrt -ovtt -otxt -of "$base" -f "$session/${stamp}_audio.wav" >"$session/transcription.log" 2>&1
else
  : "${OMS_ASR_URL:?Set OMS_ASR_URL to your transcription server}" "${OMS_ASR_MODEL:?Set OMS_ASR_MODEL}"
  echo "→ Transcribing on the server ($OMS_ASR_MODEL)"
  lang_args=()
  [[ "$language" != auto ]] && lang_args=(-F "language=$language")
  curl -sS --fail-with-body "$OMS_ASR_URL" \
    -H "Authorization: Bearer $OMS_ASR_API_KEY" \
    -F "model=$OMS_ASR_MODEL" -F "response_format=verbose_json" \
    -F "timestamp_granularities[]=segment" ${lang_args[@]+"${lang_args[@]}"} \
    -F "file=@$session/${stamp}_audio.wav" -o "$base.json"
  python3 -I - "$base" <<'PY'
import json, sys
base = sys.argv[1]
data = json.load(open(base + ".json", encoding="utf-8"))
segments = data.get("segments") or [{"start": 0, "end": data.get("duration", 0), "text": data.get("text", "")}]
def ts(s, sep=","):
    ms = max(0, round(float(s) * 1000)); h, ms = divmod(ms, 3600000); m, ms = divmod(ms, 60000); s, ms = divmod(ms, 1000)
    return f"{h:02}:{m:02}:{s:02}{sep}{ms:03}"
with open(base + ".srt", "w", encoding="utf-8") as srt, open(base + ".txt", "w", encoding="utf-8") as txt:
    for i, seg in enumerate(segments, 1):
        text = seg["text"].strip()
        srt.write(f"{i}\n{ts(seg['start'])} --> {ts(seg['end'])}\n{text}\n\n")
        txt.write(text + "\n")
PY
fi
[[ -s "$base.srt" ]] || { echo "Transcription produced no speech. See $session/transcription.log" >&2; exit 1; }

# Readable transcript for the model: [hh:mm:ss] text
awk 'BEGIN{RS=""; FS="\n"} { split($2, t, " --> "); sub(/,.*/, "", t[1]); text=""; for (i=3;i<=NF;i++) text=text (i>3?" ":"") $i; print "[" t[1] "] " text }' \
  "$base.srt" >"$base.md"

# --- 4. Summary via OpenCode ------------------------------------------------
echo "→ Summarizing: template=$template_id, detail=$detail, language=$out_language"
prompt="$(awk 'NR==1 && /^---$/ {fm=1; next} fm==1 && /^---$/ {fm=2; next} fm!=1' "$template_file")"
prompt="$prompt"$'\n\n'"$detail_text"
prompt="$prompt"$'\n\nOutput language: '"$out_language"
prompt="$prompt"$'\nMeeting date: '"$(date +%Y-%m-%d)"
[[ -n "$extra" ]] && prompt="$prompt"$'\n\nAdditional instruction from the user:\n'"$extra"
prompt="$prompt"$'\n\nScreen frames: request a frame only when the speech depends on the screen.\nCommand (keep the path in quotes): `"'"$script_dir/frame-at.sh"$'" <hh:mm:ss>`\nThe command works only in the session folder. Do not change the working folder.'

model_args=()
[[ -n "${OMS_MODEL:-}" ]] && model_args=(-m "$OMS_MODEL")

output="$session/outputs/$(date +%Y-%m-%d)_meetingsummary_${template_id}_${detail}.md"
(cd "$session" && opencode run ${model_args[@]+"${model_args[@]}"} --agent meeting-summary --title "Meeting: $name" \
  -f "$base.md" "$prompt") >"$output"

echo "✓ Done: $output"
