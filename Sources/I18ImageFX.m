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
    float base[3];   // colour at the top left
    float su[3];     // change from left to right edge
    float st[3];     // change from top to bottom edge
    float inliers;   // share of ring pixels that match the model
    float residual;  // mean distance of those pixels to the model
} fx_plate;

/// Plate colour at relative position (u, t), both 0...1.
static inline void fx_plate_at(const fx_plate *plate, float u, float t, float out[3]) {
    for (int i = 0; i < 3; i++) out[i] = fx_clamp(plate->base[i] + plate->su[i] * u + plate->st[i] * t);
}

/// Fits a flat or linearly graded plate (vertical, horizontal or diagonal
/// gradients) to a ring just inside the icon edge, throwing outliers away,
/// so glyphs that run close to the edge do not spoil it.
static bool fx_fit_plate(const uint8_t *px, int bpr, int bx0, int by0, int bw, int bh, fx_plate *out) {
    int inner = (int)(bw * 0.025f), outer = (int)(bw * 0.085f);
    int innerY = (int)(bh * 0.025f), outerY = (int)(bh * 0.085f);
    if (outer <= inner) outer = inner + 1;
    if (outerY <= innerY) outerY = innerY + 1;

    int capacity = 2 * (outer - inner + 1) * bh + 2 * (outerY - innerY + 1) * bw + 16;
    float *samples = malloc(sizeof(float) * 5 * (size_t)capacity);
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
            float *sm = samples + n * 5;
            sm[0] = c[0]; sm[1] = c[1]; sm[2] = c[2];
            sm[3] = (float)dx / (float)bw;
            sm[4] = (float)dy / (float)bh;
            for (int i = 0; i < 3; i++) hist[i][(int)(c[i] * 255.0f + 0.5f)]++;
            n++;
        }
    }
    if (n < 24) {
        free(samples);
        return false;
    }

    // Start from the per-channel median (robust against the glyph).
    fx_plate model;
    memset(&model, 0, sizeof(model));
    for (int i = 0; i < 3; i++) {
        unsigned int acc = 0;
        int v = 0;
        for (; v < 256; v++) {
            acc += hist[i][v];
            if (acc * 2 >= (unsigned int)n) break;
        }
        model.base[i] = v / 255.0f;
    }

    float inlierShare = 0.0f, residual = 1.0f;
    for (int pass = 0; pass < 5; pass++) {
        double S = 0, Su = 0, St = 0, Suu = 0, Sut = 0, Stt = 0, dist = 0;
        double Sc[3] = {0, 0, 0}, Suc[3] = {0, 0, 0}, Stc[3] = {0, 0, 0};
        float limit = pass == 0 ? 0.16f : 0.11f;
        for (int k = 0; k < n; k++) {
            const float *sm = samples + k * 5;
            float expected[3];
            for (int i = 0; i < 3; i++) expected[i] = model.base[i] + model.su[i] * sm[3] + model.st[i] * sm[4];
            float d = fx_dist(sm, expected);
            if (d > limit) continue;
            double u = sm[3], t = sm[4];
            S += 1; Su += u; St += t; Suu += u * u; Sut += u * t; Stt += t * t;
            dist += d;
            for (int i = 0; i < 3; i++) {
                Sc[i] += sm[i];
                Suc[i] += u * sm[i];
                Stc[i] += t * sm[i];
            }
        }
        inlierShare = (float)(S / n);
        if (S < 16) break;
        residual = (float)(dist / S);
        // Least squares for colour = base + su * u + st * t (Cramer's rule).
        double a11 = S, a12 = Su, a13 = St, a22 = Suu, a23 = Sut, a33 = Stt;
        double det = a11 * (a22 * a33 - a23 * a23) - a12 * (a12 * a33 - a23 * a13) + a13 * (a12 * a23 - a22 * a13);
        for (int i = 0; i < 3; i++) {
            if (fabs(det) < 1e-6) {
                model.base[i] = (float)(Sc[i] / S);
                model.su[i] = model.st[i] = 0.0f;
                continue;
            }
            double b1 = Sc[i], b2 = Suc[i], b3 = Stc[i];
            double d1 = b1 * (a22 * a33 - a23 * a23) - a12 * (b2 * a33 - a23 * b3) + a13 * (b2 * a23 - a22 * b3);
            double d2 = a11 * (b2 * a33 - a23 * b3) - b1 * (a12 * a33 - a23 * a13) + a13 * (a12 * b3 - b2 * a13);
            double d3 = a11 * (a22 * b3 - b2 * a23) - a12 * (a12 * b3 - b2 * a13) + b1 * (a12 * a23 - a22 * a13);
            model.base[i] = (float)(d1 / det);
            model.su[i] = (float)(d2 / det);
            model.st[i] = (float)(d3 / det);
        }
    }
    free(samples);

    *out = model;
    out->inliers = inlierShare;
    out->residual = residual;
    return true;
}

