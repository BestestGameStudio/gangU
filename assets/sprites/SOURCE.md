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

# spell_upgrades.png - spell and upgrade animations (#289)
- Source: single sheet attached to issue #289 by @Mitravasu
  (https://github.com/user-attachments/assets/226db38e-d1cf-4de5-ac62-48c518bb1466).
  It has real transparency, so it is cut with `tools/sprites/pack_alpha_strip.py`
  and `tools/sprites/specs/spell_upgrades.json`: 2:1 premultiplied box downsample
  into 64x72 cells (6 per row, 14 rows), source alpha below 32 dropped, each
  frame clipped to its grid cell so no line or neighbour bleeds in.
- Rows (top to bottom): fire_ball, fire_ball_split, fire_ball_split_heavy,
  fire_ball_split_wide, fire_ball_beam, fire_ball_beam_heavy,
  fire_ball_beam_homing, fire_ball_beam_long, fire_ball_beam_piercing,
  mana_shot, mana_volley, mana_lance, placeholder_bolt, summon_ally.
- Animations: projectile rows are `<row>_start` (cols 0-2, one-shot, 18 fps) then
  `<row>` (cols 3, 4, 5, 4, loop, 12 fps). `summon_ally` is all six cols, one-shot,
  10 fps, last frames held. Art faces +X; the board's column labels (F1/F3/... and
  F1/F2/...) do not match across sections, so cells are read left to right.
- Multi-shot rows draw every shot in one cell, but the game fires one projectile
  per shot. So split, split heavy, split wide and volley cells are clipped to ONE
  shot per frame (from the col where the shots separate); each fanned projectile
  flies that shot. The other shots drawn in those cells are not extracted. The
  flight then shows split wide as 5 shots although its cols 2-4 draw 4.
- `spell_projectiles.png` (#210) is no longer used at runtime.
- #302 rows 14-15 (bolt upgrades): strip attached to issue #302 by @Mitravasu
  (https://github.com/user-attachments/assets/1a76faef-5c27-4169-a8c6-9d157faea854;
  1774x887 RGBA, 2 rows x 4 gold lightning frames, real transparency). Appended
  with `tools/sprites/append_sheet_rows.py` and
  `tools/sprites/specs/spell_upgrades_bolt_rows.json`: 6:1 premultiplied box
  downsample into the same 64x72 cells, source alpha below 32 dropped, each
  window centred on its frame. The strip draws 4 frames per bolt, so cells are
  filled 0,1,2,3,2,1 to keep the #289 layout: `<row>_start` (cols 0-2, one-shot,
  18 fps) then `<row>` (cols 3, 4, 5, 4, loop, 12 fps). Row assignment from the
  art: the upper thin zigzag is Bolt Flurry (fast multi-shot), the lower broader
  arrowhead is Heavy Bolt (piercing). Sheet is now 6x16 cells.
- #305 row 16 (spirit_punch): no external art strip. The source strip was
  drawn procedurally by the author agent with Python/PIL (neither the script
  nor the strip is committed, so regeneration means re-drawing it): an
  opaque white side-view fist pointing +X, the same facing convention as the
  other rows, built from rounded-rectangle palm, finger-bar, thumb and cuff
  blocks with a light grey edge pass over full transparency. The strip is
  4 windows of 384x432: the fist at 50%, 75% and 100% size, then a final
  full-size frame nudged slightly +X. Appended with
  `tools/sprites/append_sheet_rows.py` and
  `tools/sprites/specs/spell_upgrades_spirit_punch_row.json`: 6:1
  premultiplied box downsample into the same 64x72 cells, source alpha below
  32 dropped, each window centred on its frame, cells filled 0,1,2,3,3,3 to
  keep the #289 layout: `spirit_punch_start` (cols 0-2, emerge 50/75/100%,
  one-shot, 18 fps) then `spirit_punch` (cols 3, 4, 5, 4, steady full-size
  fist, loop, 12 fps). Sheet is now 6x17 cells.

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

# beast_boss.png - the Beast (second boss, #174)

