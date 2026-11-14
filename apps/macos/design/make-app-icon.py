#!/usr/bin/env python3
"""Generates the Minutes app icon (Icon Composer .icon) with a light and a dark appearance.

Light = "R2 paper", dark = "R1 ink and amber". See docs/adr/0020-app-icon-light-dark.md.
Usage: python3 make-app-icon.py <output AppIcon.icon folder>
"""
import json
import math
import pathlib
import sys

C = 512
# The motif was designed on an 824 px icon body. Icon Composer uses the full 1024 px canvas.
# 1.2 (not 1024 / 824) keeps a calm margin around the minute ticks.
SCALE = 1.2
ARC_END = 0.68  # Part of the circle the amber arc covers: "recorded minutes".
BARS = [120, 230, 300, 360, 210, 140]  # Speech rhythm: the tallest bar is right of center.


def polar(r, frac):
    a = frac * 2 * math.pi - math.pi / 2
    return C + math.cos(a) * r, C + math.sin(a) * r


def arc_path(r, start, end):
    x1, y1 = polar(r, start)
    x2, y2 = polar(r, end)
    large = 1 if end - start > 0.5 else 0
    return f"M{x1:.1f} {y1:.1f}A{r} {r} 0 {large} 1 {x2:.1f} {y2:.1f}"


def ticks(color, opacity):
    lines = []
    for i in range(12):
        if i in (0, 8):  # 12 o'clock is the arc start, 8 o'clock is under the knob.
            continue
        x1, y1 = polar(306, i / 12)
        x2, y2 = polar(322, i / 12)
        lines.append(f'<line x1="{x1:.1f}" y1="{y1:.1f}" x2="{x2:.1f}" y2="{y2:.1f}" '
                     f'stroke="{color}" stroke-opacity="{opacity}" stroke-width="9" stroke-linecap="round"/>')
    return "".join(lines)


def bars(fill):
    width, gap = 38, 26
    total = len(BARS) * width + (len(BARS) - 1) * gap
    out = []
    for i, h in enumerate(BARS):
        x = C - total / 2 + i * (width + gap)
        out.append(f'<rect x="{x}" y="{C - h / 2}" width="{width}" height="{h}" rx="{width / 2}" fill="{fill}"/>')
    return "".join(out)


def svg(defs, body):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">'
            f'<defs>{defs}</defs><g transform="translate({C} {C}) scale({SCALE:.4f}) translate(-{C} -{C})">{body}</g></svg>')


def knob(ring, fill):
    x, y = polar(258, ARC_END)
    return f'<circle cx="{x:.1f}" cy="{y:.1f}" r="44" fill="{ring}"/><circle cx="{x:.1f}" cy="{y:.1f}" r="26" fill="{fill}"/>'


AMBER = ('<linearGradient id="arc" x1="0" y1="0" x2="1" y2="1">'
         '<stop offset="0" stop-color="#ffd27a"/><stop offset="1" stop-color="#ff9a3c"/></linearGradient>')
CORAL = ('<linearGradient id="arc" x1="0" y1="0" x2="1" y2="1">'
         '<stop offset="0" stop-color="#ffb347"/><stop offset="1" stop-color="#ff6b4a"/></linearGradient>')

LAYERS = {
    # Dial: minute ticks, ring track and (dark only) a glass disc.
    "dial-light.svg": svg("", ticks("#1b1f5c", 0.25) +
                          '<circle cx="512" cy="512" r="258" fill="none" stroke="#1b1f5c" stroke-opacity=".08" stroke-width="40"/>'),
    "dial-dark.svg": svg('<radialGradient id="disc" cx=".5" cy=".3" r=".8"><stop offset="0" stop-color="#3a428f"/>'
                         '<stop offset="1" stop-color="#171a4d"/></radialGradient>',
                         ticks("#ffffff", 0.3) +
                         '<circle cx="512" cy="512" r="226" fill="url(#disc)"/>'
                         '<circle cx="512" cy="512" r="226" fill="none" stroke="#fff" stroke-opacity=".10" stroke-width="3"/>'
                         '<circle cx="512" cy="512" r="258" fill="none" stroke="#fff" stroke-opacity=".08" stroke-width="40"/>'),
    # Arc with a knob at its end: the recorded time.
    "arc-light.svg": svg(CORAL, f'<path d="{arc_path(258, 0, ARC_END)}" fill="none" stroke="url(#arc)" stroke-width="40" stroke-linecap="round"/>'
                         + knob("#ffffff", "#ff7a4a")),
    "arc-dark.svg": svg(AMBER, f'<path d="{arc_path(258, 0, ARC_END)}" fill="none" stroke="url(#arc)" stroke-width="40" stroke-linecap="round"/>'
                        + knob("#fff6e6", "#ffb347")),
    # Voice waveform, lit from the top.
    "wave-light.svg": svg('<linearGradient id="bar" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#3b45b8"/>'
                          '<stop offset="1" stop-color="#1b1f5c"/></linearGradient>', bars("url(#bar)")),
    "wave-dark.svg": svg('<linearGradient id="bar" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ffffff"/>'
                         '<stop offset="1" stop-color="#cfd5ff"/></linearGradient>', bars("url(#bar)")),
}


def gradient(top, bottom):
    return {"linear-gradient": [top, bottom], "orientation": {"start": {"x": 0.5, "y": 0}, "stop": {"x": 0.5, "y": 1}}}


def layer(name, appearance):
    return {"name": f"{name}-{appearance}", "image-name": f"{name}-{appearance}.svg", "glass": False}


def group(appearance, names, shadow):
    """A group for one appearance. The other appearance hides it."""
    light = appearance == "light"
    return {
        "name": f"{'+'.join(names)}-{appearance}",
        "layers": [layer(n, appearance) for n in names],
        # Dark and tinted (monochrome) use the dark layers: their white waveform keeps contrast when tinted.
        "hidden-specializations": [
            {"value": not light},
            {"appearance": "dark", "value": light},
            {"appearance": "tinted", "value": light},
        ],
        "shadow": {"kind": "neutral", "opacity": 0.35} if shadow else {"kind": "none", "opacity": 0},
        "translucency": {"enabled": False, "value": 0.5},
    }


ICON = {
    "fill-specializations": [
        {"value": gradient("srgb:1.00000,1.00000,1.00000,1.00000", "srgb:0.90196,0.91373,0.95294,1.00000")},
        {"appearance": "dark", "value": gradient("srgb:0.16863,0.19216,0.43922,1.00000", "srgb:0.04706,0.05490,0.16863,1.00000")},
    ],
    # The top layer is listed first.
    "groups": [
        group("light", ["wave", "arc"], True),
        group("dark", ["wave", "arc"], True),
        group("light", ["dial"], False),
        group("dark", ["dial"], False),
    ],
    "supported-platforms": {"squares": ["macOS"]},
}


def main():
    out = pathlib.Path(sys.argv[1])
    assets = out / "Assets"
    assets.mkdir(parents=True, exist_ok=True)
    for name, content in LAYERS.items():
        (assets / name).write_text(content)
    (out / "icon.json").write_text(json.dumps(ICON, indent=2) + "\n")


if __name__ == "__main__":
    main()
