# Installation (phase 0)

> Install the Minutes app from the `.dmg`. The guide is in [apps/site/index.html](../../site/index.html#install). This file describes only phase 0 (the script without the app).

Requirements: a Mac with Apple Silicon, macOS 15 or later, approx. 3 GB of free space, OpenCode 2 or later with a model of your choice for the summary step.

## 1. Tools

```
brew install ffmpeg whisper-cpp
brew install opencode
```

## 2. Transcription model (only for the local transcript)

```
mkdir -p ~/.local/share/oms/models
curl -L -o ~/.local/share/oms/models/ggml-large-v3-turbo.bin \
  https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin
```

You download the model one time. After that, the transcript runs without internet.

## 3. OpenCode and the model

1. Set the provider and the model in `~/.config/opencode/opencode.jsonc`. It can be a local model (for example Ollama), a company server or a cloud service.
2. Start the app. The app creates the agent `~/.config/opencode/agent/meeting-summary.md` from the system prompt ([ADR-0015](../../docs/adr/0015-system-prompt-in-app.md)).
3. Check the connection:
   ```
   opencode run --agent meeting-summary "Reply only: OK"
   ```

## 4. Test

```
apps/macos/scripts/process-session.sh <path-to-video> standard strucna
```

## Transcript through a server (optional)

The audio leaves the Mac and goes to a server with an OpenAI-compatible API (`/v1/audio/transcriptions`). The video stays on the Mac.

```
export OMS_ASR=server
export OMS_ASR_API_KEY=<your key>
apps/macos/scripts/process-session.sh <path-to-video>
```

## Troubleshooting

| Problem | Solution |
|---|---|
| `Missing tool: whisper-cli` | Run `brew install whisper-cpp`. |
| The transcript is in the wrong language | Set `OMS_LANGUAGE=sk` or `en`. |
| OpenCode returns no output | Check the VPN and step 3.3. |
