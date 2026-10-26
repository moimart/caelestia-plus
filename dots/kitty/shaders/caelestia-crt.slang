#language slang 2026
// CRT for kitty (custom shader, kitty >= 0.49)
//
// Port of ghostty/shaders/amber-crt.glsl: scanlines, slight barrel curvature,
// bloom and a vignette, text keeps its own colours. A refresh band rolls down
// the window; the lines it passes tear sideways, split their colour channels
// and flicker, and every few seconds a pass glitches much harder.
//
// The band is tinted with the live theme colour kitty hands the shader (the
// cursor colour, falling back to the foreground), so it follows the Caelestia
// scheme instead of being a fixed hue.
//
// Note: kitty's colours here are LINEAR RGB, so the bloom floor is a linear
// value, not the sRGB one used in the GLSL versions.
// UV origin is bottom-left, hence the flipped band direction.

import kitty_custom_shader_types;

// ---- Tunables -------------------------------------------------------------

// Band tint comes from the theme at runtime (see band_tint below).
// Set this to a colour in LINEAR RGB to override, or leave negative for theme.
static const float3 BAND_TINT_OVERRIDE = float3(-1.0f);
static const float  CURVATURE      = 0.035f; // barrel distortion, 0 = flat
static const float  SCANLINE_PX    = 3.0f;   // scanline period in pixels
static const float  SCANLINE_DEPTH = 0.25f;  // 0 = none, 1 = black gaps (linear, so lower than the GLSL 0.35)
static const float  BLOOM          = 0.55f;  // glow around lit text
static const float  BLOOM_FLOOR    = 0.03f;  // only pixels brighter than this glow (linear)
static const float  VIGNETTE       = 0.35f;
static const float  NOISE          = 0.01f;  // static grain (linear, so lower than the GLSL 0.02)

static const float  BAND_PERIOD    = 6.0f;   // seconds for the band to cross the window
static const float  BAND_HEIGHT    = 0.045f; // band thickness (fraction of window)
static const float  BAND_GLOW      = 0.22f;  // brightness boost inside the band
static const float  TEAR_PX        = 6.0f;   // horizontal tear inside the band
static const float  CHROMA_PX      = 2.5f;   // channel split inside the band
static const float  BURST_EVERY    = 5.0f;   // seconds between chances of a hard glitch

// d.timestamp counts from when THIS kitty process started, so windows in
// different processes would animate out of phase. bin/kitty-crt overrides this
// (via `var float TIME_OFFSET` in a generated pipeline) with
// wall_clock_seconds mod CYCLE at launch, which puts every process on the same
// wall-clock phase. The CYCLE in that script must stay a common multiple of
// BAND_PERIOD and BURST_EVERY, so the animation does not jump when it wraps.
static const float  TIME_OFFSET    = 0.0f;   // seconds, set at launch

// ---- Helpers --------------------------------------------------------------

float
crt_hash11(float p) {
    p = frac(p * 0.1031f);
    p *= p + 33.33f;
    p *= p + p;
    return frac(p);
}

float
crt_hash21(float2 p) {
    float3 p3 = frac(float3(p.x, p.y, p.x) * 0.1031f);
    p3 += dot(p3, p3.yzx + 33.33f);
    return frac((p3.x + p3.y) * p3.z);
}

float
crt_luma(float3 c) {
    return dot(c, float3(0.2126f, 0.7152f, 0.0722f)); // linear-light luminance
}

// Theme colour for the refresh band: the cursor colour (the scheme's accent),
// falling back to the foreground when no active window was rendered this frame.
float3
crt_band_tint(KittyCustomShaderData d) {
    if (BAND_TINT_OVERRIDE.r >= 0.0f) return BAND_TINT_OVERRIDE;
    float3 c = d.cursor_color.rgb;
    if (dot(c, float3(1.0f)) <= 0.0001f) c = d.foreground.rgb;
    return c;
}

float2
crt_curve(float2 uv) {
    uv = uv * 2.0f - 1.0f;
    float2 offset = abs(float2(uv.y, uv.x)) * CURVATURE;
    uv += uv * offset * offset * 4.0f;
    return uv * 0.5f + 0.5f;
}

// ---- Main -----------------------------------------------------------------

