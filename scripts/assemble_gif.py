# /// script
# requires-python = ">=3.10"
# dependencies = ["pillow>=10"]
# ///
"""Assemble the frames left by 61_readme_gif_spex.exs into a gif.

    uv run scripts/assemble_gif.py FRAMES_DIR OUT.gif [--width 960]

Without --width the frames keep their native size, which is the sharp option
and, thanks to the shared palette and per-frame deltas, not a large one.

Frames are named fNNNNN_<ms>.png; the ms is used for real per-frame timing.
Consecutive identical frames are merged, a single palette is shared by every
frame so Pillow can write only the changed region of each one, and the last
frame is held for a moment before the loop.
"""
import re
import sys
from pathlib import Path

from PIL import Image

args = sys.argv[1:]
width = None
if "--width" in args:
    i = args.index("--width")
    width = int(args[i + 1])
    del args[i : i + 2]
frames_dir, out = Path(args[0]), Path(args[1])

pat = re.compile(r"f(\d+)_(\d+)\.png$")
files = sorted(
    ((int(m.group(1)), int(m.group(2)), p) for p in frames_dir.iterdir() if (m := pat.match(p.name))),
)
if not files:
    sys.exit(f"no frames in {frames_dir}")

frames, times = [], []
for _, ms, p in files:
    try:
        im = Image.open(p)
        im.load()
    except Exception:  # a frame the driver had not finished writing
        continue
    im = im.convert("RGB")
    if width and width != im.width:
        im = im.resize((width, round(im.height * width / im.width)), Image.LANCZOS)
    if frames and im.tobytes() == frames[-1].tobytes():
        continue  # nothing changed: the previous frame just lasts longer
    frames.append(im)
    times.append(ms)

durations = [max(20, b - a) for a, b in zip(times, times[1:])] + [2500]

# One palette for the whole gif, sampled from every ~8th frame.
sample = frames[::8] or frames
strip = Image.new("RGB", (sample[0].width, sample[0].height * len(sample)))
for k, f in enumerate(sample):
    strip.paste(f, (0, k * f.height))
palette = strip.quantize(colors=255, method=Image.Quantize.MEDIANCUT)

quantized = [f.quantize(palette=palette, dither=Image.Dither.NONE) for f in frames]
quantized[0].save(
    out,
    save_all=True,
    append_images=quantized[1:],
    duration=durations,
    loop=0,
    optimize=True,
    disposal=1,
)
print(f"{out}: {len(quantized)} frames, {sum(durations)/1000:.1f}s, {out.stat().st_size/1e6:.1f} MB, {frames[0].width}x{frames[0].height}")
