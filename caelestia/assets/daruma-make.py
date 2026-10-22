"""Animate a daruma: rocks on its rounded base after a nudge, settles, then winks its
left eye during the rest; repeats.

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
# The winking eye's stroke, as a mask (by darkness) for erasing it while it's open.
WINK_BOX = (150, 292, 440, 420)
_ink = source.crop(WINK_BOX).convert("L").point(lambda v: 255 - v)
w = DOLL * SS

def eye_state(t):
    """How open the left eye is: 1 = open (most of the time), 0 = the wink.
    It winks once during the rest: closes, holds, reopens."""
    ease, hold, centre = 0.045, 0.06, 0.88
    d = abs(t - centre) - hold / 2
    if d <= 0:
        return 0.0
    return 1.0 if d >= ease else (d / ease) ** 0.7

# The painted eye, mirrored, is what the winking eye looks like open.
_cx, _cy = EYE_C
_box = (_cx - EYE_R, _cy - EYE_R, _cx + EYE_R, _cy + EYE_R)
_mask = Image.new("L", source.size, 0)
ImageDraw.Draw(_mask).ellipse(_box, fill=255)
_eye = Image.new("RGBA", source.size, (0, 0, 0, 0))
_eye.paste(source, (0, 0), _mask)
OPEN_EYE = _eye.crop(_box).transpose(Image.FLIP_LEFT_RIGHT)
LEFT_C = (source.width - _cx, _cy)          # mirrored across the face's centre line

def doll_frame(openness):
    img = source.copy()
    if openness > 0.12:
        # erase the wink stroke, then draw the eye opening (squashed vertically)
        ImageDraw.Draw(img).bitmap(WINK_BOX[:2], _ink, fill=FACE)
        h = max(1, round(2 * EYE_R * openness))
        img.alpha_composite(OPEN_EYE.resize((2 * EYE_R, h), Image.LANCZOS), (LEFT_C[0] - EYE_R, LEFT_C[1] - h // 2))
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
