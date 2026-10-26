// Amber CRT for Ghostty
//
// Scanlines, slight barrel curvature, bloom and a vignette over a faint
// amber glass. Text keeps its own colours. An amber refresh band rolls down
// the screen;
// the lines it passes over tear sideways, split their colour channels
// and flicker. Every few seconds the band has a much harder glitch.
//
// Needs `custom-shader-animation = always` in the Ghostty config, and
// `background-opacity` below 1 for OPACITY to have any effect.

// ---- Tunables -------------------------------------------------------------

const vec3  AMBER          = vec3(1.00, 0.69, 0.10); // refresh band tint (#ffb01a)
const vec3  AMBER_DARK     = vec3(0.0);   // extra glass tint behind the text (scheme bg is already amber)
const float CURVATURE      = 0.035; // barrel distortion, 0 = flat
const float SCANLINE_PX    = 3.0;   // scanline period in pixels
const float SCANLINE_DEPTH = 0.35;  // 0 = no scanlines, 1 = black gaps
const float BLOOM          = 0.55;  // glow around lit text
const float BLOOM_FLOOR    = 0.20;  // only pixels brighter than this glow, so the background stays dark
const float VIGNETTE       = 0.35;
const float NOISE          = 0.02;  // static grain
const float OPACITY        = 0.85;  // screen opacity where nothing is lit (kitty uses 0.85); text stays solid

const float BAND_PERIOD    = 6.0;   // seconds for the band to cross the screen
const float BAND_HEIGHT    = 0.045; // band thickness (fraction of screen)
const float BAND_GLOW      = 0.22;  // brightness boost inside the band
const float TEAR           = 0.006; // horizontal tear inside the band (uv units)
const float CHROMA         = 0.0025; // channel split inside the band
const float BURST_EVERY    = 5.0;   // seconds between chances of a hard glitch

// ---- Helpers --------------------------------------------------------------

float hash11(float p) {
    p = fract(p * 0.1031);
    p *= p + 33.33;
    p *= p + p;
    return fract(p);
}

float hash21(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float luma(vec3 c) {
    return dot(c, vec3(0.299, 0.587, 0.114));
}

vec2 curve(vec2 uv) {
    uv = uv * 2.0 - 1.0;
    vec2 offset = abs(uv.yx) * CURVATURE;
    uv += uv * offset * offset * 4.0;
    return uv * 0.5 + 0.5;
}

vec3 sampleRgb(vec2 uv) {
    return texture(iChannel0, uv).rgb;
}

// ---- Main -----------------------------------------------------------------

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 res = iResolution.xy;
    vec2 uv = curve(fragCoord / res);

    // Outside the curved glass: black bezel
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
        fragColor = vec4(0.0, 0.0, 0.0, OPACITY);
        return;
    }

    float t = iTime;

    // Rolling band, top to bottom (uv.y = 1 is the top)
    float bandY = 1.0 - fract(t / BAND_PERIOD);
    float dist = abs(uv.y - bandY);
    dist = min(dist, 1.0 - dist); // wrap so the band enters smoothly
    float band = exp(-pow(dist / BAND_HEIGHT, 2.0));

    // Hard glitch: some bursts are much stronger, lasting ~0.35s
    float burstSlot = floor(t / BURST_EVERY);
    float burstPhase = fract(t / BURST_EVERY) * BURST_EVERY;
    float burst = step(0.55, hash11(burstSlot + 7.0)) * step(burstPhase, 0.35);
    float glitch = band * (1.0 + burst * 4.0);

    // Horizontal tear: jitter each (coarse) line, re-rolled ~30 times a second
    float line = floor(uv.y * res.y / 2.0);
    float frame = floor(t * 30.0);
    float jitter = hash21(vec2(line, frame)) - 0.5;
    float blockJitter = hash21(vec2(floor(uv.y * 24.0), frame)) - 0.5; // chunkier slices
    float tear = (jitter * 0.6 + blockJitter) * TEAR * glitch;
    uv.x += tear;

    // Channel split (only visible inside the band)
    float split = CHROMA * glitch;
    float r = texture(iChannel0, uv + vec2(split, 0.0)).r;
    float g = texture(iChannel0, uv).g;
    float b = texture(iChannel0, uv - vec2(split, 0.0)).b;
    vec3 src = vec3(r, g, b);

    // Bloom: cheap 8-tap blur, in the text's own colours
    vec2 px = 1.0 / res;
    vec3 blur = vec3(0.0);
    blur += sampleRgb(uv + vec2( 2.0,  0.0) * px);
    blur += sampleRgb(uv + vec2(-2.0,  0.0) * px);
    blur += sampleRgb(uv + vec2( 0.0,  2.0) * px);
    blur += sampleRgb(uv + vec2( 0.0, -2.0) * px);
    blur += sampleRgb(uv + vec2( 3.0,  3.0) * px);
    blur += sampleRgb(uv + vec2(-3.0,  3.0) * px);
    blur += sampleRgb(uv + vec2( 3.0, -3.0) * px);
    blur += sampleRgb(uv + vec2(-3.0, -3.0) * px);
    blur = max(blur / 8.0 - BLOOM_FLOOR, 0.0);

    vec3 col = src + blur * BLOOM * 0.5;

    // Brighter band, plus a flicker while glitching
    float flicker = 1.0 + (hash11(frame) - 0.5) * 0.25 * glitch;
    col *= (1.0 + band * BAND_GLOW) * flicker;

    // Amber glass behind the text, and the band's amber light on top
    col += AMBER_DARK + AMBER * band * 0.03;
    float intensity = luma(col);

    // Scanlines (in screen pixels, so they stay put while the band moves)
    float scan = 0.5 + 0.5 * cos(fragCoord.y * 6.2831853 / SCANLINE_PX);
    col *= 1.0 - SCANLINE_DEPTH * scan;

    // Global slow flicker and static
    col *= 0.97 + 0.03 * sin(t * 110.0);
    col += (hash21(fragCoord + fract(t) * 100.0) - 0.5) * NOISE;

    // Vignette
    vec2 v = uv * (1.0 - uv);
    col *= mix(1.0, pow(v.x * v.y * 16.0, 0.25), VIGNETTE);

    // Transparent where the phosphor is dark, solid where it is lit.
    // Output is premultiplied, as the compositor expects.
    float lit = clamp((intensity - 0.08) * 3.0, 0.0, 1.0);
    float alpha = mix(OPACITY, 1.0, lit);
    fragColor = vec4(max(col, 0.0) * alpha, alpha);
}
