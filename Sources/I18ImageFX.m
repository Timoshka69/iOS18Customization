//
//  I18ImageFX.m
//  iOS18Customization
//
//  How the "dark" conversion works (roughly what iOS 18 does for apps that
//  ship no dark icon):
//
//   1. Look at four thin bands just inside the icon edge and build a model of
//      the background (flat colour or vertical gradient).
//   2. If the background is uniform, every pixel gets a "foreground amount"
//      from its distance to that model. The background is replaced with the
//      dark iOS 18 gradient (#313131 -> #151515), the glyph is kept.
//      White glyphs on a coloured plate take the plate colour (Messages,
//      Phone, App Store...), black glyphs on a white plate become light.
//   3. Busy artwork (photos, diagonal gradients) is only dimmed.
//
//  Folder icons hand us one image with up to nine mini icons on a
//  transparent canvas, so the image is split into cells first.
//

#include "I18ImageFX.h"
#include <math.h>
#include <stdlib.h>
#include <string.h>

#define I18_DARK_TOP    (49.0f / 255.0f)
#define I18_DARK_BOTTOM (21.0f / 255.0f)

static inline float fx_clamp(float v) { return v < 0.0f ? 0.0f : (v > 1.0f ? 1.0f : v); }
static inline float fx_lerp(float a, float b, float t) { return a + (b - a) * t; }
static inline float fx_luma(const float c[3]) { return 0.299f * c[0] + 0.587f * c[1] + 0.114f * c[2]; }

static inline float fx_sat(const float c[3]) {
    float mx = fmaxf(c[0], fmaxf(c[1], c[2]));
    float mn = fminf(c[0], fminf(c[1], c[2]));
    return mx - mn;
}

static inline float fx_smoothstep(float e0, float e1, float x) {
    float t = fx_clamp((x - e0) / (e1 - e0));
    return t * t * (3.0f - 2.0f * t);
}

static inline float fx_dist(const float a[3], const float b[3]) {
    float dr = a[0] - b[0], dg = a[1] - b[1], db = a[2] - b[2];
    return sqrtf(dr * dr + dg * dg + db * db);
}

// Reads one premultiplied pixel and returns straight colour.
static inline float fx_load(const uint8_t *p, float c[3]) {
    float a = p[3] / 255.0f;
    if (a <= 0.0f) {
        c[0] = c[1] = c[2] = 0.0f;
        return 0.0f;
    }
    c[0] = fx_clamp(p[0] / 255.0f / a);
    c[1] = fx_clamp(p[1] / 255.0f / a);
    c[2] = fx_clamp(p[2] / 255.0f / a);
    return a;
}

static inline void fx_store(uint8_t *p, const float c[3], float a) {
    for (int i = 0; i < 3; i++) {
        float v = fx_clamp(c[i]) * a * 255.0f + 0.5f;
        p[i] = (uint8_t)(v > 255.0f ? 255.0f : v);
    }
}

#pragma mark - colour helpers

void I18FXHSVToRGB(float h, float s, float v, float out[3]) {
    h = h - floorf(h);
    s = fx_clamp(s);
    v = fx_clamp(v);
    float hh = h * 6.0f;
    int i = (int)floorf(hh) % 6;
    float f = hh - floorf(hh);
    float p = v * (1.0f - s);
    float q = v * (1.0f - s * f);
    float t = v * (1.0f - s * (1.0f - f));
    switch (i) {
        case 0: out[0] = v; out[1] = t; out[2] = p; break;
        case 1: out[0] = q; out[1] = v; out[2] = p; break;
        case 2: out[0] = p; out[1] = v; out[2] = t; break;
        case 3: out[0] = p; out[1] = q; out[2] = v; break;
        case 4: out[0] = t; out[1] = p; out[2] = v; break;
        default: out[0] = v; out[1] = p; out[2] = q; break;
    }
}

