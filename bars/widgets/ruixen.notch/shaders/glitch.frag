#version 440
// Globe-Launcher: the "jacked in" pass over the whole scene. Always: faint
// scanlines and a vignette. In a burst (intensity > 0), one of:
//   0 tear    horizontal slices torn sideways, colours split, noise lines
//   1 blocks  datamosh: blocks shoved out of place, coarse and recoloured
//   2 vhs     a wobble, a tracking band rolling down, colour bleeding
//   3 crt     the picture collapses to a bright line and snaps back
//   4 bleed   code bleed: columns smear downwards, drips of light
//   5 invert  a negative flash, posterised, jittering
// Opening (trans 0 -> 1): the same kinds carry the screen over from your
// desktop (desk, captured as it opened) to the launcher - torn bands, blocks,
// a rolling band, the desktop switching off and the launcher on, columns
// dripping, a negative flash. Closing runs it backwards, but to nothing:
// the window goes see-through there, onto the live desktop.
// CRT (crt = 1): heavier scanlines, an aperture-grille mask, dark rounded
// glass corners, and a faint rolling bar and flicker.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;
    vec2 resolution;
    float intensity;   // 0 calm .. 1 full burst
    float seed;        // changes per burst, so each tears differently
    float scanlines;   // 0..1
    vec4 tint;         // noise lines take this colour
    float kind;
    float trans;       // 1 = the launcher; below 1, opening from the desktop
    float crt;         // 0 / 1
    float closing;     // 1 while closing: trans runs 1 -> 0, and where the
                       // launcher has gone the window turns see-through
    vec2 shockCenter;  // <namek's blast: its ring, px from the centre,
    float shockR;      // bending and splitting the picture as it passes
    float distortionStrength;
    float density;
    float shockAmt;    // 0..1
};
layout(binding = 1) uniform sampler2D source;
layout(binding = 2) uniform sampler2D desk;

float hash(float x) { return fract(sin(x * 127.1 + seed * 311.7) * 43758.5453); }
float hash2(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7)) + seed * 17.3) * 43758.5453); }

// while opening: how much of the launcher shows at a screen point
float reveal(vec2 uv) {
    float p = trans;
    if (p >= 1.0) return 1.0;
    if (kind < 0.5) {                                        // tear: band by band
        float band = floor(uv.y * 28.0 * density);
        return step(hash(band + 40.0) * 0.85, p);
    } else if (kind < 1.5) {                                 // blocks, at random
        vec2 b = floor(uv * vec2(24.0, 14.0) * density);
        return step(hash2(b + 70.0) * 0.9, p);
    } else if (kind < 2.5) {                                 // vhs: rolled in from the top
        float edge = p * 1.25 - 0.1 + (hash2(vec2(floor(uv.y * 90.0), 3.0)) - 0.5) * 0.08;
        return step(uv.y, edge);
    } else if (kind < 3.5) {                                 // crt: off, then on
        return step(0.5, p);
    } else if (kind < 4.5) {                                 // bleed: columns drip down
        float c = floor(uv.x * resolution.x * density / 10.0);
        float delay = hash2(vec2(c, 9.0)) * 0.45;
        return step(uv.y, (p - delay) / 0.55 * 1.1);
    }
    return step(0.5, p);                                     // invert: a flash between
}
float showLauncher = 1.0;
vec4 tex(vec2 uv) {
    vec4 a = texture(source, uv);
    if (showLauncher >= 1.0) return a;
    vec4 under = closing > 0.5 ? vec4(0.0) : texture(desk, uv);
    return mix(under, a, showLauncher);
}
vec3 split(vec2 uv, float amount) {
    vec4 c = tex(uv);
    return vec3(tex(uv + vec2(amount, 0.0)).r, c.g, tex(uv - vec2(amount, 0.0)).b);
}

