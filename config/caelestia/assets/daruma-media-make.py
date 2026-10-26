"""Media-panel daruma: dances to the beat while music plays.

The dashboard plays its media GIF at speed bpm / mediaGifSpeedAdjustment (300),
so every 200 ms of animation is one beat (the stock bongocat is 2 x 100 ms).
This loop is 16 beats: rocks on its base with a hop on each beat, winks (the
winking eye opens briefly) around beat 6, then turns a full 360 degrees on its
vertical axis over the last four beats (face slides round, the red back shows)
and ends facing front where the loop starts.

make.py <rendered-png> <out-dir>
The doll rolls rather than pivots: rotation is about the centre of the base's
curvature, with the matching horizontal travel (arc length) of a rolling contact.
"""
import math, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

src, out = sys.argv[1], sys.argv[2]
SS = 4                      # supersampling
SIZE = 256                  # output canvas
DOLL = 168                  # doll width in the output (room to spin)
BEATS, PER_BEAT = 16, 10   # 10 frames per 200 ms beat
FRAMES, MS = BEATS * PER_BEAT, 20
AMP = math.radians(16)

source = Image.open(src).convert("RGBA")   # rendered at 1024 px wide
EYE_C, EYE_R = (712, 392), 134             # the open (painted) eye in the 1024 render
FACE = source.getpixel((EYE_C[0], EYE_C[1] + EYE_R + 14))
# The winking eye's stroke, as a mask (by darkness) for erasing it while it's open.
WINK_BOX = (150, 292, 440, 420)
_ink = source.crop(WINK_BOX).convert("L").point(lambda v: 255 - v)
w = DOLL * SS

def eye_state(t):
    """How open the winking eye is: 0 = its usual wink, 1 = open. It opens
    once, around beat 6."""
    d = abs(t - 5.5 / 16) / 0.035
    return 0.0 if d >= 1 else 1 - d ** 1.5

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

doll = doll_frame(0.0)
cw = ch = SIZE * SS
base_y = ch - 22 * SS        # where the base touches the ground
radius = w * 0.47            # curvature of the base ~ half the width


HOP = 10 * SS          # hop height per beat
TURN_HOP = 12 * SS     # small hop during the turn
ROCK = math.radians(9)

def pose(i):
    """(rock angle, turn angle about the vertical axis, lift) for frame i."""
    beat, phase = divmod(i / PER_BEAT, 1)
    beat = int(beat)
    if beat < 12:
        # tip left/right on alternate beats, easing through upright, small hop on the beat
        side = 1 if beat % 2 == 0 else -1
        return side * ROCK * math.sin(math.pi * phase), 0.0, HOP * math.sin(math.pi * phase) ** 2
    u = ((beat - 12) + phase) / 4               # 0..1 over the last four beats
    ease = u * u * (3 - 2 * u)                  # smoothstep: ease in and out
    return 0.0, 2 * math.pi * ease, TURN_HOP * math.sin(math.pi * u)

