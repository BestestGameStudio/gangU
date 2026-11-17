# main_character.png - player wizard sprite sheet

Hand-composed original pixel art (SpriteU: sprites/player-wizard.json), no
copied game assets, no traced art, no stock files shipped.

2026-11-15: the #136 chunky wizard (with staff) was replaced by Mitra's new
interpretation of his own reference: blue pointed hat, long white beard,
purple robe, NO staff/wand - magic from bare hands. 32x48 cells, sheet
192x1536 (6 cols x 32 rows): one row per animation - idle, walk, dash,
cast-bolt, cast-twohand, cast-raise, hurt, death, each in
down/up/left/right. Reproduce: `python3 -I tools/sprites/build_main_character.py`
regenerates this PNG and the WizardSprite block in game/core/main.tscn from
the SpriteU JSON (source of truth; see characters/player-wizard.md there).

2026-11-15 v3: Sakurai key-pose pass - fewer exaggerated keys, held wind-up,
1-frame strike, long follow-through; extreme single-pose hurt; 3-key death with
a 1500 ms held fallen frame; palette-true rim light in the rig (see SpriteU
characters/player-wizard.md).

## Design
- Mitra's wizard: oversized blue pointed hat with gold band, long white beard,
  purple bell robe, sandals, NO staff/wand - magic comes from the bare hands.
  Original art, no copied or referenced asset files.
- Flat palette (22 tones), shading via lit/shade/deep tones per part plus a
  palette-true rim light on silhouette edges; no gradients, no drawn glow or
  spell orbs (the game draws FX).
- Frame: 32x48 px. Sheet: 6 cols x 32 rows (192x1536), one row per animation
  (idle, walk, dash, cast-bolt, cast-twohand, cast-raise, hurt, death x
  down/up/left/right). Anim timing: held key poses with fast transitions
  (Sakurai key-pose pass, 2026-11-15).

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
- #331 row 17 (water_ball): no external art. Drawn in code by
  `tools/sprites/draw_water_ball_row.gd` (run it with
  `godot --headless --path . -s tools/sprites/draw_water_ball_row.gd`, then
  `godot --headless --path . --import`): a blue water droplet pointing +X with
  a tapering tail, dark rim and white glint, ball centre 12 px right of the
  cell centre to match `Projectile.SPRITE_HEAD_OFFSET`. Cols 0-2 emerge at
  50/75/100% (`water_ball_start`, one-shot, 18 fps), cols 3-5 wobble
  (`water_ball`, frames 3, 4, 5, 4, loop, 12 fps). Every Water Ball tree spell
  flies this row. Sheet is now 6x18 cells.

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
- SpriteFrames: data/sprites/mustache_warrior_frames.tres.

# head_boss.png - the Head (boss of DungeonC, #173)

Art from issue #173 ("BOSS SPRITE"): the 1536x1024 "Boss: Head (Top-Down
2D)" concept sheet attached to the issue by Mitravasu (project human). It is
a presentation board (labels, panels, dark background, uneven spacing and
panels drawn at different character sizes), so it is NOT shipped as-is; the
engine sheet here is cut from it by `tools/sprites/extract_frames.py` with
`tools/sprites/specs/head_boss.json` (background keyed out, 3:1
alpha-weighted downsample, hard alpha cut for crisp pixels). Reproduce:
`python3 -I tools/sprites/extract_frames.py pack tools/sprites/specs/head_boss.json <board.png> assets/sprites/head_boss.png --tres data/sprites/head_boss_frames.tres`.

## Layout
- Cell: 48x48 px, chin on row 44, head ~24 px tall (the scene draws it 3x).
  Sheet: 11 cols x 7 rows (528x336).
- Rows (frames drawn on the board -> packed): 0 idle (6), 1 walk (7),
  2 projectile attack (8), 3 AoE pulse (8), 4 hurt (4), 5 stun (4),
  6 death (11).
- Animations (data/sprites/head_boss_frames.tres): idle 6 (loop),
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
`python3 -I tools/sprites/extract_frames.py pack tools/sprites/specs/beast_boss.json <board.png> assets/sprites/beast_boss.png --tres data/sprites/beast_boss_frames.tres`.

## Layout
- Cell: 48x48 px, feet on row 44, body ~29 px tall (the scene draws it
  2.5x). Sheet: 11 cols x 7 rows (528x336).
