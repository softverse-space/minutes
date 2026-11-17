#!/usr/bin/env python3
"""Writes the GitHub release notes for one version from CHANGELOG.md.

Usage: release_notes.py <CHANGELOG.md> <version> <output.md>

Relative links (../../docs/...) become absolute GitHub links.
"""
import re
import sys

REPO = "https://github.com/softverse-space/minutes"


def main() -> None:
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    changelog, version, output = sys.argv[1:]
    text = open(changelog, encoding="utf-8").read()
    match = re.search(rf"^## {re.escape(version)}\b.*?$(.*?)(?=^## |\Z)", text, re.M | re.S)
    if not match:
        sys.exit(f"CHANGELOG.md has no section '## {version}'.")
    body = match.group(1).strip()
    body = re.sub(r"\]\((?:\.\./)+([^)]+)\)", rf"]({REPO}/blob/main/\1)", body)
    body += (
        "\n\n### Install\n"
        f"- Download `Minutes-{version}.dmg`, open it and move Minutes to Applications.\n"
        "- From version 1.1.0, the app updates itself. Version 1.0.0 needs one manual install.\n"
    )
    open(output, "w", encoding="utf-8").write(body + "\n")


if __name__ == "__main__":
    main()
