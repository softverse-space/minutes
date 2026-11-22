# ADR-0036: Session detail with the result first, and shared popover styles

- **Status:** Proposed
- **Date:** 2026-11-22
- **Decided by:** Henrich Neuschl

## Context

A UI review of the app and the website found these problems:

- The session detail showed the summary form first. The finished summaries were at the end, under the form.
- The detail title was the date. The sessions list showed the topic. The same session had two names.
- The Outputs list showed long file names that the popover cut in the middle.
- The popover had four banner styles and five corner radii. The cards were almost invisible on the popover material.
- Start recording was red, but Stop recording was blue.
- The state of a session in the list was only the color of an icon.

## Options

1. **Keep the layout, fix only the colors** – small change, but the main task (read or copy the summary) stays at the end of the detail.
2. **Result first, form on request** – the summaries are on top. The form opens when the session has no summary, while a summary job runs, after a failure, or after **New summary…**.
3. **Separate tabs in the detail (Summary, Transcript, Outputs)** – clear, but one more click for each task, and the popover is small.

## Decision

We take option 2, and we add shared styles:

- **Session detail:** the Outputs card is first. The Summary card is a closed row with **New summary…** when the session has a summary. A new summary closes the form again.
- **Title:** the detail and the list use the topic. Without a topic, the list shows "Meeting at 15:30".
- **Outputs:** each row shows the topic, the version and the time of the file. The file name is in the tooltip.
- **Shared styles:** `Metrics.smallRadius` (8 pt) and `Metrics.cardRadius` (12 pt), `Color.cardFill` (white 62 % in light mode, white 7 % in dark mode), and one `Banner` view with the tones info, warning and danger.
- **Recording:** Stop recording has the same red as Start recording. The audio sources are in a card. The blinking dot stays on with Reduce Motion.
- **Sessions list:** VoiceOver reads the state as text. The list shows the screen name only when the sessions use more than one screen.
- **New session:** the microphone picker has its own row. **Import a recording…** is a smaller button below Start recording.

## Consequences

- The website screenshots of the popover and of Settings show the old layout. They must be made again, in English and in Slovak.
- The detail needs one more click to make a second summary. We accept this, because most sessions get one summary.
- New views use `Card`, `Banner` and `Metrics`. Do not add new radii or banner colors.