Art from issue #174 ("BOSS SPRITE 2"): the 1448x1086 "Boss: Beast (Top-Down
2D)" concept sheet attached to the issue by Mitravasu (project human)
(https://github.com/user-attachments/assets/4ff27f56-7025-45e2-b605-2791a7899ad4).
It is a presentation board, so it is NOT shipped as-is; the engine sheet is
cut from it by `tools/sprites/extract_frames.py` with
`tools/sprites/specs/beast_boss.json` (background keyed out, 3:1
alpha-weighted downsample, hard alpha cut). Reproduce:
`python3 -I tools/sprites/extract_frames.py pack tools/sprites/specs/beast_boss.json <board.png> assets/sprites/beast_boss.png --tres resources/sprites/beast_boss_frames.tres`.

## Layout
- Cell: 48x48 px, feet on row 44, body ~29 px tall (the scene draws it
  2.5x). Sheet: 11 cols x 7 rows (528x336).
- Rows (frames drawn -> packed): 0 idle (6), 1 walk (7), 2 bite/lunge (8),
  3 AoE scream (8), 4 hurt (4), 5 stun (4), 6 death (11).
- Animations (resources/sprites/beast_boss_frames.tres): idle 6 (loop),
  walk 7 (loop), attack 4 (bite frames 3-6, contact bite), windup_bite 4 +
  bite 4 (bite row split at the snap), windup_aoe 3 + aoe 5 (scream row split
  where the mouth opens wide), hurt 4, stun 4 (loop), death 11 (last three
  frames held longer).
- Facing: every row faces LEFT, so the scene sets `EnemySprite.art_faces_left`
  and flip_h mirrors it toward the right.

## Board vs. extraction
- "Move (8, 4 dir)" draws 7 frames per row, and both "Right" and "Left" rows
  face left. The "Right" row (cleanly separated frames) is used as walk,
  resized 1.6x (nearest) because the move panel draws the beast ~0.6x the
  idle size. "Up" / "Down" are not extracted (no 4-direction consumer).
- "Death (10)" draws 11 frames; all 11 are used (resized 0.8x).
- Bite / hurt sparks and motion arcs are kept; those frames are anchored on a
  hand-measured body centre so the FX do not shift the body.
- AoE scream: the ground ring overlaps neighbouring frames, so the rows are
  cut at the feet line (the ring's front arc is dropped; the dome and back
  arcs remain) and the full ring is drawn in-engine by `BossTelegraph`. A few
  pixels of neighbouring rings remain at cell edges.
- Not extracted (no consumer): the "FX / Telegraphed Variants" panels
  (Charge, Dash, Invulnerable/Shield, Targeted/Warning), the "VFX Elements"
  overlays and the large portrait.

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

# HP bar (hp_bar_frame / hp_bar_track / hp_bar_fill)

## Source
Three-piece HP bar sheet for issue #244, supplied by the user as a 2000x667
WebP with real transparency (same layout as the image attached to the issue).
The source sheet is not stored in the repo. The shipped PNGs are extracted
with `tools/sprites/pack_hp_bar.gd`:
`godot --headless --path . --script res://tools/sprites/pack_hp_bar.gd -- <issue-244-sheet.webp> assets/sprites`.
Cut 3:1 with a hard alpha cut.

## Layout
- `hp_bar_frame.png` 100x60: 45 px caps, stretched rails. Drawn over the bar
  by the `HPFrame` nine-patch.
- `hp_bar_track.png` 151x60: 42 px caps, 67 px tile (two star periods).
- `hp_bar_fill.png` 157x60: 44 px ends (30 px transparent padding + 14 px
  tip), 69 px tile (two stripe periods).

## Changes from the sheet
- The sheet's middle top rail sits 7 px below the caps' rail; it is moved up
  to meet them.
- The fill is squeezed vertically from 105 to 72 sheet px to fit the frame
  opening, as the sheet's own previews do.
- The fill is stored as brightness only (max of r, g, b). `hud.gd` tints it
  green, amber or red, so the green is one hue and loses the sheet's slight
  yellow in the highlights.
- The sheet's full/mid/low previews and divider are not extracted.

# spell_icon_placeholder.png - no-icon spell placeholder (#257)

Supplied by Mitravasu on issue #257 (1254x1254 concept image). Cropped to the
frame, outer black keyed to transparent and area-downscaled to 64x64 with
ffmpeg. Shown by SpellIcon for any spell without art. Pixel-art import
(nearest).
