# Fishy - SpriteU integration spec

Source package: SpriteU `sprites/fishy.json` - idle/hit/cast + directional
casts from SpriteU repo commit 9f6f6dc ("Fishy: directional casts
(up/down/left) + hit animations (#4)"); `walk`/`death`/`attack` from the
2026-11-14 delivered packages (v3 final: slowed walk 6x125ms, new attack).
Packed by `tools/sprites/pack_fishy_spriteu.py` into `assets/sprites/fishy.png`
(512x576 atlas of 64x64 cells) and `data/sprites/fishy_frames.tres`.

## What the SpriteU package provides
- New front-view Fishy design: `idle` (2-frame subtle breath loop, 850ms per
  frame - Colin chose "very subtle"), `hit`, `cast`, plus directional casts
  `cast_up`, `cast_down`, `cast_left`, and (2026-11-14 packages) `walk`
  (6x125ms loop, slowed in v3), `death` (8-frame one-shot,
  110/90/100/150/170/150/120/1400ms, held corpse) and `attack` (4 frames,
  125/83/125/125ms, added in v3). Colin accepted the full v3 set 2026-11-14.
- The packer derives `cast_hold` (wind-up loop: first 2 cast frames) and
  `reel`/`retract` (cast frames 3-1 wind-down) from the provided cast frames,
  per direction. These derived animations are flagged here so reviewers know
  they are not separately authored art.

## Fallbacks
No shipped state falls back to the old sheet any more: the 2026-11-14 v3
package added `attack` and slowed `walk` to 6x125ms, and Colin accepted the
full set. Cast/hit frames are byte-identical to the accepted ones across all
package versions. If a future package drops a state, the packer falls back to
the previous sheet's cells without code changes (it maps by animation name).

## Scene/behavior metrics (new design)
- Sprite offset: (0, -16) (new art feet at row 62 of each cell; keeps the old
  shadow height).
- Idle rod tip: (15, -36). Cast tips R/L/U/D: (28,-40) / (-29,-37) /
  (10,-47) / (18,10) (`ROD_TIPS` in `enemy_behavior_fishy.gd`).
- `enemy_behavior_fishy.gd` picks a cast-direction suffix (_up/_down/_left or
  "" for right/base) from the existing aim vector; the art faces the direction
  the cast already targeted. No targeting or cast mechanics changed.
- The old-sheet `hook` cell is preserved verbatim at the top of the atlas so
  `HOOK_CELL_CENTER` (37, 26) and the fishing-line attachment are unchanged.
