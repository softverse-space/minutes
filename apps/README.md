# apps/

Each app of the project has its own folder ([ADR-0024](../docs/adr/0024-apps-folder-per-platform.md)).

| Folder | Content |
|---|---|
| [`macos/`](macos/) | Minutes for macOS: the app, `OMSCore`, templates, prompts, scripts and icon |
| [`site/`](site/) | User guide (one HTML page, English and Slovak) |

A Linux or Windows version gets a new folder, for example `linux/` or `windows/`.
Templates and the system prompt are in `macos/` now. When a second app needs them, move them to a shared folder and record it in an ADR.