#pragma mark - one icon

/// Busy artwork (Maps, games, photos) has no plate that could be swapped.
/// Light, greyish areas (the paper of a map, white backgrounds) are taken
/// down hard so the icon reads as a dark icon; colourful parts are only
/// dimmed a little, so the icon stays recognisable.
/// Busy artwork that has a dark version in iOS 18 (Maps): the map itself
/// becomes dark grey (roads lighter than land, like the iOS 18 icon), only
/// strong colours (the blue route, the arrow) keep their colour.
static I18FXResult fx_busy_dark(uint8_t *px, int bpr, int x0, int y0, int w, int h, float amount) {
    for (int y = y0; y < y0 + h; y++) {
        uint8_t *row = px + (size_t)y * bpr;
        for (int x = x0; x < x0 + w; x++) {
            uint8_t *p = row + x * 4;
            float c[3];
            float a = fx_load(p, c);
            if (a <= 0.0f) continue;
            float L = fx_luma(c), S = fx_sat(c);
            float hh, ss, vv;
            I18FXRGBToHSV(c, &hh, &ss, &vv);
            // Blue / red markings stay; greens and yellows of the map do not.
            bool keepHue = (hh > 0.52f && hh < 0.75f) || hh < 0.03f || hh > 0.95f;
            float keep = keepHue ? fx_smoothstep(0.45f, 0.70f, S) * fx_smoothstep(0.35f, 0.60f, vv) : 0.0f;
            float grey = 0.09f + 0.36f * L * L * L;
            float o[3];
            for (int k = 0; k < 3; k++) o[k] = fx_lerp(grey, c[k] * amount, keep);
            fx_store(p, o, a);
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
        for (int x = 0; x < w; x++) {
            const uint8_t *p = row + (x0 + x) * 4;
            if (p[3] < 8) { state[y * w + x] = 2; continue; }   // outside the icon counts as edge
            float bg[3];
            fx_plate_at(plate, fx_clamp((float)(x0 + x - bx0) / (float)bw), t, bg);
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

static I18FXResult fx_dark_region_core(uint8_t *px, int bpr, int x0, int y0, int w, int h, int flags) {
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

    // Plate model: a flat colour or a linear gradient in any direction, fitted
    // to a ring just inside the icon edge (see fx_fit_plate).
    fx_plate plate;
    if (!fx_fit_plate(px, bpr, bx0, by0, bw, bh, &plate)) return I18FXUntouched;

    float mid[3], corners[4][3];
    fx_plate_at(&plate, 0.5f, 0.5f, mid);
    fx_plate_at(&plate, 0.0f, 0.0f, corners[0]);
    fx_plate_at(&plate, 1.0f, 0.0f, corners[1]);
    fx_plate_at(&plate, 0.0f, 1.0f, corners[2]);
    fx_plate_at(&plate, 1.0f, 1.0f, corners[3]);
    bool plateFound = plate.inliers >= 0.62f && plate.residual <= 0.05f;
    if (!plateFound) {
        // No clean plate (pictures, games, photos): not an icon that can be
        // given a dark background without spoiling it. Left exactly as it
        // is - only Maps-like artwork is darkened when asked for.
        if (flags & I18FXFlagBusyDark) return fx_busy_dark(px, bpr, x0, y0, w, h, 0.95f);
        return I18FXUnsupported;
    }
    bool dark = true;
    for (int k = 0; k < 4; k++) dark = dark && fx_luma(corners[k]) < 0.26f;
    // Already a dark icon. For Tinted it still goes through: its glyph is
    // separated from the plate like any other.
    if (dark && !(flags & I18FXFlagStrongDim)) return I18FXUntouched;

    float bgL = fx_luma(mid), bgS = fx_sat(mid);
    // White plates (Calendar, Reminders, Photos): black text turns light.
    // Silver gradient plates (Settings, Camera) are grey plates: their glyph
    // keeps its shading, flipping it made them look like negatives.
    bool lightPlate = bgL > 0.84f && bgS < 0.20f;
    bool grayPlate = !lightPlate && bgS < 0.12f;
    uint8_t *keep = (flags & I18FXFlagKeepGlyph) ? NULL : fx_enclosed_islands(px, bpr, x0, y0, w, h, bx0, by0, bw, bh, &plate);

    // Distance of every pixel to the plate, and the largest distance close
    // to it. An anti-aliased edge pixel is a mix of glyph and plate: its
    // share of glyph is (its distance) / (distance of the glyph next to it).
    // Using that share instead of a threshold keeps every edge as smooth as
    // in the original icon - no stair steps, no speckles.
    size_t count = (size_t)w * (size_t)h;
    float *dist = malloc(sizeof(float) * count);
    float *near = malloc(sizeof(float) * count);
    float *soft = keep ? malloc(sizeof(float) * count) : NULL;
    if (!dist || !near || (keep && !soft)) {
        free(dist); free(near); free(soft); free(keep);
        return I18FXUntouched;
    }
    size_t opaque = 0, glyphPixels = 0;
    for (int y = 0; y < h; y++) {
        const uint8_t *row = px + (size_t)(y0 + y) * bpr;
        float t = fx_clamp((float)(y0 + y - by0) / (float)bh);
        for (int x = 0; x < w; x++) {
            float bg[3], c[3];
            fx_plate_at(&plate, fx_clamp((float)(x0 + x - bx0) / (float)bw), t, bg);
            float a = fx_load(row + (x0 + x) * 4, c);
            float d = a > 0.0f ? fx_dist(c, bg) : 0.0f;
            dist[(size_t)y * w + x] = d;
            if (a > 0.5f) {
                opaque++;
                if (d > 0.15f) glyphPixels++;
            }
        }
    }
    // A "plate" that is only a thin frame around a big picture: leave it.
    if (!(flags & I18FXFlagKeepGlyph) && opaque > 0 && (float)glyphPixels / (float)opaque > 0.70f) {
        free(dist); free(near); free(soft); free(keep);
        return I18FXUnsupported;
    }
    // 5x5 maximum, done as two 1D passes (near = scratch, then back).
    const int radius = 2;
    for (int y = 0; y < h; y++) {
        for (int x = 0; x < w; x++) {
            float m = 0.0f;
            for (int k = -radius; k <= radius; k++) {
                int xx = x + k;
                if (xx >= 0 && xx < w) m = fmaxf(m, dist[(size_t)y * w + xx]);
            }
            near[(size_t)y * w + x] = m;
        }
    }
    float *column = malloc(sizeof(float) * (size_t)h);
    if (!column) {
        free(dist); free(near); free(soft); free(keep);
        return I18FXUntouched;
    }
    for (int x = 0; x < w; x++) {
        for (int y = 0; y < h; y++) column[y] = near[(size_t)y * w + x];
        for (int y = 0; y < h; y++) {
            float m = 0.0f;
            for (int k = -radius; k <= radius; k++) {
                int yy = y + k;
                if (yy >= 0 && yy < h) m = fmaxf(m, column[yy]);
            }
            near[(size_t)y * w + x] = m;
        }
    }
    free(column);
    // Islands kept as glyph get a soft (3x3 averaged) edge too.
    if (keep) {
        for (int y = 0; y < h; y++) {
            for (int x = 0; x < w; x++) {
                int sum = 0, n = 0;
                for (int dy = -1; dy <= 1; dy++) {
                    for (int dx = -1; dx <= 1; dx++) {
                        int xx = x + dx, yy = y + dy;
                        if (xx < 0 || yy < 0 || xx >= w || yy >= h) continue;
                        sum += keep[(size_t)yy * w + xx];
                        n++;
                    }
                }
                soft[(size_t)y * w + x] = n ? (float)sum / (float)n : 0.0f;
            }
        }
    }

    for (int y = y0; y < y0 + h; y++) {
        uint8_t *row = px + (size_t)y * bpr;
        float t = fx_clamp((float)(y - by0) / (float)bh);
        float darkV = fx_lerp(I18_DARK_TOP, I18_DARK_BOTTOM, t);
        float dark[3] = {darkV, darkV, darkV};

        for (int x = x0; x < x0 + w; x++) {
            uint8_t *p = row + x * 4;
            float c[3];
            float a = fx_load(p, c);
            if (a <= 0.0f) continue;
            float bg[3];
            fx_plate_at(&plate, fx_clamp((float)(x - bx0) / (float)bw), t, bg);
            float plateL = fx_luma(bg);
            float vivid[3];
            fx_vivid(bg, vivid);
            size_t i = (size_t)(y - y0) * (size_t)w + (size_t)(x - x0);

            float d = dist[i], dn = near[i];
            float gate = fx_smoothstep(0.035f, 0.12f, dn);          // is there a glyph around at all
            float m = gate * fx_clamp(d / fmaxf(dn, 0.10f));
            m = fx_smoothstep(0.0f, 1.0f, fx_clamp(m * 1.08f));      // a touch of contrast, still continuous

            // The glyph colour this pixel was mixed from.
            float g[3];
            if (m > 0.02f) {
                for (int k = 0; k < 3; k++) g[k] = fx_clamp(bg[k] + (c[k] - bg[k]) / fmaxf(m, 0.25f));
            } else {
                g[0] = c[0]; g[1] = c[1]; g[2] = c[2];
            }
            if (soft) {
                float island = soft[i];
                if (island > 0.0f) {
                    m = fmaxf(m, island);
                    for (int k = 0; k < 3; k++) g[k] = fx_lerp(g[k], c[k], island);
                }
            }

            float L = fx_luma(g), S = fx_sat(g);
            float neutral = 1.0f - fx_smoothstep(0.16f, 0.34f, S);
            float f[3];

            if (flags & I18FXFlagKeepGlyph) {
                f[0] = g[0]; f[1] = g[1]; f[2] = g[2];      // only swap the plate
            } else if (lightPlate) {
                // Colours stay, black text / glyphs become light (Calendar, Reminders).
                float lifted[3];
                fx_lift(g, 0.72f, lifted);
                float flip = neutral * (1.0f - fx_smoothstep(0.30f, 0.60f, L));
                float v = 0.95f - 0.35f * L;
                for (int k = 0; k < 3; k++) f[k] = fx_lerp(lifted[k], v, flip);
            } else if (grayPlate) {
                // Grey plates (Settings, Camera): keep the shading of the glyph,
                // only brighter - never flip it, that looked like an inverted icon.
                float lifted[3];
                fx_lift(g, 0.62f, lifted);
                float v = (flags & I18FXFlagStrongDim) ? fx_clamp(0.58f + 0.42f * L) : fx_clamp(0.36f + 0.62f * L);
                for (int k = 0; k < 3; k++) f[k] = fx_lerp(lifted[k], v, neutral);
            } else {
                // Coloured plate: white glyph takes the plate colour (Messages,
                // Phone, Mail), dark glyph turns light, colours stay.
                float lifted[3];
                fx_lift(g, 0.62f, lifted);
                // (In Tinted white stays white: it becomes the full tint.)
                float white = (flags & I18FXFlagStrongDim) ? 0.0f : fx_smoothstep(plateL + 0.05f, plateL + 0.22f, L) * neutral;
                float black = (1.0f - fx_smoothstep(0.22f, 0.40f, L)) * neutral;
                for (int k = 0; k < 3; k++) {
                    float v = fx_lerp(lifted[k], vivid[k], white);
                    f[k] = fx_lerp(v, 0.90f, black * (1.0f - white));
                }
            }

            float o[3];
            if (flags & I18FXFlagStrongDim) {
                // Tinted: grey levels for the colour matrix. The plate is an
                // even near-black, the glyph sits high in the range (so it
                // shows the full tint) and keeps a little of its shading.
                float plateGrey = fx_lerp(0.085f, 0.060f, t);
                float glyphGrey = 0.36f + 0.44f * fx_luma(f);
                float v = plateGrey * (1.0f - m) + glyphGrey * m;
                o[0] = o[1] = o[2] = v;
            } else {
                for (int k = 0; k < 3; k++) o[k] = dark[k] * (1.0f - m) + f[k] * m;
            }
            fx_store(p, o, a);
        }
    }
    free(dist);
    free(near);
    free(soft);
    free(keep);
    return I18FXConverted;
}

static void fx_tint_ready_region(uint8_t *px, int bpr, int x0, int y0, int w, int h);
static void fx_tint_art_region(uint8_t *px, int bpr, int x0, int y0, int w, int h);

/// One icon. For Tinted the result is always grey levels ready for the
/// colour matrix, whatever kind of icon it was.
static I18FXResult fx_dark_region(uint8_t *px, int bpr, int x0, int y0, int w, int h, int flags) {
    I18FXResult result = fx_dark_region_core(px, bpr, x0, y0, w, h, flags);
    if (!(flags & I18FXFlagStrongDim) || result == I18FXConverted) return result;
    if (result == I18FXUnsupported) fx_tint_art_region(px, bpr, x0, y0, w, h);
    else fx_tint_ready_region(px, bpr, x0, y0, w, h);
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
        I18FXResult result = fx_light_hand(px, width, height, bytesPerRow);
        if (!(flags & I18FXFlagStrongDim)) return result;
        fx_tint_ready_region(px, bytesPerRow, 0, 0, width, height);
        return I18FXConverted;
    }

    if (flags & I18FXFlagClock) {
        I18FXResult result = fx_dark_clock(px, width, height, bytesPerRow);
        if (flags & I18FXFlagStrongDim) fx_tint_ready_region(px, bytesPerRow, 0, 0, width, height);
        return result;
    }

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
                if (one == I18FXConverted || one == I18FXDimmed) result = I18FXConverted;
                else if (one == I18FXUnsupported && result == I18FXUntouched) result = I18FXUnsupported;
            }
        }
        return result;
    }

    return fx_dark_region(px, bytesPerRow, 0, 0, width, height, flags);
}

