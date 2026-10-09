"""Generate the repository's code-defined I&W app icons (requires Pillow)."""
from pathlib import Path
import os
from PIL import Image, ImageDraw, ImageFont

root = Path(__file__).resolve().parents[1]
fonts = [Path(os.environ.get("WINDIR", "C:/Windows")) / "Fonts/seguisb.ttf",
         Path("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf")]
font_path = next((font for font in fonts if font.exists()), None)
if font_path is None:
    raise RuntimeError("Segoe UI Semibold or DejaVu Sans Bold is required to regenerate the icons.")
for name, size, maskable in [("icon-192.png", 192, False), ("icon-512.png", 512, False), ("icon-maskable-512.png", 512, True)]:
    scale = 4
    canvas = Image.new("RGB", (size * scale, size * scale), "#181a20")
    draw = ImageDraw.Draw(canvas)
    font = ImageFont.truetype(str(font_path), int(size * scale * (0.30 if maskable else 0.36)))
    draw.text((size * scale / 2, size * scale * 0.47), "I&W", font=font, fill="white", anchor="mm")
    y = size * scale * 0.70
    draw.rounded_rectangle((size * scale * .30, y, size * scale * .70, y + size * scale * .018), radius=4, fill="#727b90")
    draw.rounded_rectangle((size * scale * .30, y, size * scale * .55, y + size * scale * .018), radius=4, fill="#e8ebf2")
    canvas.resize((size, size), Image.Resampling.LANCZOS).save(root / "public" / name)
