#!/usr/bin/env python3
"""
FarmBook icon generator (Flutter-style logo version).

Place this file in the ROOT of the Flutter repository, next to pubspec.yaml.
The GitHub workflow runs:
    python3 make_icons.py android/app/src/main/res

The logo is drawn from vector shapes, so no embedded image is needed and it
stays sharp at every size.
"""

from pathlib import Path
import sys

from PIL import Image, ImageDraw

# ---- Logo definition (coordinates from the 1024x1024 reference image) ------
LIGHT = (84, 197, 248, 255)   # #54C5F8
MID = (41, 182, 246, 255)     # #29B6F6
DARK = (1, 87, 155, 255)      # #01579B

SHAPES = [
    (LIGHT, [(572, 194), (767, 194), (354, 607), (257, 510)]),   # big top bar
    (LIGHT, [(572, 486), (767, 486), (597, 658), (499, 561)]),   # upper-right
    (MID,   [(499, 561), (597, 658), (499, 754), (401, 657)]),   # middle diamond
    (DARK,  [(597, 658), (767, 829), (572, 829), (499, 754)]),   # dark bottom
]

SS = 4            # supersampling factor for smooth edges
BASE = 1024       # master drawing size


def draw_logo(flat_color=None):
    """Return the logo cropped tightly to its bounds (RGBA, transparent bg)."""
    s = BASE * SS
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    for color, pts in SHAPES:
        fill = flat_color if flat_color else color
        d.polygon([(x * SS, y * SS) for x, y in pts], fill=fill)
    img = img.crop(img.getbbox())
    return img


def make_launcher(logo, size):
    """White rounded-square icon with the logo centered."""
    radius = int(size * 0.22)
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, size - 1, size - 1), radius=radius, fill=255
    )
    bg = Image.new("RGBA", (size, size), (255, 255, 255, 255))
    out = Image.composite(bg, Image.new("RGBA", (size, size), (255, 255, 255, 0)), mask)

    target = int(size * 0.62)
    mark = logo.copy()
    mark.thumbnail((target, target), Image.Resampling.LANCZOS)
    out.alpha_composite(mark, ((size - mark.width) // 2, (size - mark.height) // 2))
    return out


def make_notification_icon(flat_logo, size=96):
    """White silhouette on transparency (Android status-bar style)."""
    pad = int(size * 0.12)
    mark = flat_logo.copy()
    mark.thumbnail((size - 2 * pad, size - 2 * pad), Image.Resampling.LANCZOS)
    icon = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    icon.alpha_composite(mark, ((size - mark.width) // 2, (size - mark.height) // 2))
    return icon


def save_all(res_dir):
    res = Path(res_dir)
    logo = draw_logo()
    flat = draw_logo(flat_color=(255, 255, 255, 255))

    launcher_sizes = {
        "mipmap-mdpi": 48,
        "mipmap-hdpi": 72,
        "mipmap-xhdpi": 96,
        "mipmap-xxhdpi": 144,
        "mipmap-xxxhdpi": 192,
    }
    for folder, size in launcher_sizes.items():
        d = res / folder
        d.mkdir(parents=True, exist_ok=True)
        icon = make_launcher(logo, size)
        icon.save(d / "ic_launcher.png", optimize=True)
        icon.save(d / "ic_launcher_round.png", optimize=True)

    # The notification Dart code uses @drawable/ic_stat_farmbook.
    drawable = res / "drawable"
    drawable.mkdir(parents=True, exist_ok=True)
    make_notification_icon(flat, 96).save(drawable / "ic_stat_farmbook.png", optimize=True)

    # 512px master PNG for any future tooling.
    make_launcher(logo, 512).save(res / "farmbook_logo.png", optimize=True)

    print("FarmBook icons generated successfully.")
    print("Launcher: mipmap-*/ic_launcher.png")
    print("Notification: drawable/ic_stat_farmbook.png")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("Usage: python3 make_icons.py android/app/src/main/res")
    save_all(sys.argv[1])
