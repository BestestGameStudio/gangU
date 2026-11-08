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

# spell_projectiles.png - spell projectile sprites (#210)
- Source: single sprite sheet attached to issue #210 by @Mitravasu
  (https://github.com/user-attachments/assets/f0f3f901-d1bc-48aa-8f67-d0df7610042b).
- Rows flame / mana / bolt, 8 loop frames each, 12 fps; packed at scale 4 into
  64x48 cells via `tools/sprites/specs/spell_projectiles.json`.
- The sheet's row labels sit close above the art, so the label text was keyed
  out of a working copy (dim lavender on the dark board) before extraction;
  the art itself is byte-faithful to the issue attachment.

# mustache_warrior.png - Mustache Warrior (common enemy + Warlord boss)

Art from issue #177 ("common enemy sprite update"): the 1536x1024
"Mustache Warrior - Common Enemy" concept sheet attached to the issue by the
project team. That sheet is a presentation board (labels, panels, dark
background, uneven spacing), so it is NOT shipped as-is; the engine sheet
here is cut from it by `tools/sprites/extract_frames.py` with
`tools/sprites/specs/mustache_warrior.json`
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

# head_boss.png - the Head (boss of DungeonC, #173)

Art from issue #173 ("BOSS SPRITE"): the 1536x1024 "Boss: Head (Top-Down
2D)" concept sheet attached to the issue by Mitravasu (project human). It is
a presentation board (labels, panels, dark background, uneven spacing and
panels drawn at different character sizes), so it is NOT shipped as-is; the
engine sheet here is cut from it by `tools/sprites/extract_frames.py` with
`tools/sprites/specs/head_boss.json` (background keyed out, 3:1
alpha-weighted downsample, hard alpha cut for crisp pixels). Reproduce:
`python3 -I tools/sprites/extract_frames.py pack tools/sprites/specs/head_boss.json <board.png> assets/sprites/head_boss.png --tres resources/sprites/head_boss_frames.tres`.

## Layout
- Cell: 48x48 px, chin on row 44, head ~24 px tall (the scene draws it 3x).
  Sheet: 11 cols x 7 rows (528x336).
- Rows (frames drawn on the board -> packed): 0 idle (6), 1 walk (7),
  2 projectile attack (8), 3 AoE pulse (8), 4 hurt (4), 5 stun (4),
  6 death (11).
- Animations (resources/sprites/head_boss_frames.tres): idle 6 (loop),
  walk 7 (loop), attack 4 (projectile frames 3-6, contact bite),
  windup_projectile 4 + projectile 4 (projectile row split at the scream),
  windup_aoe 4 + aoe 4 (AoE row split at the release), hurt 4, stun 4
  (loop), death 11 (last three frames held longer).
- Facing: idle/attack/stun are front views; the walk row faces LEFT, so the
  scene sets `EnemySprite.art_faces_left` and flip_h mirrors it toward the
  right.

## Board vs. extraction (labels lie)
- "Move (8, 4 dir)" draws 7 frames per row, and the rows are mislabelled:
  "Up" and "Down" are front views, "Right" faces LEFT and turns to the
  front, "Left" faces left. Only the consistent "Left" row is used (as walk).
- "Death (10)" draws 11 frames; all 11 are used.
- Per-row size normalisation (nearest resize before the downsample): the
  board draws walk heads ~0.8x, AoE heads ~0.9x and death heads ~1.25x the
  idle head, so those rows are resized 1.25 / 1.1 / 0.8 (stun 1.05). The
  walk panel also has a soft grey glow keyed out as a second backdrop colour.
- AoE: the board's pulse rings overlap the neighbouring frames and fade into
  the background, so only the heads are cut (`keep_largest`); the ring is
  drawn in-engine by `BossTelegraph`. A few ring pixels remain touching the
  head on the brightest pulse frame.
- Not extracted (no consumer, and drawn ~1.5x larger than the rows): the
  "FX / Telegraphed Variants" panels (Charge, Dash, Invulnerable/Shield,
  Targeted/Warning) and the "VFX Elements" overlays; the large portrait.

