"""Normalize ImageGen atlases, share palette/scale, and package Godot frames.

Only deterministic asset preparation happens here. Artwork comes from imagegen.
Requires Pillow and the installed sprite-pipeline normalize script.
"""
from pathlib import Path
import argparse
import importlib.util
import json
from PIL import Image, ImageOps

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets/elf/v2"
QA = ROOT / "build/qa/elf_v2"
SIZE, HEIGHT, BASELINE = 128, 120, 124
DIRS = ("down", "left", "right", "up")


def content(image):
    alpha = image.getchannel("A").point(lambda value: 255 if value >= 128 else 0)
    return alpha.getbbox()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--pipeline", required=True, type=Path)
    args = parser.parse_args()
    spec = importlib.util.spec_from_file_location("sprite_pipeline", args.pipeline / "normalize_sprite_strip.py")
    pipeline = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(pipeline)
    QA.mkdir(parents=True, exist_ok=True)
    (ROOT / "build/.gdignore").touch()
    raw = {}
    for direction in ("down", "left", "up"):
        image = Image.open(ASSETS / f"walk_{direction}_source.png").convert("RGBA")
        assert image.size == (1536, 1024)
        # Reflow the generated 4x2 atlas to the pipeline's horizontal-strip layout.
        strip = Image.new("RGBA", (384 * 8, 512))
        for i in range(8):
            cell = image.crop(((i % 4) * 384, (i // 4) * 512, (i % 4 + 1) * 384, (i // 4 + 1) * 512))
            strip.paste(cell, (i * 384, 0))
        strip.save(QA / f"{direction}_strip.png")
        raw[direction] = [pipeline.crop_to_content(cell, 127) for cell in pipeline.split_strip(strip, 8)]
        assert all(cell is not None for cell in raw[direction]), "Every slot must contain a sprite"
    # Calibrate directions to the seed height once, never fit individual frames.
    max_width, max_height = pipeline.max_content_size([f for frames in raw.values() for f in frames])
    print(f"Source max {max_width}x{max_height}; each direction calibrated to {HEIGHT}px with one scale for all eight frames")
    frames = {}
    metrics = {}
    for direction, cells in raw.items():
        direction_height = max(cell.height for cell in cells)
        direction_scale = HEIGHT / direction_height
        frames[direction] = []
        metrics[direction] = []
        for i, cell in enumerate(cells):
            normalized = pipeline.compose_frame(cell, HEIGHT, direction_scale)
            # Anchor by the head, not swinging cape/ribbons. This avoids lateral jitter.
            box = content(normalized)
            mask = normalized.getchannel("A")
            head_rows = range(box[1] + 5, min(box[3], box[1] + 26))
            xs = [x for y in head_rows for x in range(HEIGHT) if mask.getpixel((x, y)) >= 128]
            head_center = sum(xs) / len(xs)
            target_x = 61 if direction == "left" else 64
            x_shift = round(target_x - head_center)
            result = Image.new("RGBA", (SIZE, SIZE))
            result.paste(normalized, (x_shift, BASELINE - HEIGHT))
            frames[direction].append(result)
            metrics[direction].append({"frame": i, "source_size": list(cell.size), "strip_scale": direction_scale, "bounds": content(result), "head_x": round(head_center + x_shift, 2)})
    frames["right"] = [ImageOps.mirror(f) for f in frames["left"]]

    # A common palette eliminates bright fringe pixels and per-frame color flicker.
    seed = Image.open(ASSETS / "seed_source.png").convert("RGBA")
    seed = seed.crop(content(seed))
    seed_scale = HEIGHT / seed.height
    seed = seed.resize((round(seed.width * seed_scale), HEIGHT), Image.Resampling.NEAREST)
    idle_down = Image.new("RGBA", (SIZE, SIZE))
    idle_down.paste(seed, ((SIZE - seed.width) // 2, BASELINE - HEIGHT))
    swatches = Image.new("RGBA", (SIZE * 9, SIZE * 4))
    for row, direction in enumerate(DIRS):
        for col, frame in enumerate(frames[direction]):
            swatches.paste(frame, (col * SIZE, row * SIZE))
    swatches.paste(idle_down, (SIZE * 8, 0))
    palette = swatches.quantize(colors=48, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.NONE)
    palette_rgb = Image.new("P", (1, 1))
    palette_rgb.putpalette(palette.getpalette())

    def clean(image):
        alpha = image.getchannel("A").point(lambda value: 255 if value >= 128 else 0)
        result = image.convert("RGB").quantize(palette=palette_rgb, dither=Image.Dither.NONE).convert("RGBA")
        result.putalpha(alpha)
        return result

    atlas = Image.new("RGBA", (SIZE * 9, SIZE * 4))
    all_frames = []
    for row, direction in enumerate(DIRS):
        frame_dir = QA / direction
        frame_dir.mkdir(exist_ok=True)
        for col, frame in enumerate(frames[direction]):
            frame = clean(frame)
            frames[direction][col] = frame
            atlas.paste(frame, (col * SIZE, row * SIZE))
            frame.save(frame_dir / f"{col+1:02d}.png")
            all_frames.append(frame)
        # Separate neutral front idle; side/back use a planted-foot passing pose.
        idle = clean(idle_down) if direction == "down" else frames[direction][1]
        atlas.paste(idle, (SIZE * 8, row * SIZE))
        idle.save(ASSETS / f"idle_{direction}.png")
    atlas.save(ASSETS / "elf_atlas.png")

    resources = ['[gd_resource type="SpriteFrames" load_steps=38 format=3]', '', '[ext_resource type="Texture2D" path="res://assets/elf/v2/elf_atlas.png" id="1"]']
    for row, direction in enumerate(DIRS):
        for col in range(9):
            resources += ['', f'[sub_resource type="AtlasTexture" id="{direction}_{col}"]', 'atlas = ExtResource("1")', f'region = Rect2({col*SIZE}, {row*SIZE}, {SIZE}, {SIZE})']
    animations = []
    for direction in DIRS:
        for moving in (False, True):
            indices = range(8) if moving else [8]
            entries = ', '.join('{"duration": 1.0, "texture": SubResource("%s_%d")}' % (direction, index) for index in indices)
            animations.append('{"frames": [%s], "loop": true, "name": &"%s_%s", "speed": 14.0}' % (entries, "walk" if moving else "idle", direction))
    resources += ['', '[resource]', 'animations = [' + ',\n'.join(animations) + ']']
    (ASSETS / "elf_frames.tres").write_text('\n'.join(resources) + '\n', encoding='utf-8')
    (QA / "metrics.json").write_text(json.dumps({"scale_policy": "shared across each eight-frame direction", "native_frame": SIZE, "feet_baseline": BASELINE, "directions": metrics}, indent=2), encoding='utf-8')

    # Animated contact preview: all four directions displayed simultaneously.
    previews = []
    for i in range(8):
        preview = Image.new("RGBA", (SIZE * 4, SIZE), "#233d39")
        for col, direction in enumerate(DIRS):
            preview.alpha_composite(frames[direction][i], (col * SIZE, 0))
        previews.append(preview.resize((1024, 256), Image.Resampling.NEAREST).convert("RGB"))
    previews[0].save(QA / "walk_cycle.gif", save_all=True, append_images=previews[1:], duration=80, loop=0, disposal=2)
    print("Built 1152x512 atlas, 32 walk poses + four idle poses, unified 48-color palette.")


if __name__ == "__main__":
    main()
