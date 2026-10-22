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

    canvas_size = 1024
    icon_size = 824
    inset = (canvas_size - icon_size) // 2
    radius = 185

    # 1. Base squircle canvas with subtle macOS drop shadow
    mask_img = Image.new("L", (canvas_size, canvas_size), 0)
    draw_mask = ImageDraw.Draw(mask_img)
    draw_mask.rounded_rectangle([inset, inset, inset + icon_size, inset + icon_size], radius=radius, fill=255)

    shadow_img = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    draw_shadow = ImageDraw.Draw(shadow_img)
    draw_shadow.rounded_rectangle([inset, inset + 14, inset + icon_size, inset + icon_size + 14], radius=radius, fill=(0, 0, 0, 42))
    shadow_blurred = shadow_img.filter(ImageFilter.GaussianBlur(radius=20))

    # Squircle surface: Pure clean white (#FFFFFF) like Brave Browser and Apple System icons (no extra grey border)
    surface = Image.new("RGBA", (canvas_size, canvas_size), (255, 255, 255, 255))

    base = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    base.paste(shadow_blurred, (0, 0), shadow_blurred)
    base.paste(surface, (0, 0), mask_img)

    # 2. Extract emblem with high-precision alpha matting
    src_y = Image.open(src_path).convert("RGB")
    arr_y = np.array(src_y)
    diff_y = np.maximum(
        np.abs(arr_y[:, :, 0].astype(int) - arr_y[:, :, 1].astype(int)),
        np.abs(arr_y[:, :, 1].astype(int) - arr_y[:, :, 2].astype(int))
    )
    is_emblem = (diff_y > 25) | ((arr_y[:, :, 0] < 80) & (arr_y[:, :, 1] < 80) & (arr_y[:, :, 2] < 80))
    is_emblem[:200, :] = False
    is_emblem[800:, :] = False
    is_emblem[:, :200] = False
    is_emblem[:, 800:] = False

    rows = np.any(is_emblem, axis=1)
    cols = np.any(is_emblem, axis=0)
    ymin, ymax = np.where(rows)[0][[0, -1]]
    xmin, xmax = np.where(cols)[0][[0, -1]]

    crop_y = src_y.crop((xmin - 4, ymin - 4, xmax + 4, ymax + 4))
    crop_arr = np.array(crop_y).astype(float)
    diff = 255.0 - crop_arr
    alpha = np.max(diff, axis=2) / 255.0
    alpha = np.clip((alpha - 0.03) / 0.94, 0.0, 1.0)
    fg = np.zeros_like(crop_arr)
    mask = alpha > 0.01
    for c in range(3):
        fg[mask, c] = np.clip((crop_arr[mask, c] - (1 - alpha[mask]) * 255.0) / alpha[mask], 0, 255)
    rgba_y = np.dstack([fg, alpha * 255.0]).astype(np.uint8)
    emblem_y = Image.fromarray(rgba_y, mode="RGBA")

    # 3. Position and scale emblem
    scale = 1.25
    target_w, target_h = int(emblem_y.width * scale), int(emblem_y.height * scale)
    resized_y = emblem_y.resize((target_w, target_h), Image.Resampling.LANCZOS)
    pos_x = (canvas_size - target_w) // 2
    pos_y = (canvas_size - target_h) // 2 - 8
    base.paste(resized_y, (pos_x, pos_y), resized_y)

    res_dir = os.path.join(root_dir, "Resources")
    preview_path = os.path.join(res_dir, "AppIcon.png")
    base.save(preview_path, "PNG")
    print(f"Generated: {preview_path}")

    # 4. Generate multi-resolution .iconset and compile .icns
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
