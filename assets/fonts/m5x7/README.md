# m5x7

Font by Daniel Linssen. Official download: https://managore.itch.io/m5x7
Downloaded 2026-11-16, file `m5x7.ttf` (34,300 bytes).

The creator licenses m5x7 under CC0 1.0 Universal. Attribution is appreciated,
not required. The bundled CC0 deed is in `LICENSE.txt`.

The project theme uses this font by default, at 16px where no size is specified.
Existing explicit integer UI sizes are preserved to avoid changing layouts.
The creator recommends 16, 32, 48px, etc. Other sizes can have less regular
pixel proportions. Antialiasing, hinting, subpixel positioning, mipmaps and
MSDF are disabled, and oversampling is 1x. Fractional window/stretch scales
can still resample the final viewport; this change does not alter that policy.

`gui/theme/custom_font` also sets Godot's fallback, so direct fallback drawing
(map labels, arena labels, hammer dice) picks up m5x7 as well as normal UI
controls. Unsupported characters may use the enabled system fallback; existing
Latin UI strings are covered. Existing outlined damage numbers retain their
outline style. Text baked into sprite textures is not changed.
