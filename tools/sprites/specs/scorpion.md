# Slate scorpion art

Original 64x64 pixel-art scorpion. Eight directions in atlas columns S, SE, E, NE, N, NW, W, SW. Art package only: no scene, behavior, spawning, hitbox, damage, or balance wiring.

## Source and provenance

Original geometry drawn and posed in Python, encoded as SpriteU JSON, validated with SpriteU check_sprite.py and rendered/exported with SpriteU sheet.py. Stock image was used only as subject/pose inspiration; no pixels sampled, copied, or traced. SpriteU source is stored beside this document in scorpion.spriteu.json. No separate SpriteU repository mutation is required for this self-contained gangU package.

Original slate shading retained. Faceted sharper experiment excluded.

## Layout and timings

Atlas 512x1728, transparent, 64px cells, 27 rows, 216 frames, 48 animations.

- Rows0-3 idle: 200ms per frame, loop.
- Rows4-8 walk: 85ms per frame, loop.
- Rows9-13 attack: ground-hit tail sting, 180/180/60/180/180ms, no loop.
- Rows14-16 hurt: 90ms per frame, no loop.
- Rows17-21 death: 130ms per frame, no loop.
- Rows22-26 pincer: 100/420/60/160/160ms, no loop. Pulled-back loaded pose, 420ms hold, 3px forward extension beyond rest; recovery320ms. Timings are art timing, not a combat specification.

pack_scorpion_spriteu.py regenerates the transparent atlas and SpriteFrames resource from source. Resource is not referenced by any enemy. The attack naming uses the existing eight-direction suffix convention.

## Evidence

All frames are connected, inside64px and touch no cell boundary. Previews are art-only animation playback, not gameplay or AI demos. Runtime integration and gameplay verification are out of scope. CI and independent exact-head review are still required before merge.