void I18FXRGBToHSV(const float rgb[3], float *h, float *s, float *v) {
    float r = fx_clamp(rgb[0]), g = fx_clamp(rgb[1]), b = fx_clamp(rgb[2]);
    float mx = fmaxf(r, fmaxf(g, b));
    float mn = fminf(r, fminf(g, b));
    float d = mx - mn;
    float hue = 0.0f;
    if (d > 1e-5f) {
        if (mx == r) hue = fmodf((g - b) / d, 6.0f);
        else if (mx == g) hue = (b - r) / d + 2.0f;
        else hue = (r - g) / d + 4.0f;
        hue /= 6.0f;
        if (hue < 0.0f) hue += 1.0f;
    }
    if (h) *h = hue;
    if (s) *s = mx > 1e-5f ? d / mx : 0.0f;
    if (v) *v = mx;
}

// The second slider: left end is a deep, fully saturated colour, the middle
// is the pure colour and the right end fades to almost white.
#define I18_TONE_KNEE 0.35f

void I18FXTintColor(float hue, float tone, float outRGB[3]) {
    tone = fx_clamp(tone);
    float s, v;
    if (tone <= I18_TONE_KNEE) {
        s = 1.0f;
        v = 0.70f + 0.30f * (tone / I18_TONE_KNEE);
    } else {
        s = 1.0f - 0.92f * ((tone - I18_TONE_KNEE) / (1.0f - I18_TONE_KNEE));
        v = 1.0f;
    }
    I18FXHSVToRGB(hue, s, v, outRGB);
}

void I18FXHueToneFromRGB(const float rgb[3], float *hue, float *tone) {
    float h, s, v;
    I18FXRGBToHSV(rgb, &h, &s, &v);
    float t;
    if (s < 0.06f) {
        t = 1.0f;
    } else if (s > 0.97f) {
        t = fx_clamp((v - 0.70f) / 0.30f) * I18_TONE_KNEE;
    } else {
        t = I18_TONE_KNEE + fx_clamp((1.0f - s) / 0.92f) * (1.0f - I18_TONE_KNEE);
    }
    if (hue) *hue = h;
    if (tone) *tone = fx_clamp(t);
}

static void fx_vivid(const float in[3], float out[3]) {
    float h, s, v;
    I18FXRGBToHSV(in, &h, &s, &v);
    s = fx_clamp(s * 1.06f);
    v = fmaxf(v, 0.93f);
    I18FXHSVToRGB(h, s, v, out);
}

static void fx_lift(const float in[3], float minV, float out[3]) {
    float h, s, v;
    I18FXRGBToHSV(in, &h, &s, &v);
    if (v >= minV) {
        out[0] = in[0]; out[1] = in[1]; out[2] = in[2];
        return;
    }
    I18FXHSVToRGB(h, s, minV, out);
}

#pragma mark - background sampling

typedef struct {
    float base[3];
    float slope[3];
    float inliers;   // share of ring pixels that match the model
    float residual;  // mean distance of those pixels to the model
} fx_plate;