# shop_vendor.png - hub shop vendor stall (#217)

Art from issue #217 ("Shop Sprite Update"): the 1536x1024 six-frame board
attached to the issue by Mitravasu (project human). The board's background
is light/white with interior highlights, so the exterior background was
flood-filled to magenta before extraction (interior whites preserved), then
cut by `tools/sprites/extract_frames.py` with
`tools/sprites/specs/shop_vendor.json` (magenta keyed out, bbox-anchored,
2:1 alpha-weighted downsample, hard alpha cut for crisp pixels). Reproduce:
`python3 -I tools/sprites/extract_frames.py pack tools/sprites/specs/shop_vendor.json <keyed-board.png> assets/sprites/shop_vendor.png --tres resources/sprites/shop_vendor_frames.tres`.

## Layout
- Cell: 224x224 px, baseline row 220 (stall base). Sheet: 3 cols x 2 rows
  (672x448), one stall per cell; the scene draws it at 0.5 scale (~112 px).
- Frames are the board's six idle variants (potion sparkle / lighting
  positions). SpriteFrames (resources/sprites/shop_vendor_frames.tres):
  idle, 6 frames, 4 fps loop.
# spell_icons.png - player spell HUD icons (#207)

Art from issue #207 ("Spell ICON Sprites"): the 1448x1086 sheet attached to
the issue by Mitravasu (project human). The sheet is a regular 3x7 grid of
opaque framed tiles on a near-white page background; no keying was needed, so
the pack used a background colour absent from the sheet ([255, 0, 255] at
key_dist 54 matches nothing) and every pixel was kept. Cut by
`tools/sprites/extract_frames.py` with
`tools/sprites/specs/spell_icons.json` (bbox-anchored to the exact tile
windows, 4:1 downsample to the 47x48 cells). Reproduce:
`python3 -I tools/sprites/extract_frames.py pack tools/sprites/specs/spell_icons.json <issue-207-sheet.png> assets/sprites/spell_icons.png --tres resources/sprites/spell_icons_frames.tres`.

## Layout
- Cell: 47x48 px, baseline row 48. Sheet: 7 cols x 3 rows (329x144).
- Rows: fireball, mana, bolt. Cols: 0 base icon, 1 green-chevron upgrade
  icon, 2 alternate base (extracted, unused), 3-6 gray cooldown sweep at
  increasing coverage (~15/40/60/85%). SpriteFrames
  (resources/sprites/spell_icons_frames.tres): `<row>_base` (1 frame),
  `<row>_upgraded` (1 frame), `<row>_sweep` (4 frames, cols 3-6).
- Since #238 the `<row>_sweep` frames are packed but unused: cooldown is a
  code-drawn wipe in `SpellIcon`. `<row>_upgraded` is used only by surfaces
  without the upgrade overlay (shop, hub directory); the HUD and Tab panel
  draw `upgrade_chevron.png` over `<row>_base`.

# upgrade_chevron.png - upgrade-available overlay (#238)

Art from issue #238 ("FIx HUD"): the 2172x724 four-frame strip attached to the
issue by the project owner. The strip already has real transparency, so it was
cut with `tools/sprites/pack_alpha_strip.py` and
`tools/sprites/specs/upgrade_chevron.json` instead of the colour-keying
`extract_frames.py`: fixed 384x384 windows, 12:1 premultiplied box downsample,
source alpha below 32 dropped as generator noise (mostly around frame 3).
Reproduce:
`python3 -I tools/sprites/pack_alpha_strip.py pack tools/sprites/specs/upgrade_chevron.json <issue-238-strip.png> assets/sprites/upgrade_chevron.png --tres resources/sprites/upgrade_chevron_frames.tres`.

## Layout
- Cell: 32x32 px. Sheet: 4 cols x 1 row (128x32). Frames drawn at their
  sheet position, with no re-anchoring.
- SpriteFrames (resources/sprites/upgrade_chevron_frames.tres): `pulse`, 4
  frames, 8 fps loop.
