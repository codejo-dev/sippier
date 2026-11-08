#!/usr/bin/env python3
"""Generates the Sippier logo files and app icons.

    python3 branding/generate.py

Writes the SVGs next to this script, the macOS app icon (an Icon Composer
file) and menu bar icons, and the Android launcher and notification icons.
Then renders the Windows app and tray icons with rsvg-convert (librsvg), and
the legacy Android PNGs with render.swift (needs Xcode); each step is
skipped where its tool is missing.

The mark is a superellipse split into two interlocking halves by an S-shaped
channel. It is laid out in a 100x100 box: the body has half-size A, the
channel is C wide, and the S is three bars joined by semicircles of radius R
around a mid bar 2*D long. R and D are picked so every band, counter and
column of the two halves is equally thick. The channel is left transparent,
so the S takes the colour of whatever is behind the mark.
"""
import json
import math
import shutil
import struct
import subprocess
import tempfile
from pathlib import Path

CYAN = ("#7FE0FF", "#25B4F5")     # top-left half, top to bottom
BLUE = ("#2E8CFF", "#1556D6")   # bottom-right half, top to bottom
DOT = "#1E7BF2"                  # the wordmark's i-dots, and the app's theme seed
INK = "#17181C"                  # the wordmark's letters on light backgrounds

A = 42.0              # body half-size
N = 4.0               # superellipse exponent
C = 7.0               # channel width
R = A / 4 + C / 8     # band (A - 2R - C/2) as thick as counter (2R - C)
D = A - 3 * R + C / 2  # column as thick as band
STEPS = 360

HERE = Path(__file__).resolve().parent
APP = HERE.parent / "app"


def num(v):
    return f"{v:.2f}".rstrip("0").rstrip(".")


def body_point(t):
    c, s = math.cos(t), math.sin(t)
    return (50 + A * math.copysign(abs(c) ** (2 / N), c),
            50 + A * math.copysign(abs(s) ** (2 / N), s))


def body_t(y, right):
    """Angle where the body's left or right edge crosses height y (y above
    the centre on the right, below it on the left)."""
    s = math.asin((abs(y - 50) / A) ** (N / 2))
    return 2 * math.pi - s if right else math.pi - s


def half_path(flip=False):
    """The half made of the top band, left column and lower counter, or with
    flip the other half: the same shape turned 180 degrees about the centre."""
    def x(v):
        return num(100 - v if flip else v)

    def y(v):
        return x(v)

    top = 50 - 2 * R - C / 2  # upper edge of the top bar
    low = 50 + 2 * R - C / 2  # upper edge of the bottom bar
    l, r = 50 - D, 50 + D
    ro, ri = num(R + C / 2), num(R - C / 2)
    t0, t1 = body_t(low, right=False), body_t(top, right=True)
    d = [f"M{x(body_point(t1)[0])} {y(top)}H{x(l)}"
         f"A{ro} {ro} 0 0 0 {x(l)} {y(50 + C / 2)}H{x(r)}"
         f"A{ri} {ri} 0 0 1 {x(r)} {y(low)}H{x(body_point(t0)[0])}"]
    for k in range(math.floor(t0 / (2 * math.pi) * STEPS) + 1,
                   math.ceil(t1 / (2 * math.pi) * STEPS)):
        px, py = body_point(2 * math.pi * k / STEPS)
        d.append(f"L{x(px)} {y(py)}")
    return "".join(d) + "Z"


def gradient(id, stops):
    return (f'<linearGradient id="{id}" gradientUnits="userSpaceOnUse" x1="50" y1="{num(50 - A)}" '
            f'x2="50" y2="{num(50 + A)}"><stop offset="0" stop-color="{stops[0]}"/>'
            f'<stop offset="1" stop-color="{stops[1]}"/></linearGradient>')


def mark():
    return (f'<defs>{gradient("cyan", CYAN)}{gradient("blue", BLUE)}</defs>'
            f'<path d="{half_path()}" fill="url(#cyan)"/>'
            f'<path d="{half_path(flip=True)}" fill="url(#blue)"/>')