static bool fx_fit_plate(const uint8_t *px, int bpr, int bx0, int by0, int bw, int bh, fx_plate *out) {
    int inner = (int)(bw * 0.025f), outer = (int)(bw * 0.085f);
    int innerY = (int)(bh * 0.025f), outerY = (int)(bh * 0.085f);
    if (outer <= inner) outer = inner + 1;
    if (outerY <= innerY) outerY = innerY + 1;

    int capacity = 2 * (outer - inner + 1) * bh + 2 * (outerY - innerY + 1) * bw + 16;
    float *samples = malloc(sizeof(float) * 4 * (size_t)capacity);
    if (!samples) return false;
    int n = 0;
    unsigned int hist[3][256];
    memset(hist, 0, sizeof(hist));

    for (int y = by0; y < by0 + bh; y++) {
        int dy = y - by0, dyb = by0 + bh - 1 - y;
        bool rowBand = (dy >= innerY && dy <= outerY) || (dyb >= innerY && dyb <= outerY);
        const uint8_t *row = px + (size_t)y * bpr;
        for (int x = bx0; x < bx0 + bw; x++) {
            int dx = x - bx0, dxb = bx0 + bw - 1 - x;
            bool colBand = (dx >= inner && dx <= outer) || (dxb >= inner && dxb <= outer);
            // inside the frame band, but not deeper than the band on the other axis
            bool inFrame = (rowBand && dx >= inner && dxb >= inner) || (colBand && dy >= innerY && dyb >= innerY);
            if (!inFrame || n >= capacity) continue;
            const uint8_t *p = row + x * 4;
            if (p[3] < 250) continue;
            float c[3];
            fx_load(p, c);
            float *s = samples + n * 4;
            s[0] = c[0]; s[1] = c[1]; s[2] = c[2];
            s[3] = (float)dy / (float)bh;
            for (int i = 0; i < 3; i++) hist[i][(int)(c[i] * 255.0f + 0.5f)]++;
            n++;
        }
    }
    if (n < 24) {
        free(samples);
        return false;
    }

    // Start from the per-channel median (robust against the glyph).
    float base[3], slope[3] = {0, 0, 0};
    for (int i = 0; i < 3; i++) {
        unsigned int acc = 0;
        int v = 0;
        for (; v < 256; v++) {
            acc += hist[i][v];
            if (acc * 2 >= (unsigned int)n) break;
        }
        base[i] = v / 255.0f;
    }

    float inlierShare = 0.0f, residual = 1.0f;
    for (int pass = 0; pass < 4; pass++) {
        double st = 0, stt = 0, sc[3] = {0, 0, 0}, stc[3] = {0, 0, 0}, dist = 0;
        int m = 0;
        float limit = pass == 0 ? 0.16f : 0.11f;
        for (int k = 0; k < n; k++) {
            const float *s = samples + k * 4;
            float model[3] = {base[0] + slope[0] * s[3], base[1] + slope[1] * s[3], base[2] + slope[2] * s[3]};
            float d = fx_dist(s, model);
            if (d > limit) continue;
            m++;
            dist += d;
            st += s[3];
            stt += s[3] * s[3];
            for (int i = 0; i < 3; i++) {
                sc[i] += s[i];
                stc[i] += s[3] * s[i];
            }
        }
        if (m < 16) {
            inlierShare = (float)m / (float)n;
            break;
        }
        inlierShare = (float)m / (float)n;
        residual = (float)(dist / m);
        double denom = m * stt - st * st;
        for (int i = 0; i < 3; i++) {
            if (fabs(denom) < 1e-6) {
                slope[i] = 0.0f;
                base[i] = (float)(sc[i] / m);
            } else {
                slope[i] = (float)((m * stc[i] - st * sc[i]) / denom);
                base[i] = (float)((sc[i] - slope[i] * st) / m);
            }
        }
    }
    free(samples);

    for (int i = 0; i < 3; i++) {
        out->base[i] = base[i];
        out->slope[i] = slope[i];
    }
    out->inliers = inlierShare;
    out->residual = residual;
    return true;
}

#pragma mark - one icon

static I18FXResult fx_dim(uint8_t *px, int bpr, int x0, int y0, int w, int h, float amount) {
    for (int y = y0; y < y0 + h; y++) {
        uint8_t *row = px + (size_t)y * bpr;
        for (int x = x0; x < x0 + w; x++) {
            uint8_t *p = row + x * 4;
            for (int i = 0; i < 3; i++) p[i] = (uint8_t)(p[i] * amount + 0.5f);
        }
    }
    return I18FXDimmed;
}

