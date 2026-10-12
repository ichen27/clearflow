"""Assemble rendered documentation frames; requires Pillow in a tooling environment."""
from pathlib import Path
import shutil
import sys
from PIL import Image
source, destination = map(Path, sys.argv[1:])
destination.mkdir(parents=True, exist_ok=True)
frames = [Image.open(path).convert("RGB") for path in sorted(source.glob("frame-*.png"))]
if len(frames) != 48:
    raise SystemExit("Expected 48 documentation frames.")
frames[0].save(destination / "demo.gif", save_all=True, append_images=frames[1:], duration=150, loop=0, optimize=True)
shutil.copyfile(source / "screenshot.png", destination / "screenshot.png")