def wordmark(ink):
    return (
        '<g fill="none" stroke="{ink}" stroke-width="10" stroke-linecap="round" stroke-linejoin="round">'
        '<path d="M33 36C30 32 25 30 18 30C10 30 4 34 4 42C4 50 12 52 18 54C25 56 34 59 34 68'
        'C34 76 27 80 18 80C10 80 4 77 2 73"/>'
        '<path d="M55 30V80M75 30V108M146 30V108M217 30V80M308 80V30M308 55Q308 30 333 30'
        'M237 55H287A25 25 0 1 0 279.7 72.7"/>'
        '<circle cx="100" cy="55" r="25"/><circle cx="171" cy="55" r="25"/></g>'
        '<circle cx="55" cy="12" r="8" fill="{dot}"/><circle cx="217" cy="12" r="8" fill="{dot}"/>'
    ).format(ink=ink, dot=DOT)


def lockup(ink):
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 428 104" role="img">'
            '<title>Sippier</title><g transform="translate(0 2)">' + mark() + '</g>'
            '<g transform="translate(122 0.5) scale(0.9)">' + wordmark(ink) + '</g></svg>\n')


SVGS = {
    "sippier-mark.svg":
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" role="img">'
        '<title>Sippier</title>' + mark() + '</svg>\n',
    "sippier-wordmark.svg":
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="-12 0 356 116" role="img">'
        '<title>sippier</title>' + wordmark(INK) + '</svg>\n',
    "sippier-lockup.svg": lockup(INK),
    # For dark backgrounds, such as GitHub's dark theme.
    "sippier-lockup-dark.svg": lockup("#FFFFFF"),
}

# Adaptive icon: 108dp layers, the launcher mask shows at most the inner 72dp,
# which is where the body would sit. The launcher's mask gives the outline, so
# the halves run out to the layer's edges. A layer can't be see-through, so
# the background behind the S is white, or black in dark mode.
ANDROID_SCALE = 72 / (2 * A)
ANDROID_RES = APP / "android/app/src/main/res"


def bleed_half(size, visible, flip=False):
    """A half of a size x size layer whose system mask shows the inner
    `visible` square, cut by the channel but running out to the edges."""
    scale = visible / (2 * A)

    def x(v):
        v = size / 2 + (v - 50) * scale
        return num(size - v if flip else v)

    y = x
    top = 50 - 2 * R - C / 2
    low = 50 + 2 * R - C / 2
    l, r = 50 - D, 50 + D
    ro, ri = num((R + C / 2) * scale), num((R - C / 2) * scale)
    far, near = ("0", num(size)) if flip else (num(size), "0")
    return (f"M{far},{y(top)}H{x(l)}A{ro},{ro} 0 0,0 {x(l)},{y(50 + C / 2)}"
            f"H{x(r)}A{ri},{ri} 0 0,1 {x(r)},{y(low)}H{near}V{near}H{far}Z")


def vector_path(path, stops=None):
    if stops is None:
        return f'    <path\n        android:fillColor="#FFFFFF"\n        android:pathData="{path}" />\n'
    return (f'    <path android:pathData="{path}">\n'
            '        <aapt:attr name="android:fillColor">\n'
            '            <gradient\n                android:type="linear"\n'
            '                android:startX="54"\n                android:startY="18"\n'
            '                android:endX="54"\n                android:endY="90">\n'
            f'                <item android:offset="0" android:color="{stops[0]}" />\n'
            f'                <item android:offset="1" android:color="{stops[1]}" />\n'
            '            </gradient>\n        </aapt:attr>\n    </path>\n')


def vector(paths, dp=108, viewport=108):
    return ('<?xml version="1.0" encoding="utf-8"?>\n'
            '<!-- Generated by branding/generate.py -->\n'
            '<vector xmlns:android="http://schemas.android.com/apk/res/android"\n'
            '    xmlns:aapt="http://schemas.android.com/aapt"\n'
            f'    android:width="{dp}dp"\n    android:height="{dp}dp"\n'
            f'    android:viewportWidth="{viewport}"\n    android:viewportHeight="{viewport}">\n'
            + "".join(paths) + '</vector>\n')