/// Plate-coloured pixels that are not connected to the icon edge are only
/// background when they sit inside neutral (black / grey) glyphs, like the
/// holes of letters. Inside coloured glyphs they are part of the drawing
/// (white needle of Safari, tick marks) and must not turn dark.
/// Returns a mask (1 = keep as glyph) or NULL. Caller frees.
static uint8_t *fx_enclosed_islands(const uint8_t *px, int bpr, int x0, int y0, int w, int h,
                                    int bx0, int by0, int bw, int bh, const fx_plate *plate) {
    size_t count = (size_t)w * (size_t)h;
    uint8_t *state = calloc(count, 1);   // 0 = glyph, 1 = plate-like, 2 = reached from edge, 3 = keep
    int *queue = malloc(sizeof(int) * count);
    int *component = malloc(sizeof(int) * count);
    if (!state || !queue || !component) {
        free(state); free(queue); free(component);
        return NULL;
    }
    for (int y = 0; y < h; y++) {
        const uint8_t *row = px + (size_t)(y0 + y) * bpr;
        float t = fx_clamp((float)(y0 + y - by0) / (float)bh);
        float bg[3] = {plate->base[0] + plate->slope[0] * t, plate->base[1] + plate->slope[1] * t, plate->base[2] + plate->slope[2] * t};
        for (int x = 0; x < w; x++) {
            const uint8_t *p = row + (x0 + x) * 4;
            if (p[3] < 8) { state[y * w + x] = 2; continue; }   // outside the icon counts as edge
            float c[3];
            fx_load(p, c);
            if (fx_dist(c, bg) < 0.14f) state[y * w + x] = 1;
        }
    }
    // Flood from everything plate-like near the outer frame.
    int head = 0, tail = 0;
    int frameX = (int)(bw * 0.09f) + 1, frameY = (int)(bh * 0.09f) + 1;
    for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
            int gx = x0 + x, gy = y0 + y;
            bool nearEdge = gx - bx0 < frameX || bx0 + bw - 1 - gx < frameX || gy - by0 < frameY || by0 + bh - 1 - gy < frameY;
            int i = y * w + x;
            if ((state[i] == 1 && nearEdge) || state[i] == 2) {
                state[i] = 2;
                queue[tail++] = i;
            }
        }
    }
    while (head < tail) {
        int i = queue[head++];
        int x = i % w, y = i / w;
        const int nx[4] = {x - 1, x + 1, x, x};
        const int ny[4] = {y, y, y - 1, y + 1};
        for (int k = 0; k < 4; k++) {
            if (nx[k] < 0 || ny[k] < 0 || nx[k] >= w || ny[k] >= h) continue;
            int j = ny[k] * w + nx[k];
            if (state[j] == 1) {
                state[j] = 2;
                queue[tail++] = j;
            }
        }
    }
    // Remaining plate-like islands: look at the colour around each one.
    for (size_t start = 0; start < count; start++) {
        if (state[start] != 1) continue;
        int n = 0;
        head = 0; tail = 0;
        queue[tail++] = (int)start;
        state[start] = 4; // visiting
        double satSum = 0;
        int satCount = 0;
        while (head < tail) {
            int i = queue[head++];
            component[n++] = i;
            int x = i % w, y = i / w;
            const int nx[4] = {x - 1, x + 1, x, x};
            const int ny[4] = {y, y, y - 1, y + 1};
            for (int k = 0; k < 4; k++) {
                if (nx[k] < 0 || ny[k] < 0 || nx[k] >= w || ny[k] >= h) continue;
                int j = ny[k] * w + nx[k];
                if (state[j] == 1) {
                    state[j] = 4;
                    queue[tail++] = j;
                } else if (state[j] == 0) {
                    // Look a few pixels further out: the first ring around an
                    // island is anti-aliased and always looks coloured.
                    int sx = nx[k] + (nx[k] - x) * 3, sy = ny[k] + (ny[k] - y) * 3;
                    if (sx < 0 || sy < 0 || sx >= w || sy >= h || state[sy * w + sx] != 0) continue;
                    float c[3];
                    fx_load(px + (size_t)(y0 + sy) * bpr + (x0 + sx) * 4, c);
                    satSum += fx_sat(c);
                    satCount++;
                }
            }
        }
        uint8_t verdict = (satCount > 0 && satSum / satCount > 0.24) ? 3 : 2;
        for (int k = 0; k < n; k++) state[component[k]] = verdict;
    }
    free(queue);
    free(component);

    // Mask with a one pixel grow so the anti-aliased rim of a kept island
    // does not get a dark fringe.
    uint8_t *keep = calloc(count, 1);
    if (!keep) {
        free(state);
        return NULL;
    }
    bool any = false;
    for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
            if (state[y * w + x] != 3) continue;
            any = true;
            for (int dy = -1; dy <= 1; dy++) {
                for (int dx = -1; dx <= 1; dx++) {
                    int xx = x + dx, yy = y + dy;
                    if (xx >= 0 && yy >= 0 && xx < w && yy < h && state[yy * w + xx] != 2) keep[yy * w + xx] = 1;
                }
            }
        }
    }
    free(state);
    if (!any) {
        free(keep);
        return NULL;
    }
    return keep;
}

