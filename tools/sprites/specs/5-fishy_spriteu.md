# Fishy - SpriteU integration spec

Source package: SpriteU `sprites/fishy.json` (SpriteU repo, commit 9f6f6dc,
"Fishy: directional casts (up/down/left) + hit animations (#4)").
Packed by `tools/sprites/pack_fishy_spriteu.py` into `assets/sprites/fishy.png`
(512x512 atlas of 64x64 cells) and `data/sprites/fishy_frames.tres`.

## What the SpriteU package provides
- New front-view Fishy design: `idle` (2-frame subtle breath loop, 850ms per
  frame - Colin chose "very subtle"), `hit`, `cast`, plus directional casts
  `cast_up`, `cast_down`, `cast_left`, and (2026-11-14 package) `walk`
  (4x125ms loop) and `death` (8-frame one-shot, 2290ms, held corpse).
- The packer derives `cast_hold` (wind-up loop: first 2 cast frames) and
  `reel`/`retract` (cast frames 3-1 wind-down) from the provided cast frames,
  per direction. These derived animations are flagged here so reviewers know
  they are not separately authored art.

## What the package does NOT provide
No `attack` art. Attack still uses the previous hand-drawn sheet's two cells
(bottom-aligned into 64x64, [1.0, 1.5] @12). It is reachable in game as the
close-range rod-club contact hit, so the old top-down style remains visible
there until SpriteU authors attack art; a follow-up package can replace the
fallback cells without code changes (the packer maps by animation name).
The 2026-11-14 package's cast/hit frames are byte-identical to the accepted
ones; only idle gained a frame.

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
