"""Generate the 1024x1024 app icon for AsrRecognize."""

from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "AsrRecognize" / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon.png"

S = 2048

# Background: deep space black with soft blue / violet light.
y, x = np.mgrid[0:S, 0:S].astype(np.float32)
cx, cy = S * 0.5, S * 0.40
radius = np.sqrt((x - cx) ** 2 + (y - cy) ** 2) / (S * 0.72)
blue_glow = np.clip(1.0 - radius, 0.0, 1.0) ** 2.2

cx2, cy2 = S * 0.80, S * 0.88
radius2 = np.sqrt((x - cx2) ** 2 + (y - cy2) ** 2) / (S * 0.62)
violet_glow = np.clip(1.0 - radius2, 0.0, 1.0) ** 2.4

arr = np.zeros((S, S, 3), dtype=np.float32) + np.array([6, 7, 10], dtype=np.float32)
arr += blue_glow[..., None] * np.array([30, 66, 130], dtype=np.float32)
arr += violet_glow[..., None] * np.array([36, 20, 82], dtype=np.float32)

vignette = 1.0 - np.clip((radius - 0.32) * 0.55, 0.0, 0.45)
arr *= vignette[..., None]
img = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8)).convert("RGB")

# Symmetric waveform bars.
bar_count = 7
bar_w = int(S * 0.057)
gap = int(S * 0.044)
total_w = bar_count * bar_w + (bar_count - 1) * gap
start_x = (S - total_w) // 2
center_y = S * 0.5
heights = [0.30, 0.52, 0.76, 1.0, 0.76, 0.52, 0.30]
max_h = S * 0.40

mask = Image.new("L", (S, S), 0)
draw = ImageDraw.Draw(mask)
for index, factor in enumerate(heights):
    bar_h = max_h * factor
    x0 = start_x + index * (bar_w + gap)
    y0 = center_y - bar_h / 2
    draw.rounded_rectangle(
        [x0, y0, x0 + bar_w, y0 + bar_h],
        radius=bar_w / 2,
        fill=255,
    )

# Ambient glow behind the bars.
glow_mask = mask.filter(ImageFilter.GaussianBlur(S * 0.036))
glow_layer = Image.new("RGBA", (S, S), (74, 158, 255, 0))
glow_layer.putalpha(glow_mask.point(lambda value: int(value * 0.55)))
img = Image.alpha_composite(img.convert("RGBA"), glow_layer).convert("RGB")

# Cyan -> blue gradient inside the bars.
top_color = np.array([96, 236, 255], dtype=np.float32)
bottom_color = np.array([86, 108, 255], dtype=np.float32)
t = (np.arange(S, dtype=np.float32) / S)[:, None, None]
gradient = top_color[None, None, :] * (1.0 - t) + bottom_color[None, None, :] * t
gradient = np.repeat(gradient, S, axis=1)
bar_image = Image.fromarray(np.clip(gradient, 0, 255).astype(np.uint8))
img.paste(bar_image, (0, 0), mask)

# Subtle top shine inside the bars.
shine = Image.new("RGBA", (S, S), (255, 255, 255, 0))
alpha = (np.clip(1.0 - np.arange(S, dtype=np.float32) / (S * 0.62), 0.0, 1.0) ** 3 * 46).astype(np.uint8)
alpha_img = Image.fromarray(np.repeat(alpha[:, None], S, axis=1), mode="L")
shine.putalpha(Image.composite(alpha_img, Image.new("L", (S, S), 0), mask))
img = Image.alpha_composite(img.convert("RGBA"), shine).convert("RGB")

# A tiny accent dot for the recording motif.
dot_layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
dot = ImageDraw.Draw(dot_layer)
dot_r = int(S * 0.018)
dot_cx, dot_cy = S * 0.5, S * 0.5 - max_h / 2 - S * 0.085
dot.ellipse(
    [dot_cx - dot_r, dot_cy - dot_r, dot_cx + dot_r, dot_cy + dot_r],
    fill=(255, 69, 58, 235),
)
dot_glow = dot_layer.filter(ImageFilter.GaussianBlur(S * 0.012))
img = Image.alpha_composite(img.convert("RGBA"), dot_glow)
img = Image.alpha_composite(img, dot_layer).convert("RGB")

icon = img.resize((1024, 1024), Image.LANCZOS)
OUT.parent.mkdir(parents=True, exist_ok=True)
icon.save(OUT, format="PNG")
print(f"wrote {OUT}")