static I18FXResult fx_dark_region(uint8_t *px, int bpr, int x0, int y0, int w, int h, int flags) {
    // Opaque bounding box.
    int bx0 = x0 + w, by0 = y0 + h, bx1 = -1, by1 = -1;
    for (int y = y0; y < y0 + h; y++) {
        const uint8_t *row = px + (size_t)y * bpr;
        for (int x = x0; x < x0 + w; x++) {
            if (row[x * 4 + 3] > 128) {
                if (x < bx0) bx0 = x;
                if (x > bx1) bx1 = x;
                if (y < by0) by0 = y;
                if (y > by1) by1 = y;
            }
        }
    }
    if (bx1 < 0) return I18FXUntouched;
    int bw = bx1 - bx0 + 1, bh = by1 - by0 + 1;
    if (bw < 12 || bh < 12) return I18FXUntouched;

    // Plate model: colour = base + slope * t, t = 0 at the top edge and 1 at
    // the bottom. It is fitted to a ring just inside the icon edge with
    // outliers thrown away, so glyphs that run close to the edge (Safari's
    // compass, the Photos flower, the Mail envelope) do not spoil it.
    fx_plate plate;
    if (!fx_fit_plate(px, bpr, bx0, by0, bw, bh, &plate)) return I18FXUntouched;

    float mid[3];
    for (int i = 0; i < 3; i++) mid[i] = plate.base[i] + plate.slope[i] * 0.5f;
    float topC[3], bottomC[3];
    for (int i = 0; i < 3; i++) {
        topC[i] = plate.base[i];
        bottomC[i] = plate.base[i] + plate.slope[i];
    }
    bool plateFound = plate.inliers >= 0.40f && plate.residual <= 0.06f;
    if (plateFound && fx_luma(topC) < 0.26f && fx_luma(bottomC) < 0.26f) {
        return I18FXUntouched; // already dark
    }
    if (!plateFound) {
        // Busy artwork (Maps, games): keep it recognisable, just a bit darker.
        // In Tinted it becomes a mid-tone instead of a black square.
        return fx_dim(px, bpr, x0, y0, w, h, (flags & I18FXFlagStrongDim) ? 0.48f : 0.80f);
    }

    float bgL = fx_luma(mid), bgS = fx_sat(mid);
    // White plates (Calendar, Reminders, Photos): black text turns light.
    // Silver gradient plates (Settings, Camera) are grey plates: their glyph
    // keeps its shading, flipping it made them look like negatives.
    bool lightPlate = bgL > 0.84f && bgS < 0.20f;
    bool grayPlate = !lightPlate && bgS < 0.12f;
    uint8_t *keep = (flags & I18FXFlagKeepGlyph) ? NULL : fx_enclosed_islands(px, bpr, x0, y0, w, h, bx0, by0, bw, bh, &plate);

    for (int y = y0; y < y0 + h; y++) {
        uint8_t *row = px + (size_t)y * bpr;
        float t = fx_clamp((float)(y - by0) / (float)bh);
        float bg[3] = {
            fx_clamp(plate.base[0] + plate.slope[0] * t),
            fx_clamp(plate.base[1] + plate.slope[1] * t),
            fx_clamp(plate.base[2] + plate.slope[2] * t),
        };
        float plateL = fx_luma(bg);
        float vivid[3];
        fx_vivid(bg, vivid);
        float darkV = fx_lerp(I18_DARK_TOP, I18_DARK_BOTTOM, t);
        float dark[3] = {darkV, darkV, darkV};

        for (int x = x0; x < x0 + w; x++) {
            uint8_t *p = row + x * 4;
            float c[3];
            float a = fx_load(p, c);
            if (a <= 0.0f) continue;

            // Soft plate/glyph separation: anti-aliased edges and shading get
            // in-between values instead of snapping, so nothing looks pixelated.
            float m = fx_smoothstep(0.035f, 0.24f, fx_dist(c, bg));
            bool island = keep && keep[(size_t)(y - y0) * (size_t)w + (size_t)(x - x0)];
            if (island) m = 1.0f;
            float L = fx_luma(c), S = fx_sat(c);
            float neutral = 1.0f - fx_smoothstep(0.16f, 0.34f, S);
            float f[3];

            if (flags & I18FXFlagKeepGlyph) {
                f[0] = c[0]; f[1] = c[1]; f[2] = c[2];      // only swap the plate
            } else if (lightPlate) {
                // Colours stay, black text / glyphs become light (Calendar, Reminders).
                float lifted[3];
                fx_lift(c, 0.72f, lifted);
                float flip = neutral * (1.0f - fx_smoothstep(0.30f, 0.60f, L));
                float g = 0.95f - 0.35f * L;
                for (int i = 0; i < 3; i++) f[i] = fx_lerp(lifted[i], g, flip);
            } else if (grayPlate) {
                // Grey plates (Settings, Camera): keep the shading of the glyph,
                // only brighter - never flip it, that looked like an inverted icon.
                float lifted[3];
                fx_lift(c, 0.62f, lifted);
                float g = fx_clamp(0.36f + 0.62f * L);
                for (int i = 0; i < 3; i++) f[i] = fx_lerp(lifted[i], g, neutral);
            } else {
                // Coloured plate: white glyph takes the plate colour (Messages,
                // Phone, Mail), dark glyph turns light, colours stay.
                float lifted[3];
                fx_lift(c, 0.62f, lifted);
                float white = fx_smoothstep(plateL + 0.05f, plateL + 0.22f, L) * neutral;
                float black = (1.0f - fx_smoothstep(0.22f, 0.40f, L)) * neutral;
                for (int i = 0; i < 3; i++) {
                    float v = fx_lerp(lifted[i], vivid[i], white);
                    f[i] = fx_lerp(v, 0.90f, black * (1.0f - white));
                }
            }

            float o[3];
            for (int i = 0; i < 3; i++) o[i] = dark[i] * (1.0f - m) + f[i] * m;
            fx_store(p, o, a);
        }
    }
    free(keep);
    return I18FXConverted;
}