public float4
fragment_main(float4 color, KittyTextures t, KittyCustomShaderData d) {
    // Size of the viewport this group renders to, in pixels
    float2 vp = float2(d.viewport_size_pixels) * float2(t.viewport.z, t.viewport.w);
    float2 px = 1.0f / vp;

    float2 uv = crt_curve(t.pos);

    // Outside the curved glass: let the desktop show through
    if (uv.x < 0.0f || uv.x > 1.0f || uv.y < 0.0f || uv.y > 1.0f) return float4(0.0f);

    float tm = d.timestamp + TIME_OFFSET;

    // Rolling band, top to bottom (UV origin is bottom-left, so count down)
    float bandY = 1.0f - frac(tm / BAND_PERIOD);
    float dist = abs(uv.y - bandY);
    dist = min(dist, 1.0f - dist); // wrap so the band enters smoothly
    float band = exp(-pow(dist / BAND_HEIGHT, 2.0f));

    // Hard glitch: some bursts are much stronger, lasting ~0.35s
    float burstSlot = floor(tm / BURST_EVERY);
    float burstPhase = frac(tm / BURST_EVERY) * BURST_EVERY;
    float burst = step(0.55f, crt_hash11(burstSlot + 7.0f)) * step(burstPhase, 0.35f);
    float glitch = band * (1.0f + burst * 4.0f);

    // Horizontal tear: jitter each (coarse) line, re-rolled ~30 times a second
    float line = floor(uv.y * vp.y / 2.0f);
    float frame = floor(tm * 30.0f);
    float jitter = crt_hash21(float2(line, frame)) - 0.5f;
    float blockJitter = crt_hash21(float2(floor(uv.y * 24.0f), frame)) - 0.5f; // chunkier slices
    uv.x += (jitter * 0.6f + blockJitter) * TEAR_PX * glitch * px.x;

    // Channel split (only visible inside the band)
    float split = CHROMA_PX * glitch * px.x;
    float4 mid = t.backbuffer.Sample(uv);
    float r = t.backbuffer.Sample(uv + float2(split, 0.0f)).r;
    float b = t.backbuffer.Sample(uv - float2(split, 0.0f)).b;
    float3 src = float3(r, mid.g, b);
    float a = mid.a;

    // Bloom: cheap 8-tap blur, in the text's own colours
    float3 blur = float3(0.0f);
    blur += t.backbuffer.Sample(uv + float2( 2.0f,  0.0f) * px).rgb;
    blur += t.backbuffer.Sample(uv + float2(-2.0f,  0.0f) * px).rgb;
    blur += t.backbuffer.Sample(uv + float2( 0.0f,  2.0f) * px).rgb;
    blur += t.backbuffer.Sample(uv + float2( 0.0f, -2.0f) * px).rgb;
    blur += t.backbuffer.Sample(uv + float2( 3.0f,  3.0f) * px).rgb;
    blur += t.backbuffer.Sample(uv + float2(-3.0f,  3.0f) * px).rgb;
    blur += t.backbuffer.Sample(uv + float2( 3.0f, -3.0f) * px).rgb;
    blur += t.backbuffer.Sample(uv + float2(-3.0f, -3.0f) * px).rgb;
    blur = max(blur / 8.0f - BLOOM_FLOOR, 0.0f);

    float3 col = src + blur * BLOOM * 0.5f;

    // Brighter band, plus a flicker while glitching
    float flicker = 1.0f + (crt_hash11(frame) - 0.5f) * 0.25f * glitch;
    col *= (1.0f + band * BAND_GLOW) * flicker;
    col += crt_band_tint(d) * band * 0.03f * a;

    // Scanlines (in viewport pixels, so they stay put while the band moves)
    float scan = 0.5f + 0.5f * cos(t.pos.y * vp.y * 6.2831853f / SCANLINE_PX);
    col *= 1.0f - SCANLINE_DEPTH * scan;

    // Global slow flicker and static
    col *= 0.97f + 0.03f * sin(tm * 110.0f);
    col += (crt_hash21(t.pos * vp + frac(tm) * 100.0f) - 0.5f) * NOISE * a;

    // Vignette
    float2 v = uv * (1.0f - uv);
    col *= lerp(1.0f, pow(max(v.x * v.y * 16.0f, 0.0f), 0.25f), VIGNETTE);

    return float4(max(col, 0.0f), a);
}
