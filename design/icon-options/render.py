"""Render three proposed icons; these do not replace the application icon."""
from pathlib import Path
import math
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
MINT, WHITE = '#74f4cf', '#eefafa'


def tile():
    image = Image.new('RGBA', (1024, 1024))
    pixels = image.load()
    for y in range(1024):
        for x in range(1024):
            t = (x + y) / 2048
            pixels[x, y] = (int(17 + 8*t), int(36 + 21*t), int(51 + 24*t), 255)
    mask = Image.new('L', image.size)
    ImageDraw.Draw(mask).rounded_rectangle((10, 10, 1014, 1014), 220, fill=255)
    image.putalpha(mask)
    return image


def stroke(draw, points, color, width):
    draw.line(points, fill=color, width=width)
    r = width / 2
    for x, y in points:
        draw.ellipse((x-r, y-r, x+r, y+r), fill=color)


def wave(x0, x1, cy, height, cycles=2):
    return [(x0 + (x1-x0)*t, cy + height * math.sin(2*math.pi*cycles*t)
             * math.sin(math.pi*t)**1.4) for t in (i/400 for i in range(401))]


# A: one magnifying glass and a quiet, even waveform.
a = tile()
d = ImageDraw.Draw(a)
d.ellipse((205, 185, 720, 700), outline=MINT, width=62)
stroke(d, [(654, 635), (815, 797)], MINT, 72)
stroke(d, wave(298, 626, 444, 92), WHITE, 35)

# B: the signal itself becomes a check; there is no extra badge.
b = tile()
d = ImageDraw.Draw(b)
stroke(d, wave(170, 610, 512, 175), MINT, 56)
stroke(d, [(610, 512), (690, 592), (845, 390)], WHITE, 60)

# C: a circular scan closes with a check, with the sound in its centre.
c = tile()
d = ImageDraw.Draw(c)
arc = [(500+292*math.cos(math.radians(t)), 492+292*math.sin(math.radians(t)))
       for t in range(60, 341)]
stroke(d, arc, MINT, 62)
stroke(d, wave(290, 650, 482, 90), WHITE, 36)
stroke(d, [(646, 745), (700, 790), (835, 625)], MINT, 62)

icons = [a, b, c]
for label, icon in zip('ABC', icons):
    icon.save(ROOT / f'{label}.png')
    icon.resize((32, 32), Image.Resampling.LANCZOS).save(ROOT / f'{label}-32.png')

canvas = Image.new('RGB', (1260, 575), '#f1f3f5')
d = ImageDraw.Draw(canvas)
font_path = '/System/Library/Fonts/Supplemental/Arial.ttf'
font = ImageFont.truetype(font_path, 27)
small = ImageFont.truetype(font_path, 18)
for index, (label, icon) in enumerate(zip('ABC', icons)):
    x = 45 + index*410
    canvas.paste(icon.resize((350,350), Image.Resampling.LANCZOS), (x,35),
                 icon.resize((350,350), Image.Resampling.LANCZOS))
    d.text((x+175, 406), label, anchor='mt', font=font, fill='#203243')
    for size, offset in [(64, 91), (32, 201)]:
        scaled = icon.resize((size, size), Image.Resampling.LANCZOS)
        canvas.paste(scaled, (x+offset, 469+(64-size)//2), scaled)
    d.text((x+175, 550), '64 px     32 px', anchor='mt', font=small, fill='#65717c')
canvas.save(ROOT / 'comparison.png')
print(ROOT / 'comparison.png')