def color(value):
    return ('<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
            f'    <color name="ic_launcher_background">{value}</color>\n</resources>\n')


ANDROID_FILES = {
    "values/ic_launcher_background.xml": color("#FFFFFF"),
    "values-night/ic_launcher_background.xml": color("#000000"),
    "drawable/ic_launcher_foreground.xml": vector([
        vector_path(bleed_half(108, 72), CYAN), vector_path(bleed_half(108, 72, flip=True), BLUE)]),
    "drawable/ic_launcher_monochrome.xml": vector([
        vector_path(bleed_half(108, 72)), vector_path(bleed_half(108, 72, flip=True))]),
    "mipmap-anydpi-v26/ic_launcher.xml":
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/ic_launcher_background" />\n'
        '    <foreground android:drawable="@drawable/ic_launcher_foreground" />\n'
        '    <monochrome android:drawable="@drawable/ic_launcher_monochrome" />\n'
        '</adaptive-icon>\n',
    # Status bar icon for the notifications: Android only uses its alpha.
    "drawable/ic_stat_sippier.xml": vector(
        [vector_path(half_path()), vector_path(half_path(flip=True))], dp=24, viewport=100),
}
ANDROID_LEGACY = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}

# macOS app icon: an Icon Composer file, so the S can follow the appearance:
# white behind it in light mode, black in dark mode. The system's mask gives
# the outline, so the halves run out to the edges of the 1024pt canvas.
MACOS = APP / "macos/Runner"


def solid(hex):
    r, g, b = (int(hex[i:i + 2], 16) / 255 for i in (1, 3, 5))
    return {"solid": f"srgb:{r:.5f},{g:.5f},{b:.5f},1.00000"}


def icon_gradient(id, stops):
    return (f'<linearGradient id="{id}" gradientUnits="userSpaceOnUse" x1="512" y1="0" '
            f'x2="512" y2="1024"><stop offset="0" stop-color="{stops[0]}"/>'
            f'<stop offset="1" stop-color="{stops[1]}"/></linearGradient>')


ICON = {
    "fill-specializations": [
        {"value": solid("#FFFFFF")},
        {"appearance": "dark", "value": solid("#000000")},
    ],
    "groups": [{
        "layers": [{"glass": False, "image-name": "halves.svg", "name": "halves"}],
        "shadow": {"kind": "none", "opacity": 0.5},
        "specular": False,
        "translucency": {"enabled": False, "value": 0.5},
    }],
    "supported-platforms": {"squares": ["macOS"]},
}


def status_svg(outline):
    """Menu bar template image: the filled mark, or its inner outline."""
    a, b = half_path(), half_path(flip=True)
    svg = '<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 100 100">'
    if not outline:
        return svg + f'<path d="{a}"/><path d="{b}"/></svg>\n'
    # A stroke twice as wide as the outline, clipped to the half it traces.
    return (svg + f'<clipPath id="a"><path d="{a}"/></clipPath><clipPath id="b"><path d="{b}"/></clipPath>'
            f'<path d="{a}" fill="none" stroke="#000" stroke-width="10" clip-path="url(#a)"/>'
            f'<path d="{b}" fill="none" stroke="#000" stroke-width="10" clip-path="url(#b)"/></svg>\n')


def imageset(filename):
    return json.dumps({
        "images": [{"filename": filename, "idiom": "universal"}],
        "info": {"author": "xcode", "version": 1},
        "properties": {"preserves-vector-representation": True,
                       "template-rendering-intent": "template"},
    }, indent=2) + "\n"