#pragma mark - clock & hands

// Clock face: everything inside the round dial gets its brightness flipped
// (white dial -> near black, black numerals -> white), coloured parts keep
// their hue. The plate around the dial is left as it is.
static I18FXResult fx_dark_clock(uint8_t *px, int width, int height, int bpr) {
    float cx = width * 0.5f, cy = height * 0.5f;
    float r = fminf(width, height) * 0.5f;
    for (int y = 0; y < height; y++) {
        uint8_t *row = px + (size_t)y * bpr;
        for (int x = 0; x < width; x++) {
            uint8_t *p = row + x * 4;
            float c[3];
            float a = fx_load(p, c);
            if (a <= 0.0f) continue;
            float dx = (x + 0.5f - cx) / r, dy = (y + 0.5f - cy) / r;
            float inside = 1.0f - fx_smoothstep(0.86f, 0.93f, sqrtf(dx * dx + dy * dy));
            if (inside <= 0.0f) continue;
            float S = fx_sat(c);
            if (S > 0.35f) continue;
            float L = fx_luma(c);
            float flipped = fx_clamp(0.11f + 0.84f * (1.0f - L));
            float o[3];
            for (int i = 0; i < 3; i++) o[i] = fx_lerp(c[i], flipped, inside);
            fx_store(p, o, a);
        }
    }
    return I18FXConverted;
}