- Rows (frames drawn -> packed): 0 idle (6), 1 walk (7), 2 bite/lunge (8),
  3 AoE scream (8), 4 hurt (4), 5 stun (4), 6 death (11).
- Animations (data/sprites/beast_boss_frames.tres): idle 6 (loop),
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
`python3 -I tools/sprites/extract_frames.py pack tools/sprites/specs/shop_vendor.json <keyed-board.png> assets/sprites/shop_vendor.png --tres data/sprites/shop_vendor_frames.tres`.

## Layout
- Cell: 224x224 px, baseline row 220 (stall base). Sheet: 3 cols x 2 rows
  (672x448), one stall per cell; the scene draws it at 0.5 scale (~112 px).
- Frames are the board's six idle variants (potion sparkle / lighting
  positions). SpriteFrames (data/sprites/shop_vendor_frames.tres):
  idle, 6 frames, 4 fps loop.# spell_icons.png - player spell HUD icons (#207)

Art from issue #207 ("Spell ICON Sprites"): the 1448x1086 sheet attached to
the issue by Mitravasu (project human). The sheet is a regular 3x7 grid of
opaque framed tiles on a near-white page background; no keying was needed, so
the pack used a background colour absent from the sheet ([255, 0, 255] at
key_dist 54 matches nothing) and every pixel was kept. Cut by
`tools/sprites/extract_frames.py` with
`tools/sprites/specs/spell_icons.json` (bbox-anchored to the exact tile
windows, 4:1 downsample to the 47x48 cells). Reproduce:
`python3 -I tools/sprites/extract_frames.py pack tools/sprites/specs/spell_icons.json <issue-207-sheet.png> assets/sprites/spell_icons.png --tres data/sprites/spell_icons_frames.tres`.

## Layout (2026-11-15: raw glyphs + separate frame, per Mitra)
- The game now assembles every icon: `spell_icon_frame.png` (separate frame
  asset) underneath + one raw glyph from this sheet on top. Nothing is baked
  together any more; cooldown stays the code-drawn wipe and the upgrade
  indicator stays the code-drawn chevron.
- Cell: 47x48 px. Sheet: 7 cols x 39 rows (329x1872); only column 0 is
  used. All 39 rows are now generator-drawn primitives, ONE PER SPELL AND
  PER UPGRADE (see tools/sprites/gen_spell_icons.py GLYPHS for the row
  order; reproduced by `python3 -I tools/sprites/gen_spell_icons.py`).
- Revamp (2026-11-15 v4, Mitra): hammer family redrawn as a proper
  sledgehammer (blocky double-faced head, collar, long gripped handle;
  modifiers kept); rows 0-2 fireball/mana/bolt redrawn as primitives (the
  old glow-on-black extraction is gone); every tile gets a polish pass -
  rim light up-left, ambient shade down-right, hard outlines, no halo.
- SpriteFrames (data/sprites/spell_icons_frames.tres): `<prefix>_base` and
  `<prefix>_upgraded` per row, both pointing at the same glyph cell - the
  HUD draws its chevron overlay on base, the shop's baked `_upgraded` lookup
  resolves to the same art. Sweep anims are gone (code never played them).
- Old layout (pre-2026-11-15), for history: 7 cols x 3 rows; cols were
  0 base, 1 green-chevron upgrade, 2 alternate base, 3-6 cooldown sweep.

# spell_icon_frame.png - icon frame the game composes under every glyph

