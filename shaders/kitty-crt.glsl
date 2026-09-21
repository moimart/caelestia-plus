// CRT look for kitty windows (Hypr-DarkWindow custom shader).
//
// Port of ~/code/caelestia/ghostty/shaders/amber-crt.glsl: scanlines, slight
// barrel curvature, bloom and a vignette, text keeps its own colours. An
// amber refresh band rolls down the window; the lines it passes tear
// sideways, split their colour channels and flicker, and every few seconds
// a pass turns into a much harder glitch.
//
// Runs inside Hyprland's fragment shader (GLSL ES 3.0). Colours are
// premultiplied alpha, so kitty's own background_opacity is kept as is.
// x_PixelPos / x_WindowSize are window pixels with (0,0) at the top left.

// ---- Tunables -------------------------------------------------------------

const vec3  CRT_AMBER          = vec3(1.00, 0.69, 0.10); // refresh band tint
const float CRT_CURVATURE      = 0.035; // barrel distortion, 0 = flat
const float CRT_SCANLINE_PX    = 3.0;   // scanline period in pixels
const float CRT_SCANLINE_DEPTH = 0.35;  // 0 = no scanlines, 1 = black gaps
const float CRT_BLOOM          = 0.55;  // glow around lit text
const float CRT_BLOOM_FLOOR    = 0.20;  // only pixels brighter than this glow
const float CRT_VIGNETTE       = 0.35;
const float CRT_NOISE          = 0.02;  // static grain

const float CRT_BAND_PERIOD    = 6.0;   // seconds for the band to cross the window
const float CRT_BAND_HEIGHT    = 0.045; // band thickness (fraction of window)
const float CRT_BAND_GLOW      = 0.22;  // brightness boost inside the band
const float CRT_TEAR_PX        = 6.0;   // horizontal tear inside the band
const float CRT_CHROMA_PX      = 2.5;   // channel split inside the band
const float CRT_BURST_EVERY    = 5.0;   // seconds between chances of a hard glitch

// ---- Helpers --------------------------------------------------------------

float crt_hash11(float p) {
    p = fract(p * 0.1031);
    p *= p + 33.33;
    p *= p + p;
    return fract(p);
}

float crt_hash21(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float crt_luma(vec3 c) {
    return dot(c, vec3(0.299, 0.587, 0.114));
}

vec2 crt_curve(vec2 uv) {
    uv = uv * 2.0 - 1.0;
    vec2 offset = abs(uv.yx) * CRT_CURVATURE;
    uv += uv * offset * offset * 4.0;
    return uv * 0.5 + 0.5;
}

// ---- Main -----------------------------------------------------------------

void windowShader(inout vec4 color) {
    vec2 size = x_WindowSize;
    vec2 uv = crt_curve(x_PixelPos / size);

    // Outside the curved glass: let the desktop show through
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
        color = vec4(0.0);
        return;
    }

    float t = x_Time;
    vec2 px = 1.0 / size;

    // Rolling band, top to bottom
    float bandY = fract(t / CRT_BAND_PERIOD);
    float dist = abs(uv.y - bandY);
    dist = min(dist, 1.0 - dist); // wrap so the band enters smoothly
    float band = exp(-pow(dist / CRT_BAND_HEIGHT, 2.0));

    // Hard glitch: some bursts are much stronger, lasting ~0.35s
    float burstSlot = floor(t / CRT_BURST_EVERY);
    float burstPhase = fract(t / CRT_BURST_EVERY) * CRT_BURST_EVERY;
    float burst = step(0.55, crt_hash11(burstSlot + 7.0)) * step(burstPhase, 0.35);
    float glitch = band * (1.0 + burst * 4.0);

    // Horizontal tear: jitter each (coarse) line, re-rolled ~30 times a second
    float line = floor(uv.y * size.y / 2.0);
    float frame = floor(t * 30.0);
    float jitter = crt_hash21(vec2(line, frame)) - 0.5;
    float blockJitter = crt_hash21(vec2(floor(uv.y * 24.0), frame)) - 0.5; // chunkier slices
    uv.x += (jitter * 0.6 + blockJitter) * CRT_TEAR_PX * glitch * px.x;

    // Channel split (only visible inside the band)
    float split = CRT_CHROMA_PX * glitch * px.x;
    vec4 mid = x_Texture(uv);
    float r = x_Texture(uv + vec2(split, 0.0)).r;
    float b = x_Texture(uv - vec2(split, 0.0)).b;
    vec3 src = vec3(r, mid.g, b);
    float a = mid.a;

    // Bloom: cheap 8-tap blur, in the text's own colours
    vec3 blur = vec3(0.0);
    blur += x_Texture(uv + vec2( 2.0,  0.0) * px).rgb;
    blur += x_Texture(uv + vec2(-2.0,  0.0) * px).rgb;
    blur += x_Texture(uv + vec2( 0.0,  2.0) * px).rgb;
    blur += x_Texture(uv + vec2( 0.0, -2.0) * px).rgb;
    blur += x_Texture(uv + vec2( 3.0,  3.0) * px).rgb;
    blur += x_Texture(uv + vec2(-3.0,  3.0) * px).rgb;
    blur += x_Texture(uv + vec2( 3.0, -3.0) * px).rgb;
    blur += x_Texture(uv + vec2(-3.0, -3.0) * px).rgb;
    blur = max(blur / 8.0 - CRT_BLOOM_FLOOR, 0.0);

    vec3 col = src + blur * CRT_BLOOM * 0.5;

    // Brighter band, plus a flicker while glitching
    float flicker = 1.0 + (crt_hash11(frame) - 0.5) * 0.25 * glitch;
    col *= (1.0 + band * CRT_BAND_GLOW) * flicker;
    col += CRT_AMBER * band * 0.03 * a;

    // Scanlines (in window pixels, so they stay put while the band moves)
    float scan = 0.5 + 0.5 * cos(x_PixelPos.y * 6.2831853 / CRT_SCANLINE_PX);
    col *= 1.0 - CRT_SCANLINE_DEPTH * scan;

    // Global slow flicker and static
    col *= 0.97 + 0.03 * sin(t * 110.0);
    col += (crt_hash21(x_PixelPos + fract(t) * 100.0) - 0.5) * CRT_NOISE * a;

    // Vignette
    vec2 v = uv * (1.0 - uv);
    col *= mix(1.0, pow(v.x * v.y * 16.0, 0.25), CRT_VIGNETTE);

    color = vec4(max(col, 0.0), a);
}
