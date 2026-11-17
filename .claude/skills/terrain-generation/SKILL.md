---
name: terrain-generation
description: "Change or extend gangU's painted overworld terrain: the ground shader (grass, dirt, sand, sandstone, stone, cobble, cliff edge), the TerrainPieces atlas (trees, pines, bushes, pillars, boulders, tuft/flower/pebble clusters), clutter scatter, tree/pine placement and their collision, plus re-baking the atlas and verifying the look in game. Use when asked to make terrain look more natural, add a ground type, piece, tree or prop variant, tune colours, density or clumping, or fix how the overworld ground or decor looks."
---

# Painted overworld terrain (gangU)

The overworld is **painted, not tiled** (ARCHITECTURE D24). Three parts, all presentation only; collision and gameplay data never come from the art:

| Part | File | What it does |
|---|---|---|
| Ground | `game/world/terrain/ground_paint.gdshader` | One quad over the field. `OverworldGround._build_ground_paint()` bakes `_lattice_type()` (one `DualGrid.T` per 64 px point) into an R8 texture; the shader samples it at noise-warped positions with per-type bilinear weights, so borders curve instead of stepping. Each type is a palette picked by clumpy noise, or voronoi slabs (sandstone/stone/cobble), snapped to 2 px art pixels. Rims at type borders, rock face below the field's south edge. |
| Pieces | `game/world/terrain/terrain_pieces.gd` + `assets/sprites/terrain/terrain_pieces_{base,top}.png` | Atlas of painted props: 8 rows (`Kind`) x 8 variants, 48x64 art-px cells, foot at (24, 56), drawn at `ART_SCALE` 2. BASE = under characters (trunks, shadows, boulders, clutter), TOP = canopy z (crowns, bushes, pillars). |
| Placement | `game/world/overworld_ground.gd` | Decor `{kind, at, r}` (unchanged data) -> `tree_piece()` picks pine inside conifer-noise patches, size from `r`; `tree_foot()` drives both the art and the #771 trunk box (`TerrainPieces.trunk_rect`). `_build_scatter()` adds hashed, noise-clumped tufts/flowers/pebbles/bushes on grass. |

The hub still uses the dual-grid tiles (`dual_grid.gd`, `hub_floor.gd`); dungeons use `TerrainMap` + `TerrainArt`. Neither is in scope unless asked.

## Rules
- **The data decides, the art follows.** Change *where* ground types go in `_compute_lattice_type()`, never in the shader. The shader only decides how a type looks.
- **Art and collision share one anchor.** A tree's art and its trunk box both come from `tree_foot(d)`; keep it that way, or they drift apart. Canopy never collides; rocks, bushes and clutter never collide.
- **Deterministic.** Hash (`_hash01`) or seeded `FastNoiseLite`, never `randf()`, so every run and every harness sees the same world.
- **Pixel art stays crisp.** `OverworldGround` uses `TEXTURE_FILTER_NEAREST`; keep `ART_SCALE` an integer. Only flip unlit clutter: lit pieces assume light from the upper left.
- **Browser first.** The shader must compile on `gl_compatibility` (GLSL ES 3.0: no `uint` tricks, keep loops bounded). One quad replaces thousands of tile draws; keep per-pixel work small (the cliff branch is the most expensive).
- Update D24 when the rule changes; commit the `.gdshader.uid` / `.gd.uid` of new files.

## Recipes
**Tune the ground look:** edit the palettes / `paint()` / rim block in `ground_paint.gdshader`. `warp_amount` sets how far borders wander (70 px; keep the desert fight floor solid: `_compute_lattice_type` pads sandstone 96 px past the barrier for this reason). The grass palette is shared with the pieces' `GRASS` in the bake script; change both together.

**Add a ground type:** add it to `DualGrid.T` (append, values are baked into the texture), return it from `_compute_lattice_type()`, add a `const int` + branch in the shader's `paint()` and, if it should rim, in the margin block. Pieces/scatter skip non-grass unless you allow it in `_build_scatter()`.

**Add or change pieces:** edit `tools/sprites/draw_terrain_pieces.py` (painters + `paint()`), then re-bake:
`uv run --with pillow --with numpy python tools/sprites/draw_terrain_pieces.py`
A new kind = a new row: append to `KINDS` in the script **and** `TerrainPieces.Kind` in the same order (rows are the enum). Variants grow with the index so `sized_variant()` can map a radius. If you only refactor the script, prove the output is pixel-identical to the committed PNGs before committing.

**Tune scatter / forests:** `_build_scatter()` thresholds (density from `_clump_noise`, step `SCATTER_STEP`); conifer patches via `_pine_noise` and `PINE_LEVEL`. Keep clutter out of the village, desert arena and arrival clearing (existing checks).

## Verify (real game, not just tests)
1. `godot --headless --path . --import` after new/changed assets (it also writes `.import` files for unrelated images; do not commit those).
2. Screenshot from a scratch script (keep it out of the repo), non-headless. Create the `Camera2D` at zoom 1 **before** adding `res://game/world/overworld.tscn` (the desert arena sizes itself from the zoom on mount), wait a frame, then zoom out, wait ~20 frames, `await RenderingServer.frame_post_draw`, save `root.get_texture().get_image()`. Look at: the arrival (576, 200), the village (576, 1300), the desert edge (1700, 400) and the south cliff (900, 3050). A "get_node on null" error from `DesertStatueArena._ready` is expected when the overworld loads without Main.
3. For gameplay, load `res://game/core/main.tscn`, enter via the hub `GateOverworld` (`_on_body_entered(player)`), move the player and press `move_up` to check that collision still holds.
4. Run the full suite (`godot --headless --path . --script res://tools/run_tests.gd -- -j 8`); `test771_trunk_boxes` and `test346_overworld` own this area.

Pitfalls: `frame_post_draw` never fires headless, so a screenshot script run with `--headless` hangs (always `timeout` it). In zsh, `set -- $var` does not word-split; pass screenshot args explicitly. Never stash work while a background Godot run is using the tree.
