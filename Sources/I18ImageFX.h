//
//  I18ImageFX.h
//  iOS18Customization
//
//  Plain C pixel routines. Everything here works on 8-bit RGBA buffers with
//  premultiplied alpha (R, G, B, A byte order), so the same code runs on the
//  phone and in the little desktop test harness in tools/.
//

#ifndef I18_IMAGE_FX_H
#define I18_IMAGE_FX_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Result of I18FXMakeDark().
typedef enum {
    I18FXUntouched = 0,   ///< image was left as is (already dark, too small, not an icon)
    I18FXConverted = 1,   ///< background was replaced, glyph kept / recoloured
    I18FXDimmed    = 2,   ///< busy artwork, darkened (only with I18FXFlagBusyDark)
    I18FXUnsupported = 3, ///< no clean plate: left as is, it would only get spoilt
} I18FXResult;

/// Turns a light app icon into an iOS 18 style "dark" icon in place.
/// Works for single icons, for folder mini-grids (several icons on a
/// transparent canvas) and for thin clock hands.
I18FXResult I18FXMakeDark(uint8_t *px, int width, int height, int bytesPerRow);

/// Same as above. Pass I18FXFlagClock for the face of the live Clock icon:
/// the dial is flipped (white dial -> dark dial, dark numerals -> white).
#define I18FXFlagClock 1
/// The conversion is for Tinted.
#define I18FXFlagStrongDim 2
/// Replace only the plate and keep the glyph colours (used for the Weather
/// previews of the panel: white cloud and yellow sun on a dark plate).
#define I18FXFlagKeepGlyph 4
/// Artwork without a plate (Maps) is darkened instead of left alone.
#define I18FXFlagBusyDark 8
/// The dark icon is made for Tinted (coloured afterwards): white glyphs
/// stay white, so they end up at the full tint.
#define I18FXFlagForTint 16
I18FXResult I18FXMakeDarkWithFlags(uint8_t *px, int width, int height, int bytesPerRow, int flags);

/// Converts an already dark icon to grey levels that keep saturated glyphs
/// bright. Used as the contents of tinted icons (the tint itself is a cheap
/// colour matrix on top, so the sliders update instantly).
void I18FXMakeTintReady(uint8_t *px, int width, int height, int bytesPerRow);
/// Grey levels for the tint matrix from a (dark) colour icon.
void I18FXMakeTintGrey(uint8_t *px, int width, int height, int bytesPerRow);
/// For icons without a plate (I18FXUnsupported): brightness only, kept in
/// the darker part of the range.
void I18FXMakeTintReadyArt(uint8_t *px, int width, int height, int bytesPerRow);

/// 4x5 colour matrix, rows are R, G, B, A; columns are r, g, b, a, offset.
/// Same layout as CAColorMatrix.
typedef struct {
    float m[20];
} I18FXMatrix;

/// Applies a colour matrix to a premultiplied buffer (CPU version of the
/// CAFilter that is used on screen).
void I18FXApplyMatrix(uint8_t *px, int width, int height, int bytesPerRow, const I18FXMatrix *matrix);

/// Matrices used by the tweak. `rgb` is the tint colour, 0...1.
I18FXMatrix I18FXIconTintMatrix(const float rgb[3]);
I18FXMatrix I18FXWidgetTintMatrix(const float rgb[3], bool lightContent);
I18FXMatrix I18FXBadgeTintMatrix(const float rgb[3]);

/// Tint colour for the two sliders: hue 0...1, tone 0...1
/// (0 = deep saturated colour, 1 = almost white).
void I18FXTintColor(float hue, float tone, float outRGB[3]);
void I18FXHSVToRGB(float h, float s, float v, float out[3]);
void I18FXRGBToHSV(const float rgb[3], float *h, float *s, float *v);
/// Inverse of I18FXTintColor for the eyedropper.
void I18FXHueToneFromRGB(const float rgb[3], float *hue, float *tone);

#ifdef __cplusplus
}
#endif

#endif
