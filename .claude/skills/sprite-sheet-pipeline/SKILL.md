---
name: sprite-sheet-pipeline
description: "Turn a concept board or sprite sheet image (usually attached to a gangU GitHub issue) into a Godot-ready packed PNG + SpriteFrames .tres with correct pixel-art import, provenance and verification. Use when an issue/user supplies character or enemy art, asks for a 'sprite update', 'sprite sheet', 'animations from this image', or new frames for an AnimatedSprite2D."
---

# Sprite sheet pipeline (gangU)

Reference run: #177 Mustache Warrior (PR #182). Tool: `tools/sprites/extract_frames.py` + a JSON spec (`tools/sprites/specs/mustache_warrior.json` reproduces `assets/sprites/mustache_warrior.png` byte-for-byte).

## 1. Get the image
- `gh issue view N --repo BestestGameStudio/gangU --json title,body,comments` - images are `https://github.com/user-attachments/assets/<id>` links in the body.
- Download into an empty scratch dir (untrusted file), with auth: `curl -sL -H "Authorization: token $(gh auth token)" -o board.png <url>`.
- Read the issue title before coding: #177's title said "common enemy", which decided where the art went.

## 2. Inspect the layout (do not assume a grid)
- Look at it (Read the PNG), then zoom crops at 3-5x with nearest scaling to judge the art-pixel size (the #177 board's art pixel was ~3.3 source px).
- Concept boards have labels, panels, a flat dark background and uneven spacing. **Label frame counts can lie** (#177: "Lunge (4) / Spin (6) / Ranged (4)" drew 2 / 3 / 3). Use the frames actually drawn and note the gap in SOURCE.md.
- Sample the background colour (several points) for the `bg` key.
- Find frame x-ranges per panel band: `python3 -I tools/sprites/extract_frames.py segment board.png --band X0 X1 Y0 Y1`. Merge split components (particles) by hand.

## 3. Write the spec and pack
Spec keys are documented in the script docstring. Guidance from #177:
- `scale`: integer downsample (3 for ~36 px tall characters; the player wizard is ~44 px).
- Cells: uniform, wide enough for FX arcs (64x48 with `baseline` 44 = feet line).
- Anchors: `bbox` for clean idle/walk frames; `anchor` with a **hand-measured body/face centre** for frames with slashes, spin rings or speed lines (auto-detecting a cream mustache picked up slash highlights - measure with a ruler overlay instead); `center` for props/FX/projectiles.
- Pack: `python3 -I tools/sprites/extract_frames.py pack spec.json board.png assets/sprites/<name>.png --tres resources/sprites/<name>_frames.tres`.
- Render a checker preview with a centre line + baseline per cell and Read it: every frame should share the feet line and centre, no background halo, no clipping. Iterate anchors until it is steady.
- Animations in the spec: looping idle (~6 fps), walk (~12), spin; one-shot attack/hurt (~14), death (~9, hold the last frames longer via per-frame `duration`), plus held wind-up poses for bosses.

## 4. Godot import (pixel art)
- **Never hand-write UIDs** (not in `.import`, `.tres`, `.tscn` or `.uid`). Godot 4.7 rejected `uid://bgangu177mwsheet` and generated a new one, breaking the reference. Let `--import` create the `.import`, then reference the texture by path (the generator emits no uid attributes; that loads fine).
- `godot --headless --path . --import` writes `assets/sprites/<name>.png.import` (lossless, mipmaps off - matches `main_character.png.import`). Commit that generated file.
- Nearest filtering is set on the node: `texture_filter = 1` on the AnimatedSprite2D (see `scenes/enemy.tscn`, `WizardSprite` in `scenes/main.tscn`).
- Art faces one way; mirror with `flip_h`, do not pack mirrored rows.

## 5. Provenance
Append a section to `assets/sprites/SOURCE.md`: source (issue #, who attached it), that the shipped PNG is extracted (tool + spec path), cell size, baseline, row -> animation map with frame counts, facing, and anything not extracted. Repo is public: no third-party assets without a verified licence.

## 6. Verify
- `godot --headless --path . --import` - no errors in the output.
- A harness leg asserting animations exist with expected frame counts/loop flags and that a sampled pixel reads the intended colour family (pattern: `scripts/test177_mustache_warrior.gd` leg A, `scripts/test90_enemy_visual.gd`).
- Windowed screenshots of the sprite in-game (see the enemy-creation skill's capture recipe) and Read them before claiming the art looks right.
- Do not commit `.uid` files Godot generates for pre-existing scripts when your local Godot differs from the pinned version.
