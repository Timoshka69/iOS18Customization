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
    float mean[3];
    float dev;
    int count;
} fx_band;

static fx_band fx_sample(const uint8_t *px, int bpr, int xa, int xb, int ya, int yb) {
    fx_band band;
    memset(&band, 0, sizeof(band));
    if (xb < xa) xb = xa;
    if (yb < ya) yb = ya;
    double sum[3] = {0, 0, 0};
    int n = 0;
    for (int y = ya; y <= yb; y++) {
        const uint8_t *row = px + (size_t)y * bpr;
        for (int x = xa; x <= xb; x++) {
            const uint8_t *p = row + x * 4;
            if (p[3] < 250) continue;
            float c[3];
            fx_load(p, c);
            sum[0] += c[0]; sum[1] += c[1]; sum[2] += c[2];
            n++;
        }
    }
    if (n == 0) return band;
    for (int i = 0; i < 3; i++) band.mean[i] = (float)(sum[i] / n);
    double dev = 0;
    for (int y = ya; y <= yb; y++) {
        const uint8_t *row = px + (size_t)y * bpr;
        for (int x = xa; x <= xb; x++) {
            const uint8_t *p = row + x * 4;
            if (p[3] < 250) continue;
            float c[3];
            fx_load(p, c);
            dev += fx_dist(c, band.mean);
        }
    }
    band.dev = (float)(dev / n);
    band.count = n;
    return band;
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

#define FX_X(f) (bx0 + (int)((f) * bw))
#define FX_Y(f) (by0 + (int)((f) * bh))
    fx_band top    = fx_sample(px, bpr, FX_X(0.30f), FX_X(0.70f), FX_Y(0.04f), FX_Y(0.10f));
    fx_band bottom = fx_sample(px, bpr, FX_X(0.30f), FX_X(0.70f), FX_Y(0.90f), FX_Y(0.96f));
    fx_band left   = fx_sample(px, bpr, FX_X(0.04f), FX_X(0.10f), FX_Y(0.30f), FX_Y(0.70f));
    fx_band right  = fx_sample(px, bpr, FX_X(0.90f), FX_X(0.96f), FX_Y(0.30f), FX_Y(0.70f));
#undef FX_X
#undef FX_Y

    // Not enough solid pixels near the edge: this is not a regular icon
    // (progress pie, highlight overlay, odd shapes). Leave it alone.
    if (top.count < 3 || bottom.count < 3) return I18FXUntouched;

    float topL = fx_luma(top.mean), bottomL = fx_luma(bottom.mean);
    if (topL < 0.26f && bottomL < 0.26f) return I18FXUntouched; // already dark

    float mid[3];
    for (int i = 0; i < 3; i++) mid[i] = (top.mean[i] + bottom.mean[i]) * 0.5f;

    float maxDev = fmaxf(top.dev, bottom.dev);
    float sideDist = 0.0f;
    if (left.count >= 3) { maxDev = fmaxf(maxDev, left.dev); sideDist = fmaxf(sideDist, fx_dist(left.mean, mid)); }
    if (right.count >= 3) { maxDev = fmaxf(maxDev, right.dev); sideDist = fmaxf(sideDist, fx_dist(right.mean, mid)); }

    bool uniform = maxDev < 0.065f && sideDist < 0.13f;

    // Plate with a coloured strip (Notes: yellow top, white body). If the
    // sides agree with one end, that end is the plate and the strip is
    // treated like part of the glyph.
    if (!uniform && left.count >= 3 && right.count >= 3 && left.dev < 0.065f && right.dev < 0.065f) {
        const fx_band *ends[2] = {&bottom, &top};
        for (int e = 0; e < 2 && !uniform; e++) {
            const fx_band *end = ends[e];
            if (end->dev < 0.065f && fx_dist(left.mean, end->mean) < 0.10f && fx_dist(right.mean, end->mean) < 0.10f) {
                top.mean[0] = bottom.mean[0] = end->mean[0];
                top.mean[1] = bottom.mean[1] = end->mean[1];
                top.mean[2] = bottom.mean[2] = end->mean[2];
                for (int i = 0; i < 3; i++) mid[i] = end->mean[i];
                uniform = true;
            }
        }
    }
    if (!uniform) return fx_dim(px, bpr, x0, y0, w, h, (flags & I18FXFlagStrongDim) ? 0.42f : 0.62f);

    float bgL = fx_luma(mid), bgS = fx_sat(mid);
    bool lightPlate = bgL > 0.70f && bgS < 0.20f;
    bool grayPlate = bgS < 0.12f;

    float topY = by0 + 0.07f * bh, bottomY = by0 + 0.93f * bh;
    for (int y = y0; y < y0 + h; y++) {
        uint8_t *row = px + (size_t)y * bpr;
        float t = fx_clamp((y - topY) / (bottomY - topY));
        float bg[3] = {
            fx_lerp(top.mean[0], bottom.mean[0], t),
            fx_lerp(top.mean[1], bottom.mean[1], t),
            fx_lerp(top.mean[2], bottom.mean[2], t),
        };
        float plateL = fx_luma(bg);
        float darkV = fx_lerp(I18_DARK_TOP, I18_DARK_BOTTOM, fx_clamp((float)(y - by0) / (float)bh));
        float dark[3] = {darkV, darkV, darkV};

        for (int x = x0; x < x0 + w; x++) {
            uint8_t *p = row + x * 4;
            float c[3];
            float a = fx_load(p, c);
            if (a <= 0.0f) continue;

            float m = fx_smoothstep(0.09f, 0.26f, fx_dist(c, bg));
            float L = fx_luma(c), S = fx_sat(c);
            float f[3];

            if (flags & I18FXFlagKeepGlyph) {
                f[0] = c[0]; f[1] = c[1]; f[2] = c[2];      // only swap the plate
            } else if (lightPlate) {
                if (L < 0.38f && S < 0.24f) {
                    float g = 0.95f - 0.35f * L;           // black text -> light text
                    f[0] = f[1] = f[2] = g;
                } else {
                    fx_lift(c, 0.72f, f);                   // keep colours readable
                }
            } else {
                bool lighter = L > plateL + 0.16f;
                if (lighter && S < 0.32f) {
                    if (grayPlate) {
                        float g = fx_clamp(0.30f + 0.62f * L);
                        f[0] = f[1] = f[2] = g;
                    } else {
                        fx_vivid(bg, f);                    // white glyph takes plate colour
                    }
                } else if (L < 0.30f && S < 0.25f) {
                    f[0] = f[1] = f[2] = 0.90f;             // dark glyph on coloured plate
                } else {
                    fx_lift(c, 0.62f, f);
                }
            }

            float o[3];
            for (int i = 0; i < 3; i++) o[i] = dark[i] * (1.0f - m) + f[i] * m;
            fx_store(p, o, a);
        }
    }
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
            float g = 0.62f * mx + 0.38f * fx_luma(c);
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
    return fx_luma_ramp(rgb, plate, 0.12f, 0.86f, false);
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
