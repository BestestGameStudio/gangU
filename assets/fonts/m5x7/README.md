# m5x7

Font by Daniel Linssen. Official download: https://managore.itch.io/m5x7
Downloaded 2026-11-16, file `m5x7.ttf` (34,300 bytes).

The creator licenses m5x7 under CC0 1.0 Universal. Attribution is appreciated,
not required. The bundled CC0 deed is in `LICENSE.txt`.

The project theme defaults to32px. Primary labels, headings and HUD use32px;
body text and hints use16px. These native steps match the creator's16/32/48px
recommendation. Upgrade descriptions never shrink below16px. Antialiasing,
hinting, subpixel positioning, mipmaps and MSDF are disabled; oversampling1x.
Fractional viewport stretching can still resample final pixels.

`gui/theme/custom_font` also sets Godot's fallback, so direct fallback drawing
(map labels, arena labels, hammer dice) picks up m5x7 as well as normal UI
controls. Unsupported characters may use the enabled system fallback; existing
Latin UI strings are covered. Existing outlined damage numbers retain their
outline style. Text baked into sprite textures is not changed.
