"""Build a self-contained concept gallery from the reviewed SVG proposals."""
from pathlib import Path
import html
import re
from itertools import count

ROOT = Path(__file__).resolve().parent
INSTANCES = count(1)
CONCEPTS = [
    ('A', 'Пластинка', 'Пластинка и завершённый поиск.', 'a-record-v2.svg'),
    ('B', 'Ритм проверен', 'Звуковые уровни переходят в галочку.', 'b-levels-v2.svg'),
    ('C', 'Музыкальная M', 'Буква M с восходящим завершением.', 'c-monogram-v2.svg'),
]


def mark(filename, size):
    svg = (ROOT / 'concepts' / filename).read_text()
    svg = svg.replace('#000000', 'currentColor')
    # Each inline instance has its own accessible title identifier.
    ident = f'{filename.split("-")[0]}-{size}-{next(INSTANCES)}'
    svg = svg.replace('id="title"', f'id="{ident}"').replace(
        'aria-labelledby="title"', f'aria-labelledby="{ident}"')
    svg = svg.replace('id="symbol"', f'id="symbol-{ident}"')
    svg = re.sub(r'<svg ', f'<svg width="{size}" height="{size}" ', svg, count=1)
    return svg


cards = []
for letter, name, note, filename in CONCEPTS:
    sizes = ''.join(f'<div>{mark(filename, size)}<span>{size} px</span></div>'
                    for size in (64, 32, 16))
    cards.append(f'''<article>
      <div class="tile">{mark(filename, 320)}</div>
      <h2>{letter} <span>{html.escape(name)}</span></h2>
      <p>{html.escape(note)}</p>
      <div class="sizes">{sizes}</div>
      <div class="proof"><div class="ink">{mark(filename, 96)}</div>
        <div class="reverse">{mark(filename, 96)}</div></div>
    </article>''')

page = '''<!doctype html>
<html lang="ru"><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Music Check — варианты иконки</title>
<style>
*{box-sizing:border-box}body{margin:0;background:#f3f5f7;color:#142d3d;
font:16px -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}
main{max-width:1260px;margin:auto;padding:34px 30px 26px}
header{display:flex;align-items:center;justify-content:space-between;margin-bottom:25px;gap:20px}
h1{font-size:27px;letter-spacing:-.5px;margin:0 0 6px}header p{margin:0;color:#5d6b77;font-size:15px}
button{font:inherit;font-size:14px;color:inherit;background:white;border:1px solid #d3dce2;
border-radius:10px;padding:11px 16px;cursor:pointer}button:focus-visible{outline:3px solid #16a57c}
.grid{display:grid;grid-template-columns:repeat(3,1fr);gap:22px}article{padding:20px;background:white;
border:1px solid #e1e6eb;border-radius:22px;text-align:center}
.tile{width:100%;max-width:320px;aspect-ratio:1;margin:auto;border-radius:23%;background:#142d3d;
color:#74f4cf;display:grid;place-items:center}.tile svg{width:100%;height:100%}
svg{display:block;flex-shrink:0}h2{font-size:21px;margin:23px 0 8px}h2 span{font-weight:500;margin-left:7px}
article p{font-size:13px;color:#5d6b77;margin:0;min-height:32px;line-height:1.5}
.sizes{display:flex;justify-content:center;align-items:center;gap:30px;height:123px}
.sizes>div{display:flex;flex-direction:column;align-items:center;justify-content:flex-end;height:90px}
.sizes svg{background:#142d3d;color:#74f4cf;border-radius:23%}.sizes span{font-size:11px;color:#687783;
margin-top:10px}.proof{display:flex;border-top:1px solid #e6ebef;padding-top:18px;gap:12px}
.proof>div{display:flex;justify-content:center;flex:1;border-radius:12px}.ink{color:#142d3d;background:#f3f5f7}
.reverse{color:#eefafa;background:#142d3d}footer{font-size:12px;color:#657582;margin-top:20px;text-align:center}
body.mono .tile,body.mono .sizes svg{background:#f0f2f4;color:#142d3d}
@media(max-width:780px){.grid{grid-template-columns:1fr}header{align-items:flex-start}main{padding:24px 16px}}
</style><main><header><div><h1>Проверка музыки</h1><p>Три направления · крупно и в размере значка</p></div>
<button type="button" aria-pressed="false">Посмотреть без цвета</button></header>
<section class="grid">''' + ''.join(cards) + '''</section>
<footer>Галочка означает завершённую проверку. Программа не изменяет музыкальные файлы.</footer>
</main><script>
document.querySelector('button').addEventListener('click',function(){
 const mono=document.body.classList.toggle('mono');
 this.setAttribute('aria-pressed',String(mono));
 this.textContent=mono?'Вернуть цвет':'Посмотреть без цвета';
});
</script></html>'''
(ROOT / 'preview.html').write_text(page)
print(ROOT / 'preview.html')
