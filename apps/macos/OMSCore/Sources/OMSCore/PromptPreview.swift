import Foundation

/// The full text that a summary engine gets, as one Markdown file that the user can read before the summary.
public enum PromptPreview {
    public static func render(systemPrompt: String, taskPrompt: String, engine: String, model: String,
                              transcriptFile: String, transcriptWords: Int?) -> String {
        let modelLine = model.isEmpty ? engine : "\(engine) · \(model)"
        let transcript = transcriptWords.map {
            "The app adds `\(transcriptFile)` (\($0) words) after the task. The preview does not show it."
        } ?? "The session has no transcript yet. The summary starts only after the transcription."

        return """
        <!-- Minutes prompt preview. The app does not read this file. Changes here have no effect. -->

        # Prompt for the next summary

        Model: \(modelLine)

        The model gets three parts in this order:

        1. **System prompt:** the rules for all summaries. Change them in Settings → Summary → System prompt → Edit.
        2. **Task:** the app builds it from the template, the detail, the language, Extra and the frame rules of this session.
        3. **Transcript** of the meeting.

        ---

        # 1. System prompt

        \(systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines))

        ---

        # 2. Task

        \(taskPrompt.trimmingCharacters(in: .whitespacesAndNewlines))

        ---

        # 3. Transcript

        \(transcript)

        """
    }

    /// Number of words in a text, for the transcript line of the preview.
    public static func wordCount(_ text: String) -> Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }
}