void main() {
    vec2 uv = qt_TexCoord0;
    // (CRT doesn't bend the picture: clicks land where things are drawn, so
    // the curve is only suggested, by the dark rounded glass edge below)
    vec2 cuv = uv;
    // the blast's shockwave: a ring that bends the picture outward and
    // splits its colours as it passes, the screen jolting with it
    float shockSplit = 0.0;
    if (shockAmt > 0.0) {
        vec2 px0 = uv * resolution;
        vec2 rel = px0 - shockCenter;
        float dist = length(rel);
        float band = exp(-pow((dist - shockR) / 55.0, 2.0));
        uv -= rel / max(dist, 1.0) * band * 14.0 * shockAmt / resolution;
        uv += vec2(sin(uv.y * 90.0 + time * 60.0), 0.0) * 0.0012 * shockAmt * shockAmt;   // the feed shuddering
        shockSplit = band * shockAmt;
        cuv = uv;
    }
    float k = max(max(intensity, trans < 1.0 ? sin(trans * 3.14159) * 0.85 : 0.0), shockSplit * 0.3);
    k *= distortionStrength;
    showLauncher = reveal(uv);
    vec3 col;

    if (kind > 2.5 && kind < 3.5 && trans < 1.0) {
        // crt opening: the desktop squashes to a line, the launcher springs out of one
        float phase = trans < 0.5 ? 1.0 - trans * 2.0 : (trans - 0.5) * 2.0;
        float squash = max(0.02, phase * phase);
        float y = (uv.y - 0.5) / squash + 0.5;
        float inside = step(0.0, y) * step(y, 1.0);
        col = split(vec2(uv.x, clamp(y, 0.0, 1.0)), 0.003 * (1.0 - phase)) * inside * (1.0 + 1.5 * (1.0 - phase));
        float line = exp(-abs(uv.y - 0.5) * resolution.y / (2.0 + 30.0 * squash));
        col += mix(tint.rgb, vec3(1.0), 0.6) * line * (1.0 - phase);
    } else if (k < 0.001 || kind < 0.5) {
        // tear: bands of rows shifted sideways
        float band = floor(uv.y * density * mix(14.0, 46.0, hash(3.0)));
        float tear = (hash(band) - 0.5) * 0.08 * k * step(0.55, hash(band + 7.0));
        vec2 tuv = uv + vec2(tear, 0.0);
        col = split(tuv, 0.006 * k + 0.0008);
        float row = floor(uv.y * resolution.y / 2.0);
        col += tint.rgb * step(1.0 - 0.012 * k, hash(row + floor(time * 30.0))) * 0.6;
    } else if (kind < 1.5) {
        // blocks: some blocks pulled from elsewhere, pixelated, tinted
        vec2 grid = vec2(mix(18.0, 40.0, hash(1.0)), mix(10.0, 24.0, hash(2.0))) * density;
        vec2 b = floor(uv * grid);
        float hit = step(1.0 - 0.28 * k, hash2(b + floor(time * 12.0)));
        vec2 shove = (vec2(hash2(b + 3.1), hash2(b + 5.7)) - 0.5) * vec2(0.18, 0.06) * hit;
        float px = mix(1.0, 90.0, hit);
        vec2 cell = resolution / px;
        vec2 q = hit > 0.5 ? (floor((uv + shove) * cell) + 0.5) / cell : uv;
        col = split(q, 0.004 * k);
        col = mix(col, tint.rgb * dot(col, vec3(0.33)) * 1.6, hit * step(0.5, hash2(b + 9.9)));
    } else if (kind < 2.5) {
        // vhs: wobble, a rolling tracking band, colour bleed, a little roll
        float roll = fract(uv.y + k * 0.04 * hash(4.0));
        float wob = sin(roll * 40.0 * density + time * 9.0) * 0.004 * k + sin(roll * 7.0 - time * 3.0) * 0.003 * k;
        float bandY = trans < 1.0 ? trans * 1.25 - 0.1 : fract(time * 0.6 + hash(6.0));
        float inBand = smoothstep(0.06, 0.0, abs(roll - bandY));
        float noise = hash2(vec2(floor(roll * resolution.y / 2.0), floor(time * 40.0)));
        vec2 vuv = vec2(uv.x + wob + inBand * (noise - 0.5) * 0.05 * k, roll);
        vec3 c = split(vuv, 0.003 + 0.01 * k);
        vec3 smear = (tex(vuv - vec2(0.004, 0.0)).rgb + tex(vuv - vec2(0.009, 0.0)).rgb) * 0.5;
        col = mix(c, vec3(smear.r, c.g, smear.b), 0.6 * k);
        col += vec3(noise) * inBand * 0.35 * max(k, 0.5 * step(trans, 0.999));
    } else if (kind < 3.5) {
        // crt: squashed to a line, with a flash in the middle
        float squash = 1.0 - 0.96 * k;
        float y = (uv.y - 0.5) / squash + 0.5;
        float inside = step(0.0, y) * step(y, 1.0);
        col = split(vec2(uv.x, clamp(y, 0.0, 1.0)), 0.002 * k) * inside * (1.0 + 1.5 * k);
        float line = exp(-abs(uv.y - 0.5) * resolution.y / (2.0 + 30.0 * squash));
        col += mix(tint.rgb, vec3(1.0), 0.6) * line * k;
    } else if (kind < 4.5) {
        // code bleed: each column dragged down by its own amount, drips of light
        float colW = mix(6.0, 14.0, hash(8.0)) / density;
        float c = floor(uv.x * resolution.x / colW);
        float drag = pow(hash2(vec2(c, 1.0)), 3.0) * 0.25 * k;
        vec2 buv = vec2(uv.x, uv.y - drag);
        vec3 a = tex(buv).rgb;
        vec3 b = tex(buv - vec2(0.0, drag * 0.5)).rgb;
        col = max(a, b * 0.8);
        float drip = step(0.9, hash2(vec2(c, 3.0))) * smoothstep(0.0, 0.02, drag) * exp(-abs(uv.y - fract(hash2(vec2(c, 5.0)) + time * 0.7)) * 60.0);
        col += tint.rgb * drip * 1.2 * k;
        col = mix(col, col * tint.rgb * 1.6, 0.35 * k);
    } else {
        // invert: a negative, posterised, jittering
        vec2 j = (vec2(hash(floor(time * 50.0)), hash(floor(time * 50.0) + 1.0)) - 0.5) * 0.012 * k;
        vec3 c = split(uv + j, 0.005 * k);
        vec3 neg = floor((1.0 - c) * 4.0 + 0.5) / 4.0;
        col = mix(c, neg * 0.7, step(0.25, k));          // dimmed: a flash, not a flashbang
    }

    // scanlines and vignette
    float sl = 0.5 + 0.5 * sin(uv.y * resolution.y * 3.14159);
    col *= 1.0 - scanlines * 0.12 * sl;
    vec2 v = uv - 0.5;
    col *= 1.0 - dot(v, v) * 0.55;

    if (crt > 0.5) {
        // heavier scanlines, an aperture grille, a rolling bar, flicker
        float line = 0.5 + 0.5 * sin(uv.y * resolution.y * 3.14159 * 0.5);
        col *= 0.72 + 0.28 * line;
        float g = mod(floor(qt_TexCoord0.x * resolution.x), 3.0);
        vec3 mask = g < 1.0 ? vec3(1.0, 0.82, 0.82) : g < 2.0 ? vec3(0.82, 1.0, 0.82) : vec3(0.82, 0.82, 1.0);
        col *= mask * 1.12;
        col *= 1.0 + 0.04 * smoothstep(0.0, 0.08, 0.08 - abs(fract(uv.y - time * 0.07) - 0.5));
        col *= 0.985 + 0.015 * sin(time * 120.0);
        // the glass: dark, softly rounded corners and a shade toward the
        // edges, as if it bowed out
        vec2 e = abs(cuv * 2.0 - 1.0);
        vec2 px2 = e * resolution * 0.5;                   // px from the centre
        vec2 inner = resolution * 0.5 - vec2(46.0);
        float rd = length(max(px2 - inner, 0.0)) - 40.0;   // rounded-rect distance
        float corner = 1.0 - smoothstep(-6.0, 2.0, rd);
        float bow = 1.0 - 0.22 * pow(max(e.x, e.y), 6.0);
        col *= corner * bow;
    }
    // closing: see-through wherever the launcher has gone (its glitchy
    // light still shows over the desktop)
    float alpha = 1.0;
    if (closing > 0.5 && trans < 1.0) {
        alpha = clamp(max(showLauncher, max(col.r, max(col.g, col.b)) * 1.4), 0.0, 1.0);
        if (kind > 2.5 && kind < 3.5) alpha = clamp(max(col.r, max(col.g, col.b)) * 2.0, 0.0, 1.0);
    }
    // Wallpaper adaptation: exact unchanged endpoints; distortion only between.
    if (crt < 0.5) {
        float envelope = sin(clamp(trans, 0.0, 1.0) * 3.14159265);
        vec3 plain = mix(texture(desk, qt_TexCoord0).rgb, texture(source, qt_TexCoord0).rgb, showLauncher);
        col = mix(plain, col, envelope);
    }
    fragColor = vec4(col, alpha) * qt_Opacity;
}