MACOS_FILES = {
    "AppIcon.icon/icon.json": json.dumps(ICON, indent=2) + "\n",
    "AppIcon.icon/Assets/halves.svg":
        '<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">'
        f'<defs>{icon_gradient("cyan", CYAN)}{icon_gradient("blue", BLUE)}</defs>'
        f'<path d="{bleed_half(1024, 1024)}" fill="url(#cyan)"/>'
        f'<path d="{bleed_half(1024, 1024, flip=True)}" fill="url(#blue)"/></svg>\n',
    # Menu bar: filled while registered, outlined while not.
    "Assets.xcassets/StatusIcon.imageset/Contents.json": imageset("status.svg"),
    "Assets.xcassets/StatusIcon.imageset/status.svg": status_svg(outline=False),
    "Assets.xcassets/StatusIconOff.imageset/Contents.json": imageset("status-off.svg"),
    "Assets.xcassets/StatusIconOff.imageset/status-off.svg": status_svg(outline=True),
}


# Windows shows app icons without a tile, so the app icon is the mark itself
# and the S shows the taskbar or desktop behind it. Tray: the mark while an
# account is registered, the mark in grey (visible on light and dark
# taskbars) while none is. The macOS outline doesn't work here: at 16 px it
# fills the thin bands. The margin is trimmed to 1 unit, as Windows icons
# fill their square.
WINDOWS = APP / "windows/runner/resources"
WINDOWS_SVG = ('<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" '
               f'viewBox="{num(49 - A)} {num(49 - A)} {num(2 * A + 2)} {num(2 * A + 2)}">')
TRAY_SIZES = (16, 20, 24, 32, 40, 48)
WINDOWS_ICONS = {
    "app_icon.ico": (WINDOWS_SVG + mark() + "</svg>\n",
                     (16, 20, 24, 32, 40, 48, 64, 96, 128, 256)),
    "tray_on.ico": (WINDOWS_SVG + mark() + "</svg>\n", TRAY_SIZES),
    "tray_off.ico": (WINDOWS_SVG + f'<g fill="#8A8A8A"><path d="{half_path()}"/>'
                     f'<path d="{half_path(flip=True)}"/></g></svg>\n', TRAY_SIZES),
}


def ico(images):
    """An .ico file from (size, PNG data) pairs; Windows reads PNG entries."""
    head = struct.pack("<HHH", 0, 1, len(images))
    offset = len(head) + 16 * len(images)
    entries, data = b"", b""
    for size, png in images:
        entries += struct.pack("<BBBBHHII", size % 256, size % 256, 0, 0, 1, 32,
                               len(png), offset + len(data))
        data += png
    return head + entries + data


def windows_icons():
    for name, (svg, sizes) in WINDOWS_ICONS.items():
        pngs = [(size, subprocess.run(["rsvg-convert", "-w", str(size), "-h", str(size)],
                                      input=svg.encode(), capture_output=True,
                                      check=True).stdout)
                for size in sizes]
        WINDOWS.mkdir(parents=True, exist_ok=True)
        (WINDOWS / name).write_bytes(ico(pngs))


def android_legacy_pngs():
    mark_svg = str(HERE / "sippier-mark.svg")
    with tempfile.TemporaryDirectory() as tmp:
        render = Path(tmp) / "render"
        subprocess.run(["xcrun", "swiftc", "-O", str(HERE / "render.swift"), "-o", str(render)],
                       check=True)
        for density, size in ANDROID_LEGACY.items():
            subprocess.run([render, mark_svg, ANDROID_RES / f"mipmap-{density}/ic_launcher.png",
                            str(size), str(size)], check=True)


def write(root, files):
    for name, text in files.items():
        path = root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)


def main():
    write(HERE, SVGS)
    write(ANDROID_RES, ANDROID_FILES)
    write(MACOS, MACOS_FILES)

    if shutil.which("rsvg-convert"):
        windows_icons()
    else:
        print("Skipped the Windows icons: rsvg-convert (librsvg) not found")
    if shutil.which("xcrun"):
        android_legacy_pngs()
    else:
        print("Skipped the legacy Android PNGs: needs Xcode")


if __name__ == "__main__":
    main()
