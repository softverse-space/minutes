#!/usr/bin/env python3
"""Adds one release to the Sparkle appcast (ADR-0031). apps/macos/scripts/appcast.sh calls it.

Usage: appcast_item.py <appcast.xml> <CHANGELOG.md> <version> <build> <download-url> <signature> <length>

The release notes come from the section "## <version>" of CHANGELOG.md, converted to simple HTML.
"""
import html
import re
import sys
from email.utils import formatdate

REPO = "https://github.com/softverse-space/minutes"
MINIMUM_SYSTEM_VERSION = "15.0"


def changelog_section(text: str, version: str) -> str:
    match = re.search(rf"^## {re.escape(version)}\b.*?$(.*?)(?=^## |\Z)", text, re.M | re.S)
    if not match:
        sys.exit(f"CHANGELOG.md has no section '## {version}'.")
    return match.group(1).strip()


def inline(text: str) -> str:
    text = html.escape(text, quote=False)
    text = re.sub(r"`([^`]+)`", r"<code>\1</code>", text)
    text = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", text)

    def link(m: re.Match) -> str:
        label, target = m.group(1), m.group(2)
        if not re.match(r"https?://", target):
            # Links in CHANGELOG.md are relative to apps/macos/.
            target = re.sub(r"^(\.\./)+", "", target)
            target = f"{REPO}/blob/main/{target}"
        return f'<a href="{html.escape(target)}">{label}</a>'

    return re.sub(r"\[([^\]]+)\]\(([^)]+)\)", link, text)


def to_html(markdown: str) -> str:
    out, in_list = [], False
    for line in markdown.splitlines():
        line = line.rstrip()
        if line.startswith("- "):
            if not in_list:
                out.append("<ul>")
                in_list = True
            out.append(f"<li>{inline(line[2:])}</li>")
            continue
        if in_list:
            out.append("</ul>")
            in_list = False
        if line.startswith("### "):
            out.append(f"<h3>{inline(line[4:])}</h3>")
        elif line:
            out.append(f"<p>{inline(line)}</p>")
    if in_list:
        out.append("</ul>")
    return "\n".join(out)


def main() -> None:
    if len(sys.argv) != 8:
        sys.exit(__doc__)
    appcast_path, changelog_path, version, build, url, signature, length = sys.argv[1:]
    appcast = open(appcast_path, encoding="utf-8").read()

    builds = [int(b) for b in re.findall(r"<sparkle:version>(\d+)</sparkle:version>", appcast)]
    if builds and int(build) <= max(builds):
        sys.exit(f"Build {build} is not higher than build {max(builds)} in the appcast. Increase CURRENT_PROJECT_VERSION.")

    notes = to_html(changelog_section(open(changelog_path, encoding="utf-8").read(), version))
    item = f"""    <item>
      <title>Minutes {version}</title>
      <pubDate>{formatdate(usegmt=True)}</pubDate>
      <sparkle:version>{build}</sparkle:version>
      <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>{MINIMUM_SYSTEM_VERSION}</sparkle:minimumSystemVersion>
      <sparkle:fullReleaseNotesLink>{REPO}/releases/tag/v{version}</sparkle:fullReleaseNotesLink>
      <description><![CDATA[
{notes}
      ]]></description>
      <enclosure url="{html.escape(url)}" length="{length}" type="application/x-apple-diskimage" sparkle:edSignature="{signature}"/>
    </item>
"""
    # The newest item comes first, after the channel header.
    marker = "    <language>en</language>\n"
    if marker not in appcast:
        sys.exit("The appcast has no <language> line.")
    appcast = appcast.replace(marker, marker + item, 1)
    open(appcast_path, "w", encoding="utf-8").write(appcast)


if __name__ == "__main__":
    main()
