# main_character.png - original chunky wizard sprite sheet

Original hand-authored pixel art for gangU (#136). No copied game assets, no
traced art, no stock files shipped.

## Design
- Chunky wizard: oversized pointed hat with gold band, white beard, bell robe,
  stubby boots, wood staff with cyan orb. Among-Us-LIKE chunky proportions as
  style direction only (round little body, stubby legs) - original art, no
  Innersloth assets used or referenced as files.
- Flat palette, no gradients/glow, fitted to the existing player blue
  (73,142,232) with gate/HUD accents (gold band, spell-cyan orb).
- Frame: 32x48 px. Sheet: uniform 5x4 grid (160x192 px), rows = directions
  [down, left, right, up], col 0 = idle, cols 1-4 = walk cycle
  (contact, passing, contact, passing). Player footprint ~44px tall against
  the 64px grid.

## References (layout/timing only, not shipped art)
- "Space Guy - 8 Directional animated character 16x16"
  https://opengameart.org/content/space-guy-8-directional-animated-character-16x16
  License: CC0 (verified in page HTML 2026-11-07). File blitzorion.png
  (64x256, 16x16 frames) consulted for walk-cycle frame counts and direction
  ordering only; its slim astronaut proportions were NOT used.

## Provenance
- Author: instinctmitra (Mitra's Instinct), 2026-11-07, pixel-by-pixel via
  generator script (PIL), iterated against rendered previews.
- License for this original asset: CC0 (matches project asset licensing).

# mustache_warrior.png - Mustache Warrior (common enemy + Warlord boss)

Art from issue #177 ("common enemy sprite update"): the 1536x1024
"Mustache Warrior - Common Enemy" concept sheet attached to the issue by the
project team. That sheet is a presentation board (labels, panels, dark
background, uneven spacing), so it is NOT shipped as-is; the engine sheet
here is cut from it by `tools/sprites/extract_mustache_warrior.py`
(background keyed out, frames anchored on body/mustache centre + feet line,
3:1 alpha-weighted downsample, hard alpha cut for crisp pixels).

## Layout
- Cell: 64x48 px (wide enough for slash / spin arcs), feet on row 44,
  character ~36 px tall. Sheet: 8 cols x 10 rows (512x480).
- Rows (frames): 0 idle (4), 1 walk (8), 2 attack/melee (4), 3 hurt (3),
  4 death (6), 5 lunge (2), 6 spin (3), 7 ranged (3), 8 ranged orb (1),
  9 FX elements: slash, heavy slash, sparkle, burst (4).
- Art faces right; the game mirrors it with flip_h.
- The board's "Variants" and "Directional Sprites (4 dir)" panels are not
  extracted yet (no consumer); the board labels Lunge (4) / Spin (6) /
  Ranged (4) but draws 2 / 3 / 3 frames - the drawn frames are used.
- SpriteFrames: resources/sprites/mustache_warrior_frames.tres.
