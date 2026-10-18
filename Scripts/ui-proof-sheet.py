"""Builds index.html and sheet.png for one ui-proof run, marking each screen new, changed or same."""
import html
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw

SHEET_COLUMN_WIDTH = 420
SHEET_COLUMNS = 4
LABEL_HEIGHT = 28


def status(image_path, previous_dir):
    if previous_dir is None:
        return "new"
    old = previous_dir / image_path.name
    if not old.exists():
        return "new"
    with Image.open(image_path) as a, Image.open(old) as b:
        if a.size != b.size:
            return "changed"
        diff = ImageChops.difference(a.convert("RGB"), b.convert("RGB"))
        return "changed" if diff.getbbox() else "same"


def write_sheet(run, entries):
    focus = [e for e in entries if e[1] != "same"] or entries
    tiles = []
    for path, state in focus:
        with Image.open(path) as image:
            image = image.convert("RGB")
            scale = min(1.0, SHEET_COLUMN_WIDTH / image.width)
            image = image.resize((int(image.width * scale), int(image.height * scale)))
        tiles.append((path.stem, state, image))
    rows = [tiles[i:i + SHEET_COLUMNS] for i in range(0, len(tiles), SHEET_COLUMNS)]
    heights = [max(t[2].height for t in row) + LABEL_HEIGHT for row in rows]
    sheet = Image.new("RGB", (SHEET_COLUMNS * (SHEET_COLUMN_WIDTH + 12) + 12, sum(heights) + 12 * (len(rows) + 1)),
                      (38, 38, 40))
    draw = ImageDraw.Draw(sheet)
    y = 12
    for row, height in zip(rows, heights):
        x = 12
        for name, state, image in row:
            color = {"changed": (255, 196, 64), "new": (110, 231, 183)}.get(state, (150, 150, 150))
            draw.text((x, y + 6), f"{name}  [{state}]", fill=color)
            sheet.paste(image, (x, y + LABEL_HEIGHT))
            x += SHEET_COLUMN_WIDTH + 12
        y += height + 12
    sheet.save(run / "sheet.png")


def write_html(run, entries):
    order = {"changed": 0, "new": 1, "same": 2}
    cards = "\n".join(
        f'<figure class="{state}"><figcaption>{html.escape(path.stem)} <b>{state}</b></figcaption>'
        f'<img src="{html.escape(path.name)}" loading="lazy"></figure>'
        for path, state in sorted(entries, key=lambda e: (order[e[1]], e[0].name))
    )
    counts = {s: sum(1 for _, st in entries if st == s) for s in order}
    (run / "index.html").write_text(f"""<!doctype html><meta charset="utf-8"><title>UI proof</title>
<style>
body{{margin:0;padding:20px;background:#1c1c1e;color:#ddd;font:13px -apple-system,sans-serif}}
header{{margin-bottom:16px}} label{{margin-left:12px}}
main{{display:grid;grid-template-columns:repeat(auto-fill,minmax(420px,1fr));gap:16px;align-items:start}}
figure{{margin:0;background:#2a2a2c;border-radius:10px;padding:10px}}
figcaption{{margin-bottom:8px}} img{{max-width:100%;display:block}}
b{{font-weight:600}} .changed b{{color:#ffc440}} .new b{{color:#6ee7b7}} .same b{{color:#888}}
body.hide-same .same{{display:none}}
</style>
<header>{counts['changed']} changed · {counts['new']} new · {counts['same']} same
<label><input type="checkbox" checked onchange="document.body.classList.toggle('hide-same',this.checked)"> Hide unchanged</label>
</header>
<body class="hide-same"><main>{cards}</main></body>""")
    return counts


def main():
    run = Path(sys.argv[1])
    previous = Path(sys.argv[2]) if len(sys.argv) > 2 and Path(sys.argv[2]).is_dir() else None
    entries = [(p, status(p, previous)) for p in sorted(run.glob("*.png")) if p.name != "sheet.png"]
    if not entries:
        sys.exit("No screens were rendered.")
    counts = write_html(run, entries)
    write_sheet(run, entries)
    print(f"{counts['changed']} changed · {counts['new']} new · {counts['same']} same")
    print(f"Sheet: {run.resolve() / 'sheet.png'}")
    print(f"Browse: {run.resolve() / 'index.html'}")


main()