static I18FXResult fx_light_hand(uint8_t *px, int width, int height, int bpr) {
    bool changed = false;
    for (int y = 0; y < height; y++) {
        uint8_t *row = px + (size_t)y * bpr;
        for (int x = 0; x < width; x++) {
            uint8_t *p = row + x * 4;
            float c[3];
            float a = fx_load(p, c);
            if (a <= 0.0f) continue;
            if (fx_sat(c) < 0.25f && fx_luma(c) < 0.5f) {
                float o[3] = {0.95f, 0.95f, 0.95f};
                fx_store(p, o, a);
                changed = true;
            }
        }
    }
    return changed ? I18FXConverted : I18FXUntouched;
}

#pragma mark - entry point

typedef struct { int start, end; } fx_run;

static int fx_runs(const int *counts, int n, int minCount, fx_run *out, int maxRuns) {
    int found = 0, start = -1;
    for (int i = 0; i <= n; i++) {
        bool on = i < n && counts[i] >= minCount;
        if (on && start < 0) start = i;
        if (!on && start >= 0) {
            if (found < maxRuns) {
                out[found].start = start;
                out[found].end = i - 1;
            }
            found++;
            start = -1;
        }
    }
    return found;
}

I18FXResult I18FXMakeDark(uint8_t *px, int width, int height, int bytesPerRow) {
    return I18FXMakeDarkWithFlags(px, width, height, bytesPerRow, 0);
}

I18FXResult I18FXMakeDarkWithFlags(uint8_t *px, int width, int height, int bytesPerRow, int flags) {
    if (!px || width < 8 || height < 8) return I18FXUntouched;

    // Long and thin: a clock hand or a separator, not an icon.
    if (width > height * 2.2f || height > width * 2.2f) {
        return fx_light_hand(px, width, height, bytesPerRow);
    }

    if (flags & I18FXFlagClock) return fx_dark_clock(px, width, height, bytesPerRow);

    int *cols = calloc((size_t)width, sizeof(int));
    int *rows = calloc((size_t)height, sizeof(int));
    if (!cols || !rows) {
        free(cols);
        free(rows);
        return I18FXUntouched;
    }
    for (int y = 0; y < height; y++) {
        const uint8_t *row = px + (size_t)y * bytesPerRow;
        for (int x = 0; x < width; x++) {
            if (row[x * 4 + 3] > 128) {
                cols[x]++;
                rows[y]++;
            }
        }
    }

    enum { kMaxRuns = 8 };
    fx_run colRuns[kMaxRuns], rowRuns[kMaxRuns];
    int nc = fx_runs(cols, width, 2, colRuns, kMaxRuns);
    int nr = fx_runs(rows, height, 2, rowRuns, kMaxRuns);
    free(cols);
    free(rows);

    if (nc == 0 || nr == 0) return I18FXUntouched;

    if ((nc > 1 || nr > 1) && nc <= kMaxRuns && nr <= kMaxRuns) {
        // Mini icons of a folder.
        I18FXResult result = I18FXUntouched;
        for (int r = 0; r < nr; r++) {
            for (int c = 0; c < nc; c++) {
                int x0 = colRuns[c].start, x1 = colRuns[c].end;
                int y0 = rowRuns[r].start, y1 = rowRuns[r].end;
                I18FXResult one = fx_dark_region(px, bytesPerRow, x0, y0, x1 - x0 + 1, y1 - y0 + 1, flags);
                if (one != I18FXUntouched) result = I18FXConverted;
            }
        }
        return result;
    }

    return fx_dark_region(px, bytesPerRow, 0, 0, width, height, flags);
}

#pragma mark - tinted

