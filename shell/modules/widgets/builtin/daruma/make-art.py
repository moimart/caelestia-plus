#!/usr/bin/env python3
"""Builds the Daruma widget's two images from the daruma SVG.

    make-art.py <daruma.svg>      (needs rsvg-convert and Pillow)

daruma-open.png   the doll with its painted eye's pupil removed; the widget
                  draws the pupil itself so it can follow the pointer
daruma-closed.png the painted eye shut as well, drawn as the doll's own wink
                  stroke mirrored, for when it winks or rests

Geometry is in the 1024 px render; Daruma.qml uses the same values as
fractions of the image (EYE_C / 1024, ...).
"""
import subprocess, sys, tempfile
from PIL import Image, ImageDraw, ImageOps

SIZE = 640
EYE_C, PUPIL_R, RING_OUTER = (712, 392), 52, 136
WINK_BOX = (150, 292, 440, 420)  # the doll's winking eye stroke

svg = sys.argv[1]
with tempfile.NamedTemporaryFile(suffix=".png") as tmp:
    subprocess.run(["rsvg-convert", "-w", "1024", svg, "-o", tmp.name], check=True)
    src = Image.open(tmp.name).convert("RGBA")
white = (255, 255, 255, 255)

# Open: paint the pupil out, leaving the ring
opened = src.copy()
cx, cy = EYE_C
ImageDraw.Draw(opened).ellipse((cx - PUPIL_R, cy - PUPIL_R, cx + PUPIL_R, cy + PUPIL_R), fill=white)

# Closed: clear the whole eye, then draw the wink stroke mirrored in its place
closed = src.copy()
ImageDraw.Draw(closed).ellipse((cx - RING_OUTER, cy - RING_OUTER, cx + RING_OUTER, cy + RING_OUTER), fill=white)
stroke = ImageOps.mirror(src.crop(WINK_BOX))
mask = ImageOps.invert(stroke.convert("L")).point(lambda v: 255 if v > 110 else v * 2)
w, h = stroke.size
closed.paste(stroke, (cx - w // 2, cy - h // 2 + 6), mask)

for name, img in (("daruma-open.png", opened), ("daruma-closed.png", closed)):
    img.resize((SIZE, SIZE), Image.LANCZOS).save(name, optimize=True)
    print("wrote", name)
