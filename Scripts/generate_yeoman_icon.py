#!/usr/bin/env python3
import os
import subprocess
import shutil
from PIL import Image, ImageDraw, ImageFilter
import numpy as np

def generate():
    root_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    src_path = os.path.join(root_dir, "Resources", "AppIcon_Source.jpg")
    if not os.path.exists(src_path):
        print(f"Source file not found at: {src_path}")
        return

    src = Image.open(src_path).convert("RGB")
    crop_box = (310, 315, 715, 705)
    emblem_crop = src.crop(crop_box)
    arr = np.array(emblem_crop).astype(float)
    
    bg = 255.0
    diff = 255.0 - arr
    alpha = np.max(diff, axis=2) / 255.0
    alpha = np.clip((alpha - 0.03) / 0.94, 0.0, 1.0)
    
    fg = np.zeros_like(arr)
    mask = alpha > 0.01
    for c in range(3):
        fg[mask, c] = np.clip((arr[mask, c] - (1 - alpha[mask]) * bg) / alpha[mask], 0, 255)
    
    rgba = np.dstack([fg, alpha * 255.0]).astype(np.uint8)
    emblem_img = Image.fromarray(rgba, mode="RGBA")
    
    canvas_size = 1024
    icon_size = 824
    inset = (canvas_size - icon_size) // 2
    radius = 185
    
    mask_img = Image.new("L", (canvas_size, canvas_size), 0)
    draw_mask = ImageDraw.Draw(mask_img)
    draw_mask.rounded_rectangle([inset, inset, inset + icon_size, inset + icon_size], radius=radius, fill=255)
    
    shadow_img = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    draw_shadow = ImageDraw.Draw(shadow_img)
    draw_shadow.rounded_rectangle([inset, inset + 14, inset + icon_size, inset + icon_size + 14], radius=radius, fill=(0, 0, 0, 48))
    shadow_blurred = shadow_img.filter(ImageFilter.GaussianBlur(radius=20))
    
    surface = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    draw_surface = ImageDraw.Draw(surface)
    for y in range(inset, inset + icon_size):
        ratio = (y - inset) / float(icon_size)
        val = int(255 - ratio * 8)
        draw_surface.line([(inset, y), (inset + icon_size, y)], fill=(val, val, val, 255))
    
    draw_surface.rounded_rectangle([inset, inset, inset + icon_size, inset + icon_size], radius=radius, outline=(0, 0, 0, 22), width=2)
    
    base = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    base.paste(shadow_blurred, (0, 0), shadow_blurred)
    base.paste(surface, (0, 0), mask_img)
    
    emblem_scale = 1.28
    target_w = int(emblem_img.width * emblem_scale)
    target_h = int(emblem_img.height * emblem_scale)
    emblem_resized = emblem_img.resize((target_w, target_h), Image.Resampling.LANCZOS)
    
    pos_x = (canvas_size - target_w) // 2
    pos_y = (canvas_size - target_h) // 2 - 4
    base.paste(emblem_resized, (pos_x, pos_y), emblem_resized)
    
    res_dir = os.path.join(root_dir, "Resources")
    preview_path = os.path.join(res_dir, "AppIcon.png")
    base.save(preview_path, "PNG")
    print(f"Generated: {preview_path}")
    
    iconset_dir = "/tmp/Yeoman.iconset"
    if os.path.exists(iconset_dir):
        shutil.rmtree(iconset_dir)
    os.makedirs(iconset_dir)
    
    specs = [
        ("icon_16x16.png", 16),
        ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32),
        ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128),
        ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256),
        ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512),
        ("icon_512x512@2x.png", 1024),
    ]
    
    for filename, size in specs:
        resized = base.resize((size, size), Image.Resampling.LANCZOS)
        resized.save(os.path.join(iconset_dir, filename), "PNG")
        
    icns_path = os.path.join(res_dir, "AppIcon.icns")
    ret = subprocess.run(["iconutil", "-c", "icns", iconset_dir, "-o", icns_path])
    if ret.returncode == 0:
        print(f"Generated: {icns_path}")
    else:
        print(f"iconutil failed with code {ret.returncode}")

if __name__ == "__main__":
    generate()