void I18FXMakeTintReady(uint8_t *px, int width, int height, int bytesPerRow) {
    // A colour matrix can only use linear luma, which makes saturated blue or
    // red glyphs look muddy once tinted. iOS 18 keeps them bright, so the
    // brightness is baked into a grey image here and the on-screen filter only
    // has to map grey -> tint colour.
    for (int y = 0; y < height; y++) {
        uint8_t *row = px + (size_t)y * bytesPerRow;
        for (int x = 0; x < width; x++) {
            uint8_t *p = row + x * 4;
            float c[3];
            float a = fx_load(p, c);
            if (a <= 0.0f) continue;
            float mx = fmaxf(c[0], fmaxf(c[1], c[2]));
            // Slight curve keeps light details (needles, ticks) apart from the glyph.
            float g = powf(0.50f * mx + 0.50f * fx_luma(c), 1.45f);
            float o[3] = {g, g, g};
            fx_store(p, o, a);
        }
    }
}

#pragma mark - matrices

void I18FXApplyMatrix(uint8_t *px, int width, int height, int bytesPerRow, const I18FXMatrix *matrix) {
    const float *m = matrix->m;
    for (int y = 0; y < height; y++) {
        uint8_t *row = px + (size_t)y * bytesPerRow;
        for (int x = 0; x < width; x++) {
            uint8_t *p = row + x * 4;
            if (p[3] == 0) continue;
            float in[4] = {p[0] / 255.0f, p[1] / 255.0f, p[2] / 255.0f, p[3] / 255.0f};
            float out[4];
            for (int i = 0; i < 4; i++) {
                const float *r = m + i * 5;
                out[i] = r[0] * in[0] + r[1] * in[1] + r[2] * in[2] + r[3] * in[3] + r[4] * in[3];
            }
            float a = fx_clamp(out[3]);
            for (int i = 0; i < 3; i++) {
                float v = out[i];
                if (v < 0.0f) v = 0.0f;
                if (v > a) v = a;
                p[i] = (uint8_t)(v * 255.0f + 0.5f);
            }
            p[3] = (uint8_t)(a * 255.0f + 0.5f);
        }
    }
}

static const float kLuma[3] = {0.299f, 0.587f, 0.114f};

// out = plate * a + (tint - plate) * gain * (luma - l0 * a)
static I18FXMatrix fx_luma_ramp(const float tint[3], const float plate[3], float l0, float l1, bool invert) {
    I18FXMatrix mx;
    memset(&mx, 0, sizeof(mx));
    float gain = 1.0f / (l1 - l0);
    for (int i = 0; i < 3; i++) {
        float k = (tint[i] - plate[i]) * gain;
        float *row = mx.m + i * 5;
        if (!invert) {
            row[0] = k * kLuma[0];
            row[1] = k * kLuma[1];
            row[2] = k * kLuma[2];
            row[3] = plate[i] - k * l0;
        } else {
            // luma' = a - luma (light widgets become dark ones)
            row[0] = -k * kLuma[0];
            row[1] = -k * kLuma[1];
            row[2] = -k * kLuma[2];
            row[3] = plate[i] + k * (1.0f - l0);
        }
    }
    mx.m[18] = 1.0f;
    return mx;
}

I18FXMatrix I18FXIconTintMatrix(const float rgb[3]) {
    float plate[3];
    for (int i = 0; i < 3; i++) plate[i] = rgb[i] * 0.13f + 0.016f;
    return fx_luma_ramp(rgb, plate, 0.06f, 0.78f, false);
}

I18FXMatrix I18FXWidgetTintMatrix(const float rgb[3], bool lightContent) {
    float plate[3];
    for (int i = 0; i < 3; i++) plate[i] = rgb[i] * 0.19f + 0.018f;
    return fx_luma_ramp(rgb, plate, 0.10f, 0.88f, lightContent);
}

I18FXMatrix I18FXBadgeTintMatrix(const float rgb[3]) {
    // Red plate (g+b small) -> tint, white numerals -> white.
    I18FXMatrix mx;
    memset(&mx, 0, sizeof(mx));
    const float w = 0.5f / 0.79f, off = 0.21f / 0.79f;
    for (int i = 0; i < 3; i++) {
        float *row = mx.m + i * 5;
        float span = 1.0f - rgb[i];
        row[1] = span * w;
        row[2] = span * w;
        row[3] = rgb[i] - span * off;
    }
    mx.m[18] = 1.0f;
    return mx;
}
