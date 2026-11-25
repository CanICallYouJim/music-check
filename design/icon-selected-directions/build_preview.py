"""Show the selected originals next to restrained SVG refinements."""
from pathlib import Path
import base64
from itertools import count
import re

ROOT = Path(__file__).resolve().parent
ORIGINALS = ROOT / 'originals'
SERIAL = count(1)


def svg_mark(filename, size):
    content = (ROOT / filename).read_text()
    suffix = str(next(SERIAL))
    content = content.replace('id="title"', f'id="title-{suffix}"').replace(
        'aria-labelledby="title"', f'aria-labelledby="title-{suffix}"')
    content = content.replace('id="symbol"', f'id="symbol-{suffix}"')
    return re.sub(r'<svg ', f'<svg width="{size}" height="{size}" ', content, count=1)


cards = []
for letter, filename, original, note in [
    ('A', 'a-lens.svg', 'A-lens.png', 'Ровнее столбики и чище соединение ручки с кольцом.'),
    ('B', 'b-scan.svg', 'B-scan.png', 'Плавнее изгибы волны; сканирующая линия сохранена.'),
]:
    encoded = base64.b64encode((ORIGINALS / original).read_bytes()).decode()
    small = ''.join(f'<div><div class="tile">{svg_mark(filename, s)}</div><span>{s} px</span></div>'
                    for s in (64, 32, 16))
    cards.append(f'''<article><h2>{letter}</h2><div class="pair">
      <figure><img width="224" height="224" src="data:image/png;base64,{encoded}" alt="Исходный {letter}">
      <figcaption>Исходный {letter}</figcaption></figure>
      <figure><div class="tile">{svg_mark(filename,224)}</div><figcaption>Доводка {letter}</figcaption></figure>
      </div><p>{note}</p><div class="sizes">{small}</div></article>''')

page = '''<!doctype html><html lang="ru"><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Проверка музыки — исходные A и B</title><style>
*{box-sizing:border-box}body{margin:0;color:#142d3d;background:#edf1f4;
font:16px -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}
main{max-width:1160px;margin:auto;padding:30px}h1{font-size:27px;margin:0 0 9px;letter-spacing:-.5px}
header p{color:#65717b;margin:0 0 24px;font-size:15px}.grid{display:grid;grid-template-columns:1fr 1fr;gap:22px}
article{background:#fff;border:1px solid #dce4e9;border-radius:22px;padding:24px}h2{font-size:24px;margin:0 0 18px}
.pair{display:flex;justify-content:space-between;gap:20px}figure{margin:0;min-width:0;width:224px}
figure>.tile,figure>img{width:100%;height:auto;aspect-ratio:1}img,.tile{border-radius:22%;overflow:hidden}
.tile{background:linear-gradient(135deg,#112433,#19394b);display:grid;place-items:center}
svg{display:block;max-width:100%;height:auto}figcaption{font-size:13px;color:#65717b;margin-top:10px;text-align:center}
article p{font-size:14px;line-height:1.5;margin:24px 0 0;min-height:42px}
.sizes{display:flex;justify-content:center;align-items:flex-end;gap:36px;margin-top:20px;padding-top:20px;
border-top:1px solid #e5ebef}.sizes>div{display:flex;align-items:center;flex-direction:column;gap:10px}
.sizes span{font-size:11px;color:#65717b}.sizes svg{max-width:none}
@media(max-width:850px){.grid{grid-template-columns:1fr}main{padding:20px}.pair{justify-content:center}h1{font-size:24px}}
</style><main><header><h1>Проверка музыки · A и B</h1>
<p>Сохранил выбранные композиции. Изменения — только в геометрии.</p></header>
<section class="grid">''' + ''.join(cards) + '</section></main></html>'
(ROOT / 'preview.html').write_text(page)
print(ROOT / 'preview.html')
