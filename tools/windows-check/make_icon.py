"""Build the Windows ICO from the shared PNG rendered from lead-in-b.svg."""
from pathlib import Path

from PIL import Image

root = Path(__file__).resolve().parent
with Image.open(root / 'icon.png') as image:
    image.save(root / 'icon.ico', sizes=[(size, size) for size in (16, 24, 32, 48, 64, 128, 256)])