#pragma mark - tinted

static void fx_tint_ready_region(uint8_t *px, int bpr, int x0, int y0, int w, int h) {
    // Brightness as grey levels, saturated glyphs kept bright (a colour
    // matrix alone would make red or blue glyphs muddy).
    for (int y = y0; y < y0 + h; y++) {
        uint8_t *row = px + (size_t)y * bpr;
        for (int x = x0; x < x0 + w; x++) {
            uint8_t *p = row + x * 4;
            float c[3];
            float a = fx_load(p, c);
            if (a <= 0.0f) continue;
            float mx = fmaxf(c[0], fmaxf(c[1], c[2]));
            float g = powf(0.50f * mx + 0.50f * fx_luma(c), 1.45f);
            float o[3] = {g, g, g};
            fx_store(p, o, a);
        }
    }
}

static void fx_tint_art_region(uint8_t *px, int bpr, int x0, int y0, int w, int h) {
    // Pictures without a plate are only recoloured, but always end up as a
    // dark tile like every other tinted icon: a mostly light picture has its
    // brightness turned around (light background -> dark, drawing -> tint),
    // a dark one keeps it. A steep curve keeps it crisp instead of a muddy
    // half-tone.
    double sum = 0.0;
    size_t count = 0;
    for (int y = y0; y < y0 + h; y++) {
        const uint8_t *row = px + (size_t)y * bpr;
        for (int x = x0; x < x0 + w; x++) {
            float c[3];
            if (fx_load(row + x * 4, c) > 0.5f) {
                sum += 0.5f * fmaxf(c[0], fmaxf(c[1], c[2])) + 0.5f * fx_luma(c);
                count++;
            }
        }
    }
    bool light = count && sum / (double)count > 0.55;
    for (int y = y0; y < y0 + h; y++) {
        uint8_t *row = px + (size_t)y * bpr;
        for (int x = x0; x < x0 + w; x++) {
            uint8_t *p = row + x * 4;
            float c[3];
            float a = fx_load(p, c);
            if (a <= 0.0f) continue;
            float v = 0.5f * fmaxf(c[0], fmaxf(c[1], c[2])) + 0.5f * fx_luma(c);
            if (light) v = 1.0f - v;
            float g = 0.06f + 0.74f * fx_smoothstep(0.12f, 0.85f, v);
            float o[3] = {g, g, g};
            fx_store(p, o, a);
        }
    }
}

void I18FXMakeTintReady(uint8_t *px, int width, int height, int bytesPerRow) {
    fx_tint_ready_region(px, bytesPerRow, 0, 0, width, height);
}

void I18FXMakeTintReadyArt(uint8_t *px, int width, int height, int bytesPerRow) {
    fx_tint_art_region(px, bytesPerRow, 0, 0, width, height);
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
    // iOS 18: a near-black plate with only a breath of the tint.
    for (int i = 0; i < 3; i++) plate[i] = rgb[i] * 0.045f + 0.05f;
    return fx_luma_ramp(rgb, plate, 0.06f, 0.78f, false);
}

I18FXMatrix I18FXWidgetTintMatrix(const float rgb[3], bool lightContent) {
    float plate[3];
    for (int i = 0; i < 3; i++) plate[i] = rgb[i] * 0.09f + 0.05f;
    // Widgets that stay light (Weather: a sky picture behind white text)
    // need a steep ramp: the picture becomes the dark plate, the text tint.
    if (lightContent) return fx_luma_ramp(rgb, plate, 0.66f, 0.95f, false);
    return fx_luma_ramp(rgb, plate, 0.10f, 0.88f, false);
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