def split_layers(doll):
    """Body (outline + red, with the red filled in behind the design) and the
    design (face and gold marks) that turns around it."""
    a = np.asarray(doll).astype(np.float32)
    r, g, b, al = a[..., 0], a[..., 1], a[..., 2], a[..., 3]
    inside = np.asarray(Image.fromarray((al > 128).astype(np.uint8) * 255).filter(ImageFilter.MinFilter(31))) > 0
    red = (r > 120) & (g < 90) & (b < 90) & inside
    design = np.asarray(Image.fromarray((inside & ~red).astype(np.uint8) * 255).filter(ImageFilter.MaxFilter(9))) > 0
    design &= inside
    keep = red & ~design                                   # red we trust
    # normalised blur: spread the surrounding red smoothly into the design area
    def blur(x, rad=28):
        # three box-blur passes per axis (about a Gaussian), edge-padded
        x = x.astype(np.float32)
        for axis in (0, 1):
            for _ in range(3):
                pad = np.pad(x, [(rad + 1, rad) if ax == axis else (0, 0) for ax in (0, 1)], mode="edge")
                c = np.cumsum(pad, axis=axis)
                hi = np.take(c, range(2 * rad + 1, c.shape[axis]), axis=axis)
                lo = np.take(c, range(0, c.shape[axis] - 2 * rad - 1), axis=axis)
                x = (hi - lo) / (2 * rad + 1)
        return x
    weight = blur(keep.astype(np.float32), 110)
    # fallback where the blur can't reach: the mean red of that row (or the image)
    rows = keep.sum(axis=1, keepdims=True)
    body = a.copy()
    for c in range(3):
        overall = a[..., c][keep].mean()
        row_mean = np.where(rows > 0, (a[..., c] * keep).sum(axis=1, keepdims=True) / np.maximum(rows, 1), overall)
        spread = blur(a[..., c] * keep, 110) / np.maximum(weight, 1e-6)
        t = np.clip(weight / 0.05, 0, 1)                   # blend to the fallback where weight is tiny
        fill = t * spread + (1 - t) * np.broadcast_to(row_mean, spread.shape)
        body[..., c] = np.where(design, fill, a[..., c])
    mask = Image.fromarray(design.astype(np.uint8) * 255).filter(ImageFilter.GaussianBlur(2))
    dec = doll.copy()
    dec.putalpha(mask)
    return Image.fromarray(np.clip(body, 0, 255).astype(np.uint8)), dec, Image.fromarray(inside.astype(np.uint8) * 255)

BODY, DESIGN, INSIDE = split_layers(doll_frame(0.0))
R_TURN = w * 0.42      # how far the design travels round the body

def turned(theta):
    """The doll turned by theta about its vertical axis."""
    c, s_ = math.cos(theta), math.sin(theta)
    img = BODY.copy()
    if c > 0.03:
        dw = max(1, round(w * c))
        dec = DESIGN.resize((dw, DESIGN.height), Image.LANCZOS)
        shade = 0.55 + 0.45 * c                          # darker as it turns away
        rgb = dec.convert("RGB").point(lambda v: round(v * shade))
        rgb.putalpha(dec.getchannel("A"))
        dec = rgb
        layer = Image.new("RGBA", BODY.size, (0, 0, 0, 0))
        layer.alpha_composite(dec, (round(w / 2 + R_TURN * s_ - dw / 2), 0))
        clip = Image.composite(layer.getchannel("A"), Image.new("L", BODY.size, 0), INSIDE)
        layer.putalpha(clip)
        img.alpha_composite(layer)
    return img

cw = ch = SIZE * SS
base_y = ch - 22 * SS
radius = w * 0.47

frames = []
for i in range(FRAMES):
    rock, turn, lift = pose(i)
    doll = turned(turn) if turn else doll_frame(eye_state(i / FRAMES))
    canvas = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    # rock on the rounded base (rolling contact), raised by the hop
    cx = cw / 2 + radius * rock
    cy = base_y - radius - lift
    canvas.alpha_composite(doll, (round(cx - w / 2), round(base_y - lift - doll.height)))
    if rock:
        canvas = canvas.rotate(math.degrees(-rock), resample=Image.BICUBIC, center=(cx, cy))
    frames.append(canvas.resize((SIZE, SIZE), Image.LANCZOS))

frames[0].save(f"{out}/daruma-media.webp", save_all=True, append_images=frames[1:], duration=MS, loop=0,
               lossless=False, quality=86, method=6)
sheet = Image.new("RGBA", (SIZE * 8, SIZE * 2), (30, 12, 8, 255))
for k, i in enumerate([0, 20, 55, 100, 120, 128, 134, 138, 142, 146, 150, 152, 154, 156, 158, 159]):
    if k < 16:
        sheet.alpha_composite(frames[i], ((k % 8) * SIZE, (k // 8) * SIZE))
sheet.save(f"{out}/sheet-media.png")
print("ok", len(frames), "frames,", FRAMES * MS, "ms =", BEATS, "beats")
