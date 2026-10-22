"""Animate a daruma: rocks on its rounded base after a nudge, settles, rests, repeats.

make.py <rendered-png> <out-dir>
The doll rolls rather than pivots: rotation is about the centre of the base's
curvature, with the matching horizontal travel (arc length) of a rolling contact.
"""
import math, sys
from PIL import Image, ImageDraw

src, out = sys.argv[1], sys.argv[2]
SS = 4                      # supersampling
SIZE = 256                  # output canvas
DOLL = 196                  # doll width in the output
FRAMES, MS = 60, 40         # 2.4 s loop
AMP = math.radians(16)

source = Image.open(src).convert("RGBA")   # rendered at 1024 px wide
EYE_C, EYE_R = (712, 392), 134             # the open (painted) eye in the 1024 render
FACE = source.getpixel((EYE_C[0], EYE_C[1] + EYE_R + 14))
# The winking (closed) eye on the other side, cut by darkness so only the stroke
# comes along, mirrored across the face's centre line.
WINK_BOX = (150, 292, 440, 420)
_wink = source.crop(WINK_BOX)
_ink = _wink.convert("L").point(lambda v: 255 - v)
WINK = Image.new("RGBA", _wink.size, (0, 0, 0, 0))
WINK.paste(_wink, (0, 0), _ink)
WINK = WINK.transpose(Image.FLIP_LEFT_RIGHT)
w = DOLL * SS

def eye_state(t):
    """1 = open, 0 = closed: one blink during the rest, centred at 88% of the loop."""
    d = abs(t - 0.88) / 0.05
    return 1.0 if d >= 1 else d ** 1.5

def doll_frame(openness):
    img = source.copy()
    if openness < 0.999:
        cx, cy = EYE_C
        box = (cx - EYE_R, cy - EYE_R, cx + EYE_R, cy + EYE_R)
        mask = Image.new("L", source.size, 0)
        ImageDraw.Draw(mask).ellipse(box, fill=255)
        eye = Image.new("RGBA", source.size, (0, 0, 0, 0))
        eye.paste(img, (0, 0), mask)
        eye = eye.crop(box)
        ImageDraw.Draw(img).ellipse(box, fill=FACE)          # cover the open eye
        h = max(1, round(2 * EYE_R * openness))
        if openness > 0.12:
            img.alpha_composite(eye.resize((2 * EYE_R, h), Image.LANCZOS), (cx - EYE_R, cy - h // 2))
        else:  # closed: his own wink, mirrored onto this side of the face
            img.alpha_composite(WINK, (source.width - WINK_BOX[2], WINK_BOX[1]))
    return img.resize((w, round(img.height * w / img.width)), Image.LANCZOS)

doll = doll_frame(1.0)
cw = ch = SIZE * SS
base_y = ch - 22 * SS        # where the base touches the ground
radius = w * 0.47            # curvature of the base ~ half the width

def angle(t):
    # nudge -> two decaying rocks, then rest for the last 30% of the loop
    if t > 0.78:
        return 0.0
    u = t / 0.78
    return AMP * math.exp(-3.2 * u) * math.sin(2 * math.pi * 2 * u) * (1 - u) ** 0.3

frames = []
for i in range(FRAMES):
    a = angle(i / FRAMES)
    # pivot = centre of base curvature, `radius` above the contact point
    cx = cw / 2 + radius * a          # rolling: contact moves by arc length
    cy = base_y - radius
    doll = doll_frame(eye_state(i / FRAMES))
    canvas = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    # place the doll so its bottom sits on base_y, centred on the pivot
    canvas.alpha_composite(doll, (round(cx - w / 2), round(base_y - doll.height)))
    rotated = canvas.rotate(math.degrees(-a), resample=Image.BICUBIC, center=(cx, cy))
    frames.append(rotated.resize((SIZE, SIZE), Image.LANCZOS))

frames[0].save(f"{out}/daruma.webp", save_all=True, append_images=frames[1:], duration=MS, loop=0,
               lossless=False, quality=92, method=6)
# GIF: 1-bit transparency, so threshold alpha
gif = []
for f in frames:
    alpha = f.getchannel("A").point(lambda v: 255 if v > 110 else 0)
    p = f.convert("RGB").quantize(colors=255, method=Image.MEDIANCUT)
    p.paste(255, mask=alpha.point(lambda v: 255 - v))
    gif.append(p)
gif[0].save(f"{out}/daruma.gif", save_all=True, append_images=gif[1:], duration=MS, loop=0, transparency=255, disposal=2)
# contact sheet for checking
sheet = Image.new("RGBA", (SIZE * 6, SIZE * 2), (30, 12, 8, 255))
for k, i in enumerate([0, 6, 12, 18, 24, 30, 48, 50, 51, 52, 53, 55]):
    sheet.alpha_composite(frames[i], ((k % 6) * SIZE, (k // 6) * SIZE))
sheet.save(f"{out}/sheet.png")
print("ok", len(frames), "frames")
