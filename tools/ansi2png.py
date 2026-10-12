"""Draw status lines as a terminal would, into a PNG (or an animated one).

Reads rows from stdin, one per line: `label<TAB>line`, the line as the status
line script wrote it, colour codes and all. A row that is exactly `---` starts
the next frame of an animation.

    render-assets.sh | ansi2png.py --out assets/x.png --text-font D2Coding.ttc --icon-font SymbolsNerdFont.ttf

Only what the status line uses is understood: SGR 0, 1, 38;5;n, 48;5;n,
38;2;r;g;b, the block elements, and private-use glyphs taken from the icon font.
"""
import argparse
import re
import sys

from PIL import Image, ImageDraw, ImageFont

p = argparse.ArgumentParser()
p.add_argument("--out", required=True)
p.add_argument("--text-font", required=True)
p.add_argument("--icon-font", required=True)
p.add_argument("--duration", type=int, default=1000, help="ms per frame of an animation")
args = p.parse_args()

SIZE = 30                      # the text font is half as wide as it is tall: 15 px a cell
CW, CH, GAP = SIZE // 2, 40, 12
PAD_X, PAD_Y, RADIUS = 28, 22, 18
PANEL, BORDER = (27, 28, 33, 255), (58, 60, 70, 255)
FG, LABEL = (214, 217, 224), (118, 124, 136)

text = ImageFont.truetype(args.text_font, SIZE)
icon = ImageFont.truetype(args.icon_font, SIZE - 2)
ascent, descent = text.getmetrics()
TEXT_Y = (CH - (ascent + descent)) // 2

BASE16 = [(0, 0, 0), (205, 49, 49), (13, 188, 121), (229, 229, 16), (36, 114, 200), (188, 63, 188), (17, 168, 205),
          (229, 229, 229), (102, 102, 102), (241, 76, 76), (35, 209, 139), (245, 245, 67), (59, 142, 234),
          (214, 112, 214), (41, 184, 219), (255, 255, 255)]


def xterm(n):
    if n < 16:
        return BASE16[n]
    if n < 232:
        n -= 16
        return tuple(0 if v == 0 else 55 + 40 * v for v in (n // 36, n // 6 % 6, n % 6))
    v = 8 + 10 * (n - 232)
    return (v, v, v)


def cells(line):
    """(char, fg, bg, bold) for every character of a line."""
    out, fg, bg, bold = [], FG, None, False
    for part in re.split(r"(\x1b\[[0-9;]*m)", line):
        if part.startswith("\x1b["):
            codes = [int(c) for c in part[2:-1].split(";") if c] or [0]
            i = 0
            while i < len(codes):
                c = codes[i]
                if c == 0:
                    fg, bg, bold = FG, None, False
                elif c == 1:
                    bold = True
                elif c in (38, 48) and codes[i + 1] == 5:
                    colour = xterm(codes[i + 2])
                    fg, bg = (colour, bg) if c == 38 else (fg, colour)
                    i += 2
                elif c == 38 and codes[i + 1] == 2:
                    fg = tuple(codes[i + 2:i + 5])
                    i += 4
                i += 1
        else:
            out.extend((ch, fg, bg, bold) for ch in part)
    return out


BLOCKS = {"█": 8, "▇": 7, "▆": 6, "▅": 5, "▄": 4, "▃": 3, "▂": 2, "▁": 1}


def draw_row(d, x, y, row):
    for ch, fg, bg, bold in row:
        if bg:
            d.rectangle([x, y, x + CW - 1, y + CH - 1], fill=bg)
        if ch in BLOCKS:
            d.rectangle([x, y + CH - CH * BLOCKS[ch] // 8, x + CW - 1, y + CH - 1], fill=fg)
        elif ch == "░":      # light shade: a quarter of the foreground over the background
            under = bg or PANEL[:3]
            d.rectangle([x, y, x + CW - 1, y + CH - 1], fill=tuple((a + 3 * b) // 4 for a, b in zip(fg, under)))
        elif ch == "▕":
            d.rectangle([x + CW - 2, y, x + CW - 1, y + CH - 1], fill=fg)
        elif ch == "▏":
            d.rectangle([x, y, x + 1, y + CH - 1], fill=fg)
        elif ord(ch) >= 0xE000 and not 0xF900 <= ord(ch) <= 0xFFFF:   # private use: an icon, as wide as it likes
            box = icon.getbbox(ch)
            d.text((x - box[0], y + (CH - (box[3] - box[1])) // 2 - box[1]), ch, font=icon, fill=fg)
        elif ch != " ":
            d.text((x, y + TEXT_Y), ch, font=text, fill=fg)
            if bold:
                d.text((x + 1, y + TEXT_Y), ch, font=text, fill=fg)
        x += CW


frames, rows = [], []
for raw in sys.stdin.read().split("\n"):
    if raw == "---":
        frames.append(rows)
        rows = []
    elif raw.strip():
        label, _, line = raw.partition("\t")
        rows.append((label, cells(line)))
if rows:
    frames.append(rows)

gutter = max(len(label) for rows in frames for label, _ in rows)
gutter = gutter + 2 if gutter else 0
width = max(len(row) for rows in frames for _, row in rows) + gutter
height = max(len(rows) for rows in frames)
W = PAD_X * 2 + width * CW
H = PAD_Y * 2 + height * CH + (height - 1) * GAP

images = []
for rows in frames:
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, W - 1, H - 1], RADIUS, fill=PANEL, outline=BORDER, width=2)
    for n, (label, row) in enumerate(rows):
        y = PAD_Y + n * (CH + GAP)
        d.text((PAD_X, y + TEXT_Y), label, font=text, fill=LABEL)
        draw_row(d, PAD_X + gutter * CW, y, row)
    images.append(img)

if len(images) == 1:
    images[0].save(args.out)
else:
    images[0].save(args.out, save_all=True, append_images=images[1:], duration=args.duration, loop=0)
print(f"{args.out}: {W}x{H}, {len(images)} frame(s)")