The dark metal frame ring + corner gems + near-black interior, extracted
from the committed mana tile (same #207 source as spell_icons.png) with the
interior filled. 47x48. Drawn by `SpellIcon` as the control texture, with
the spell's raw glyph (from spell_icons.png) on a TextureRect child above
it, so frame, glyph, chevron, cooldown wipe and rank border are all
independent layers.

# upgrade_chevron.png - upgrade-available overlay (#238)

Art from issue #238 ("FIx HUD"): the 2172x724 four-frame strip attached to the
issue by the project owner. The strip already has real transparency, so it was
cut with `tools/sprites/pack_alpha_strip.py` and
`tools/sprites/specs/upgrade_chevron.json` instead of the colour-keying
`extract_frames.py`: fixed 384x384 windows, 12:1 premultiplied box downsample,
source alpha below 32 dropped as generator noise (mostly around frame 3).
Reproduce:
`python3 -I tools/sprites/pack_alpha_strip.py pack tools/sprites/specs/upgrade_chevron.json <issue-238-strip.png> assets/sprites/upgrade_chevron.png --tres data/sprites/upgrade_chevron_frames.tres`.

## Layout
- Cell: 32x32 px. Sheet: 4 cols x 1 row (128x32). Frames drawn at their
  sheet position, with no re-anchoring.
- SpriteFrames (data/sprites/upgrade_chevron_frames.tres): `pulse`, 4
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

# terrain_block.png - destroyable terrain block (Stone Block spell) wall (#327)

Supplied by Mitravasu on issue #327 (2172x724 hand-laid sheet, transparent
background). Extracted with `tools/sprites/extract_frames.py` and spec
`tools/sprites/specs/terrain_block.json` into a 384x192 sheet of 64x64 cells
(scale 3, per-row `resize` 0.873 so a wall frame fills the game cell,
baseline 63). Faint pixels below alpha 100 were dropped before flattening,
so the semi-transparent edge blend never reaches the pack.

Row -> animation map (`data/sprites/terrain_block_frames.tres`):
- row 0 (6 frames) -> `create` (10 fps, one-shot): the wall builds up.
- row 1 (4 frames) -> frame 0 is `intact` (looping stand); all four are the
  `damage` crack progression (8 fps, one-shot) kept for a future
  partial-damage mechanic - nothing consumes it yet (#169 destroy is one
  hit).
- row 2 (6 frames) -> `destroy` (10 fps, one-shot): cracks, collapse,
  rubble, dust.

Art faces no direction; nothing mirrored. The board's panel margins/labels
were not extracted (there were none - bare frames). The wall frames slightly
overhang their cell sideways so adjacent blocks read as one connected wall.

# slime.png - original code-drawn Slime sheet (#392)

Original art drawn by `tools/sprites/draw_slime.gd` (procedural pixel drawing,
no external assets, no traced or generated images). `data/sprites/slime_frames.tres`
is built from it by `tools/sprites/build_slime_frames.gd`. Placeholder-quality
style pass; replaceable if Daniel supplies concept art (sprite-sheet-pipeline).

- Cell 32x32, feet baseline y=28, art faces RIGHT (EnemySprite flips with flip_h).
- Rows: idle x4 (5 fps loop), walk x6 (10 fps loop), hurt x2, attack x3, death x5 (one-shots).

# terrain_tiles.png / terrain_objects.png - terrain art pass

- Source: two AI-generated sheets supplied by the user (Mitravasu) in a
  Claude Code session, 2026-11-09, committed unchanged under
  `tools/sprites/sources/` (`.gdignore`d, never imported):
  `terrain_tiles_sheet.webp` (1066x1476, RGBA) and
  `terrain_objects_sheet.webp` (1447x1087, RGBA). Not pixel exact: blurred
  pixel art, cells split by thin transparent gaps, floor cells ~83x85 px,
  autotile cells ~81x74 px, object cells ~181 px with a faint near-white
  fringe (alpha 1-95) around every object.
- Packed by `tools/sprites/pack_terrain_sheets.py` (Pillow + numpy). Grid
  lines are predicted from the outer bounds, snapped to the local alpha
  minimum, each cell trimmed to fully opaque rows/cols plus a 2 px (floors)
  / 4 px (autotiles) inset, then box-resampled.
- `terrain_tiles.png` (16 x 25 cells of 64 px, opaque):
  - rows 0-10 floors, cols 0-3 variants: ground, grass spring / summer /
    autumn / winter, meadow, scree, snow, ice, mud, water (its 4 cols are
    the animation loop). Each cell's low-frequency lighting (wide blur) was
    replaced by its row's mean colour so variants mix without a visible
    grid; the small details are the sheet's.
  - rows 11-24 autotile sets, 2 rows each (A, B): obstacle slate / brown /
    purple / green, mountain, cliff, chasm. Column = exposed-side mask
    (N=1 E=2 S=4 W=8). The sheet's 13 pieces per set turned out to be:
    full fill, top / bottom / left / right rims, four corner rims, and four
    alternate corner rims (no inner corners were drawn). Every mask is
    composed: interior = the fill (lighting flattened; row B mirrored) or,
    for chasm, the flat pit colour; rims are keyed off the set's
    background colour and alpha-blended on (corner piece where two
    adjacent sides are exposed, side piece otherwise). Cliff remap: the
    sheet's "top" pieces show grass over a dirt face, so they are used for
    an exposed SOUTH side (a cliff face faces the viewer) and the flipped
    "bottom" grass lips for the north side.
