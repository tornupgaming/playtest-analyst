"""Draw each probe result onto its frame and lay them out on one contact sheet.

  python -I overlay.py        # needs Pillow; reads results/records.json, writes results/overlays/ and results/sheet.png

Mask: semi-transparent fill plus outline. Box: thin rectangle. Rep 1 only (rep 2 is identical in count).
"""
import json
import re
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).parent
RES = ROOT / "results"
COLORS = [(255, 40, 40), (255, 200, 0), (0, 220, 255), (255, 0, 220), (120, 255, 0), (255, 130, 0)]
FONT = ImageFont.truetype("/usr/share/fonts/TTF/DejaVuSans-Bold.ttf", 15)
TILE_W, TILE_H, COLS = 480, 270, 4


def slug(s):
    return re.sub(r"[^a-z0-9]+", "-", s.lower()).strip("-")


def read_pgm(path):
    data = path.read_bytes()
    _, dims, _, body = data.split(b"\n", 3)
    w, h = map(int, dims.split())
    return Image.frombytes("L", (w, h), body)


def overlay(frame, rec):
    img = Image.open(ROOT / "frames" / f"{frame}.png").convert("RGBA")
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    for i, inst in enumerate(rec["instances"]):
        color = COLORS[i % len(COLORS)]
        b = inst["bounds"]
        full = Image.new("L", img.size, 0)
        full.paste(read_pgm(RES / inst["maskFile"]), (b["left"], b["top"]))
        edge = ImageChops.subtract(full.filter(ImageFilter.MaxFilter(5)), full.filter(ImageFilter.MinFilter(5)))
        layer.paste(Image.new("RGBA", img.size, color + (110,)), mask=full)
        layer.paste(Image.new("RGBA", img.size, color + (255,)), mask=edge)
        box = inst["box"]
        ImageDraw.Draw(layer).rectangle([box["left"], box["top"], box["right"] - 1, box["bottom"] - 1], outline=color + (255,), width=1)
    return Image.alpha_composite(img, layer).convert("RGB")


def caption(img, text, ok):
    d = ImageDraw.Draw(img)
    w = d.textlength(text, font=FONT) + 10
    d.rectangle([0, img.height - 26, w, img.height], fill=(0, 0, 0) if ok else (140, 0, 0))
    d.text((5, img.height - 23), text, font=FONT, fill="white")


records = [r for r in json.load(open(RES / "records.json")) if r["rep"] == 1]
(RES / "overlays").mkdir(exist_ok=True)
tiles = []
for frame in dict.fromkeys(r["frame"] for r in records):
    group = [Image.open(ROOT / "frames" / f"{frame}.png").convert("RGB")]
    caption(group[0], f"{frame}: input frame", True)
    for r in (x for x in records if x["frame"] == frame):
        img = overlay(frame, r)
        n = len(r["instances"])
        conf = f" c={r['instances'][0]['confidence']:.2f}" if n == 1 else ""
        caption(img, f"\"{r['prompt']}\": " + (f"{n} match{'es' if n != 1 else ''}{conf}" if n else "NO MATCH") + f" {r['latencyS']:.1f}s", n > 0)
        img.save(RES / "overlays" / f"{frame}__{slug(r['prompt'])}.png")
        group.append(img)
    group += [Image.new("RGB", (1, 1), (34, 34, 34))] * (-len(group) % COLS)
    tiles += group

rows = len(tiles) // COLS
sheet = Image.new("RGB", (COLS * (TILE_W + 4) + 4, rows * (TILE_H + 4) + 4), (34, 34, 34))
for i, t in enumerate(tiles):
    sheet.paste(t.resize((TILE_W, TILE_H), Image.LANCZOS), (4 + (i % COLS) * (TILE_W + 4), 4 + (i // COLS) * (TILE_H + 4)))
sheet.save(RES / "sheet.png")
print(sheet.size)
