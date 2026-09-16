#!/usr/bin/env python3
"""Render the BlitzRecorder DMG background + a Finder-accurate preview."""

from __future__ import annotations

from subprocess import DEVNULL, check_call
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
OUT_DIR = REPO / "Resources/dmg"
MARK = HERE / "mark.png"
APP_ICON = REPO / "Resources/BlitzRecorder.icns"
APPS_ICON = Path("/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/ApplicationsFolderIcon.icns")

# create-dmg window. Icon positions are centers in logical pixels.
WIDTH, HEIGHT = 760, 480
SCALE = 2
ICON = 128
APP = (210, 228)
APPS = (550, 228)

PAPER = (238, 242, 239)
PAPER_DEEP = (226, 232, 228)
INK = (15, 22, 18)
MINT = (14, 168, 110)
MINT_GLOW = (23, 255, 166)


def px(n: float) -> int:
    return int(round(n * SCALE))


def font(size: int) -> ImageFont.FreeTypeFont:
    for path, index in (
        ("/System/Library/Fonts/SFNS.ttf", 0),
        ("/System/Library/Fonts/HelveticaNeue.ttc", 0),
    ):
        try:
            return ImageFont.truetype(path, px(size), index=index)
        except OSError:
            continue
    raise RuntimeError("no usable UI font")


def lerp(a: tuple[int, int, int], b: tuple[int, int, int], t: float) -> tuple[int, int, int]:
    t = max(0.0, min(1.0, t))
    return (
        int(a[0] + (b[0] - a[0]) * t),
        int(a[1] + (b[1] - a[1]) * t),
        int(a[2] + (b[2] - a[2]) * t),
    )


def paper() -> Image.Image:
    w, h = px(WIDTH), px(HEIGHT)
    img = Image.new("RGB", (w, h), PAPER)
    pixels = img.load()
    cx, cy = px(WIDTH * 0.5), px(HEIGHT * 0.42)
    rx, ry = px(280), px(160)
    for y in range(h):
        gy = y / max(1, h - 1)
        row = lerp(PAPER, PAPER_DEEP, gy * 0.7)
        for x in range(w):
            dx = (x - cx) / rx
            dy = (y - cy) / ry
            bloom = max(0.0, 1.0 - (dx * dx + dy * dy))
            bloom = bloom * bloom * 0.10
            pixels[x, y] = lerp(row, MINT_GLOW, bloom)
    return img


def draw_arrow(base: Image.Image) -> Image.Image:
    layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    y = px(APP[1])
    x0 = px(APP[0] + ICON / 2 + 28)
    x1 = px(APPS[0] - ICON / 2 - 28)
    # Soft mint halo, then a 2px shaft and a tight chevron.
    halo = Image.new("RGBA", base.size, (0, 0, 0, 0))
    hd = ImageDraw.Draw(halo)
    hd.line((x0, y, x1 - px(10), y), fill=(*MINT_GLOW, 70), width=px(5))
    halo = halo.filter(ImageFilter.GaussianBlur(px(3)))
    draw.line((x0, y, x1 - px(12), y), fill=(*MINT, 255), width=px(2))
    tip = x1
    head = [
        (tip, y),
        (tip - px(13), y - px(6)),
        (tip - px(13), y + px(6)),
    ]
    draw.polygon(head, fill=(*MINT, 255))
    out = base.convert("RGBA")
    out.alpha_composite(halo)
    out.alpha_composite(layer)
    return out


def draw_wordmark(base: Image.Image) -> Image.Image:
    overlay = Image.new("RGBA", base.size, (0, 0, 0, 0))
    mark = Image.open(MARK).convert("RGBA").resize((px(18), px(18)), Image.Resampling.LANCZOS)
    title = font(13)
    draw = ImageDraw.Draw(overlay)
    name = "BlitzRecorder"
    name_w = draw.textlength(name, font=title)
    brand_w = px(18) + px(8) + name_w
    x = int((px(WIDTH) - brand_w) / 2)
    y = px(28)
    overlay.alpha_composite(mark, (x, y))
    draw = ImageDraw.Draw(overlay)
    draw.text((x + px(26), y + px(1)), name, font=title, fill=(*INK, 220))
    out = base.convert("RGBA")
    out.alpha_composite(overlay)
    return out


def background() -> Image.Image:
    img = draw_wordmark(draw_arrow(paper()))
    return img.resize((WIDTH, HEIGHT), Image.Resampling.LANCZOS).convert("RGB")


def load_icon(path: Path, size: int = ICON) -> Image.Image:
    if path.suffix == ".icns":
        tmp = Path("/tmp") / f"{path.stem}-{size}.png"
        check_call(
            ["sips", "-s", "format", "png", "-Z", str(size * 2), str(path), "--out", str(tmp)],
            stdout=DEVNULL,
        )
        img = Image.open(tmp).convert("RGBA")
    else:
        img = Image.open(path).convert("RGBA")
    return img.resize((size, size), Image.Resampling.LANCZOS)


def paste_icon(canvas: Image.Image, icon: Image.Image, center: tuple[int, int]) -> None:
    x = center[0] - icon.width // 2
    y = center[1] - icon.height // 2
    # Soft contact shadow, then the icon.
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    pad = 10
    sd.ellipse(
        (x + pad, y + icon.height - 18, x + icon.width - pad, y + icon.height + 6),
        fill=(20, 30, 24, 38),
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(6))
    canvas.alpha_composite(shadow)
    canvas.alpha_composite(icon, (x, y))


def preview(bg: Image.Image) -> Image.Image:
    canvas = bg.convert("RGBA")
    paste_icon(canvas, load_icon(APP_ICON), APP)
    paste_icon(canvas, load_icon(APPS_ICON), APPS)
    draw = ImageDraw.Draw(canvas)
    label = ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", 12)
    for text, center in (("BlitzRecorder", APP), ("Applications", APPS)):
        w = draw.textlength(text, font=label)
        draw.text(
            (center[0] - w / 2, center[1] + ICON / 2 + 6),
            text,
            font=label,
            fill=(29, 29, 31, 230),
        )
    return canvas.convert("RGB")


if __name__ == "__main__":
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    bg = background()
    bg_path = OUT_DIR / "background.png"
    preview_path = OUT_DIR / "preview.png"
    bg.save(bg_path, optimize=True)
    preview(bg).save(preview_path, optimize=True)
    gif = OUT_DIR / "background.gif"
    if gif.exists():
        gif.unlink()
    print(f"wrote {bg_path} ({bg_path.stat().st_size} bytes)")
    print(f"wrote {preview_path} ({preview_path.stat().st_size} bytes)")