- `terrain_objects.png` (8 x 6 cells of 80 px, transparent, drawn centred
  on a 64 px game cell so canopies overhang slightly): rows tree spring /
  summer / autumn / winter, pine (4 variants), stone block; cols 0-3 idle
  variants, cols 4-7 the 4-frame destroy sequence (tree ends on a stump).
  Alpha below 96 dropped before a premultiplied 2:1 box downsample, then
  hard alpha (>= 110 opaque) so no white halo remains.
- The stone-block row is packed but NOT used: `terrain_block.png` (#327)
  keeps drawing BLOCK because it has the build-up `create` animation the new
  sheet lacks.
- Licence: user-supplied project art (same terms as the other supplied
  sheets).

# bird.png - original bird sprite sheet (#478)

Original code-drawn pixel art for gangU (#478). No copied game assets, no
traced art, no stock files shipped. Daniel: "Make the sprites yourself."

## Design
- Slate blue-black dive-bomber bird (crow/kite silhouette): orange beak and
  talons, pale belly, lighter wing highlight, yellow eye. Flat palette, no
  gradients/glow, fitted to the existing enemy palette idiom.
- Frame: 32x32 px, feet on y=28, art faces right (EnemySprite flip idiom).
  Sheet: uniform 6x5 grid (192x160 px), rows = [idle x4 (perched), walk x6
  (flight flap - the locomotion row), hurt x2, attack x3 (dive tuck, stoop,
  landing flare), death x5].

## Provenance
- Author: instinct-dc (Daniel's Instinct), 2026-11-09, pixel-by-pixel via
  tools/sprites/draw_bird.gd (code-drawn, same generator idiom as
  tools/sprites/draw_slime.gd / draw_wolf.gd).
- License for this original asset: CC0 (matches project asset licensing).

# wolf.png - Wolf sheet (#476, art by Mitra's artist)

Hand-drawn 8-direction wolf sheet supplied by Mitra's user in PR #476
(https://github.com/BestestGameStudio/gangU/pull/476#issuecomment-6758758613),
replacing the earlier code-drawn placeholder. The source board is presentation
art (direction headers, row labels, grid lines); the game sheet is packed from
it by `tools/sprites/pack_alpha_strip.py` with spec
`tools/sprites/specs/wolf.json` (clip windows drop the grid lines/labels;
3x premultiplied box downsample), which also writes
`data/sprites/wolf_frames.tres`.

- Cell 56x22 (3x downsample), feet baseline at the cell bottom.
- 8 directions per row: S, SE, E, NE, N, NW, W, SW; EnemySprite plays the
  `<anim>_<dir>` variant for the body's travel direction (no flip_h).
- The board's labels claim Idle 4 / Run 6 / Bite 6 frames, but the drawn rows
  actually count 4 / 5 / 5 - only the drawn frames are packed:
  idle x4 (5 fps loop), walk x5 (12 fps loop), attack (bite) x5 (10 fps
  one-shot). `telegraph` holds the bite crouch (frame 0), `pounce` plays the
  lunge (bite frames 1-4). `hurt` and `death` reuse the idle frame (the sheet
  has no hurt/death art; the hit flash and corpse fade carry those beats).
- Base `idle`/`walk`/`attack`/`hurt`/`death`/`telegraph`/`pounce` animations
  (E-facing) are kept as fallbacks alongside the directional variants.

# wolf_cave.png - original code-drawn wolf den decor (#474)

Original art drawn by `tools/sprites/draw_wolf_cave.gd` (procedural pixel
drawing, no external assets): one 64x64 sprite, a rocky mound with a dark
den opening. Caves are decor only (Daniel: "Decor" - not enterable), drawn
under characters (z -10, above the ground layer).

# fishy.png - Fishy enemy (#464)

Source: the sprite sheet attached to issue #464 by real-human-123 (1536x1024
RGBA, real transparency; the green glow and grey smoke are partial alpha).
Extracted with `tools/sprites/pack_alpha_strip.py` + `tools/sprites/specs/fishy.json`
(alpha_floor 215 drops the glow/smoke and the thin partial-alpha fishing
lines), downsampled 3x into 64x52 cells, 8 columns, feet on cell row ~51.
Origins were measured per frame (body centre = green-hair centroid, feet =
lowest boot pixel). `data/sprites/fishy_frames.tres` is generated by the
same command.

- sheet frames 0-2 (board row 6, cols 5-7, front stand) -> `idle` (5 fps loop, 0-1-2-1)
- frames 3-5 (board rows 1-3, col 1, front view) -> `walk` (8 fps loop, 3-4-5-4)
- frames 6-10 (board row 4, cols 1-5) -> `cast` wind-up (12 fps, one-shot, held)
- frame 11 (board row 4, col 6; line cut at the rod tip) -> `cast_hold`
- frames 12-15 (board row 5, cols 4-7) -> `reel` (10 fps loop)
- frames 16-19 (board row 6, cols 1-4) -> `retract` (one-shot); 18-19 also `attack`
- frame 20 (the hook from board row 4, col 6) -> `hook`, drawn at the line tip
  by `game/enemies/fishing_line.gd` (cell centre offset (37, 26))

Not drawn on the board, so reused frames: `hurt` = walk frames 5, 4; `death` =
walk frames 4, 5 (held, then the corpse fades). Not extracted: the other
turnaround views (board rows 1-3, cols 2-6: side and back), board row 5
cols 1-3 (side cast / hand close-ups) and the drawn fishing lines (the line is
drawn in-engine so it can reach the real target). The cast/reel art faces
RIGHT (EnemySprite flips with flip_h); idle/walk are front views.

## Village props (#484 / PR #544)

Original in-house pixel art, reproducible with `python3 tools/sprites/draw_village.py`.
No external source image or third-party assets. `village_props.png` is a static
512x128 RGBA sheet, four 128x128 cells in one row: three collapsed-house
variants (columns 0-2) and a dry well (column 3). House cells include stone
foundations, broken doors, fallen timber, shingles, rubble, weeds and shadows.
Well includes chipped stonework, empty interior, broken beam/rope and shadow.
Static props have no animation or facing. No SpriteFrames resource is needed;
AbandonedVillage draws atlas regions by path with nearest filtering. The road
reuses the existing TerrainArt floor atlas; surrounding trees already use its
object atlas. The old shape-drawn clearing disk is removed, exposing the
existing grass floor. No building/well/ruin primitive drawing remains.

## Stationary circle statues (#658)

Source: six transparent animated GIFs supplied by Colin for this replacement.
Nearest-neighbor reduction from 1024x1024 to 64x64, no crop or per-frame
recentering, preserving the source body/feet anchors and alpha. Packed in
`stationary_statues.png`, 19 columns by 6 rows (empty cells unused);
`stationary_statues_frames.tres` stores the source per-frame durations.
The static first pose supplies idle; the throw directions are selected from
the inward vector, not mirrored or rotated. Hit/death remain front-facing
as supplied. The old `sandstatues.png` remains for the moving phase-two boss.

- `throw_down`: 13 frames; milliseconds [400, 100, 160, 120, 280, 50, 60, 70, 100, 180, 140, 180, 300]; source SHA256 `2b98619d188c41f42b4a5eb3c4c68c59f27caecc1abceafd7ae11d28731bc279`.
- `throw_left`: 13 frames; milliseconds [400, 100, 160, 120, 280, 50, 60, 70, 100, 180, 140, 180, 300]; source SHA256 `c1318fc793ac0d9b8200007cfb9c21eabe7a0215f0f4cac3111aa35f8ab6c0cb`.
- `throw_right`: 13 frames; milliseconds [400, 100, 160, 120, 280, 50, 60, 70, 100, 180, 140, 180, 300]; source SHA256 `51544b17f84b379b5ced808e30f74104d5407fd1a756262181cd88e0fc23e0bf`.
- `throw_up`: 13 frames; milliseconds [400, 100, 160, 120, 280, 50, 60, 70, 100, 180, 140, 180, 300]; source SHA256 `232cf131b08c437f8ff5fa11cfab320c29f4f7f58abc1b6a09150f7e2f7e50ea`.
- `hurt`: 6 frames; milliseconds [60, 90, 150, 120, 110, 200]; source SHA256 `67dcc5f5f23e2caaa021628fca608e1dccc4575473ee4b231a257ed3f060c964`.
- `death`: 19 frames; milliseconds [70, 100, 110, 120, 130, 220, 60, 60, 60, 70, 70, 70, 80, 80, 90, 90, 100, 110, 1300]; source SHA256 `569bc9d22e71dfff5dee9ca179ec0e1188512239ae8df66e6d46dc21e2c5266f`.

Throws are uniformly sped up at runtime to fit 90% of the existing volley
interval (1.35s at the default 1.5s cadence). Frame 7, the first pose without
the released spear, aligns with the actual projectile release. Hit and death
use their original timing; hurt reactions queue behind an active throw so
they cannot obscure its release. Death finishes before the original rubble
absorption begins. Rebuilding cancels death and restores the ring anchor.

## fishy.png (SpriteU refresh, 2026-11)
Regenerated from the SpriteU package `sprites/fishy.json` (SpriteU repo,
commit 9f6f6dc) by `tools/sprites/pack_fishy_spriteu.py`; see
`tools/sprites/specs/fishy_spriteu.md`. Contains the new front-view idle (subtle
breath loop)/walk/attack/death/hit/cast (incl. up/down/left) design (walk +
death added in the 2026-11-14 package; slowed walk + attack in the same-day
v3 package, full set accepted by Colin 2026-11-14), with only the original
hook cell carried over from the previous hand-drawn sheet.

## Roman Sand general (Phase 2, #664)

- Source: custom Roman sandstone general v2 pixel art supplied by Mitra for this replacement. Native transparent 64x64 frames, purple eyes/sash/crest/shield sigil, no plinth. The reference photo is not included in the game assets.
- `roman_general_v3.png` losslessly repacks the supplied atlas: only redundant mirrored-left rows were removed. No resizing, repainting, interpolation or palette conversion. `roman_general_manifest.json` records every row, frame count, tag and source duration in milliseconds. `roman_general_frames.tres` uses those durations at speed 1.0.
- Row order: idle, walk, run, projectile, triple-slash, charged-slash, ground-slam, shield-bash, spear-throw. Shield-plant is appended after spear-throw. Each move has front, back, right rows, in that order (30 rows total, 1408x1920). Left mirrors right in the renderer. Native cell center is (32,32); body feet are near y=55 and aligned to the existing y=24 ground line by the node offset. Effects may intentionally extend below the feet.
- The mobile Phase 2 general alone uses this art. The 12 Phase 1 statues retain `stationary_statues.png` and its throw/hurt/crumble animations.
- `desert_statue.gd` samples the attack animations against the existing arena clock, aligning impact poses with gameplay cues and fitting recovery inside the existing attack duration. Original GIF timing is preserved in the resource, but retimed in combat. Projectile art has three casts while the existing gameplay volley still fires five projectiles. The seventh shield-plant move now has a custom 11-frame placement animation (400 ms wind-up, 80 ms release, 720 ms recovery in source), retimed to its existing 0.75 s wind-up + 0.28 s release cue and 1.0 s action window. Walk/run are available for locomotion; the existing encounter moves during attack dashes rather than adding a new chase state.
- Left lighting is mirrored. Back detail is cape-dominant. Effects are baked into the art; existing gameplay projectiles and ground warnings remain independently rendered. Spear throw ends empty-handed before the next animation restores it. No new death art was supplied: defeat holds a dimmed idle pose rather than reusing Phase 1 rubble.
- Imported with Godot 4.5.1, lossless, mipmaps off, nearest node filtering. Repack method: copy each non-left 64-pixel row from the supplied sheet in manifest order, generate an AtlasTexture for each occupied cell, and set frame duration to source milliseconds / 1000.

### Larger general and planted shield follow-up
- General renderer scale is 2.0x (was 1.22x), about 64% larger. Native source remains 64x64. Offset -22 keeps native foot y=55 at the same world ground y=24. Collision radius and gameplay reach are unchanged.
- `roman_planted_shield.png` / `_frames.tres` use a custom sandstone wall-shaped shield with rim, panel seams, rivets and purple diamond sigil. Four 200 ms frames make the sigil pulse. Whole silhouette stays fixed. The unchanged parent wall rotation points it toward the target; the same sprite rotates with all directions.
- The planted-shield renderer replaces only the old Polygon2D/Line2D children in `desert_statue_arena.gd`; the existing 88x24 collision, position, orientation, five-second duration, healing and removal are unchanged. Sprite opaque bounds at 2x are 90x38, close to the previous decorative shield face; transparent cell margins do not change collision.
- New placement art uses the original part rig, key poses, smoothstep in-betweens and same 10-color palette. Four facings, 11 frames each. SpriteU checker: no errors/warnings; connected neck, one body component, no edge clipping. All 36 prior animations are unchanged against baseline. SpriteU viewer played at 1x/0.5x with onion/silhouette inspection; 1x PNG exports match packed engine pixels.


## Sand general attack readability (#666)
The existing original Roman-general part rig was extended under Mitra's requested fan/jump-slam rework. Native SpriteU character data and keyframe generators remain in the art source bundle; the packed export updates only the projectile and ground-slam rows in `roman_general_v4.png`, `roman_general_frames.tres` and `roman_general_manifest.json`. The old v3 atlas is retained for source continuity; the active frames resource points at v4. Other rows are unchanged.

Projectile: 16 frames per facing, source windup 740ms, release 80ms, recovery 960ms; no baked flying spear effects. Ground slam: 17 frames per facing, source crouch 380ms, takeoff 140ms, airborne 200ms, landing 80ms, recovery 800ms. The game maps key poses to its shared attack clock. Feet remain at the existing ground baseline except intentional jump height, applied to the whole sprite node. Left mirrors right.

`roman_general_spear.png` is the same rig's sandstone/purple spear template, rotated right into a 39x9 transparent PNG, drawn at 1.6x by the shared Projectile. No third-party art. Generated frames pass the existing SpriteU checker: continuous neck, one connected component, no edge clipping. No new test or verification drivers are committed.

## Hub stone bricks, thin connected walls and quiet shop (#708)
`terrain/dualgrid_brickwall_on_stonebrick.png` and `terrain/dualgrid_variants_stonebrick_hub.png` were generated for gangU by Instinct, then edited to darken and mute the original brick design and align the variant borders. No third-party assets. The 256x256 wall sheet uses 16 row-major 64px dual-grid masks (TL=1, TR=2, BR=4, BL=8), with backgrounds from floor/cap variant 0. The 512x64 floor strip holds eight variants with identical outer rings. Runtime uses deterministic hash placement and trims excess outer cap to a 22px band around the square marching-corner floor boundary; no full cap tiles remain. Nearest texture filtering, lossless import, no mipmaps.

`shop_vendor.png` is a darker, muted recolor of the existing shop sheet for this hub. Its 672x448 layout, six 224x224 frames, animation, scene scale and anchor are unchanged.

## Desert sanctum lights

Original pixel art drawn for this project, 2026-11-16. No pixels extracted
from reference images. `desert_brazier.png`: four 64x80 frames, 7 fps looping
flame over a stationary carved stone bowl and plinth. `desert_lantern_pillar.png`:
one 64x128 carved sandstone pillar with a bronze lantern. Both use 2px art
pixels and nearest filtering. Runtime anchors sit at the base of each prop;
lighting is shared radial gradients, not baked into the PNGs.

Visual references only (not licensed or shipped as game assets):
- Tanya Ivanova, Lost Oasis Courtyard, day/night: sand drifts, stone center,
  low fire bowls and contained amber light against cool surroundings.
  https://tataiv.artstation.com/projects/Nql4aJ
- Bhaven Jani, Petra at night: separate warm pools on sandy sandstone.
  https://www.nationalgeographic.com/photo-of-the-day/photo/candles-petra-jordan
- Max_M42, Desert Ruins: broken sand-to-paving edge.
  https://max-m42.itch.io/desert-ruins-16x16-pixel-art-asset
- princess-phoenix, Desert interior tileset: warm golden stone and edge lights.
  https://www.deviantart.com/princess-phoenix/art/Desert-interior-tileset-656502636

## Suncrest player healthbar (#753)

Original Suncrest gold/red-enamel frame authored in SpriteU format for this project;
source: `tools/sprites/specs/suncrest-border.spriteu.json`. Validated/exported with
SpriteU at 7fd4617ebb9a084450fef7e428bee61357b26227 (read-only source).
The exported 64x30 source is assembled with fixed 24px caps to 180x30, then scaled
2x nearest to `hp_bar_frame.png` (360x60). HUD NinePatchRect cap margins are48px.
`hp_bar_track.png` retains the existing151x60 alpha/star pattern, recolored from
purple to warm charcoal/bronze. Track cap42px and original diagonal-striped
`hp_bar_fill.png` are unchanged. No third-party art added.

## Gilded thread spirit bar (#757)

Original SpriteU-authored Gilded thread frame, track, cyan fill and mint ready
textures exported using unchanged SpriteU7fd4617. Final PNGs284x16,
trimmed/reassembled fixed12pxcaps and260pxmiddle, nearest-neighbor.
HUD position relativeHP(38,46), fixedheight16, frameverticalmargins4.
No spirit text; spirit gain/heal/channel logic unchanged. No third-party art.

## Overworld water, south beach and shore life (#811)

Original SpriteU-authored art (SpriteU repo, branch `water-terrain-sprites`
and its `tools/gen_wildlife.py`, `gen_water_tile.py`, `gen_driftwood.py`,
`gen_palm_tree.py`); no third-party art. Reference pixel art (itch.io seagull,
fish and beach packs, OpenGameArt shoreline tiles) was viewed for style only;
nothing is copied or shipped.
- `dualgrid_water_on_{sand,cliff,grass,dirt}.png`: 256x1280, five 256x256
  dual-grid frames stacked vertically (loop 220/160/220/160/140 ms), built by
  `tools/sprites/gen_water_sheets.py` + `gen_water_tex.py` from the shipped
  sheets' geometry. `dualgrid_sand_on_dirt.png`: new 256x256 sheet.
- `palm_1/2.png`, `driftwood_1/2.png`: beach props, 1 frame each.
- `seagull.png` (4 frames flap), `fish.png` (4 frames swim),
  `fish_splash.png` (5 frames), `seashell.png` (3 variants),
  `footprint.png` (left, right): 32x32 cells in horizontal strips, facing
  right, nearest filtering.
Code only: shore tiles' flat sand/grass/dirt base colours are keyed transparent
at load (`overworld_water.gd`) so the shader ground shows through; depth,
specks, waves and the tide are drawn procedurally. Not extracted from a board.

## Cliff shore flattened and front-only rock (#820)

- `terrain/dualgrid_water_on_cliff.png`: regenerated with `tools/sprites/gen_water_sheets.py`. The rock side of every cliff shore tile is now one flat colour (88,82,88) instead of cobble, to match the flat rock fill the engine draws in world space (`game/world/overworld_cliff_rock.gd`). Water side unchanged. Source of the rock tones: the cliff set it was derived from (`dualgrid_cliff_on_grass`).
- `terrain/dualgrid_cliff_on_sand.png`: rock side flattened to the same (88,82,88) with `tools/sprites/gen_cliff_flat.py` (sand pixels untouched), so the rock/sand seam beside the beach has no cobble or dark wedge.

## Pine shadow strays and tuft redraw (#838)

- `terrain/terrain_pieces_base.png`: regenerated with `tools/sprites/draw_terrain_pieces.py`. Pine row (kind 1) variants 3-7 had 91 stray semi-transparent shadow pixels spilled from the tree shadow into the cell above, drawn as dark bars. The shadow is now clipped to its own cell. Tuft row (kind 5) redrawn as upright 1 px blades (no dark base row). All other rows are pixel-identical. Original art, no external reference pixels used.

## Stone Hammer sprites (#839)

- `stone_hammer.png`: 64x32 atlas, authored in SpriteU (`tools/gen_stone_hammer.py`, `sprites/stone-hammer.json`, `characters/stone-hammer.md`) and exported with `python3 -I tools/gen_stone_hammer.py --export DIR`. Hammer head (15x9, drawn at 2x = the old 30x18 rectangle), 2x4 handle strip stretched along the swing, 32x32 radial crack star for the impact. Original pixel art; CC0 references (OpenGameArt CC0 Hammer Icons, pixor.art war hammer) were looked at only, no pixels copied. SpriteU PR: https://github.com/BestestGameStudio/SpriteU/pull/13
