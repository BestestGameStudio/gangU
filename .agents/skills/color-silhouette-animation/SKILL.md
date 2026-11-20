---
name: color-silhouette-animation
description: Animate a pixel-art sprite pose to pose using primary-color silhouettes that identify body parts. Use for new or revised character animations that call for color blocking, expressive motion, or a SpriteU silhouette pass.
---

# Color silhouette animation

## Lock the reference and block the keys

1. Identify the action, the direction it faces, and the features that make the sprite recognizable. When matching an existing sprite, use its source pixels or sample its native grid before drawing. Keep the head shape, limb lengths, palette, and markings unless the user grants room to exaggerate. For a revision, carry forward the approved timing and poses outside the requested change.
2. Draw the key poses as flat shapes at the export resolution. Assign each visible moving part a distinct, stable swatch. Use red, yellow, and blue families with shades that remain distinguishable where parts overlap. For a raptor, use red for the skull and dark red for the jaw, two yellows for the neck and torso, and distinct blues for the tail, forearms, and near and far legs. Choose a different grouping when it makes another character easier to read.
3. Render the key poses side by side and inspect them before creating in-betweens or adding shading. Check the outer contour as one shape and use the colored parts to inspect overlaps, joint connections, and near and far limb order. Follow a visible landmark through the keys, such as the eye, planted toe, or tail tip. Revise any pose where the action, contact point, or direction is unclear.

## Set timing, then shade

4. Time the keys for the action. Use a longer anticipation or hold where the pose needs to read, and short exposures with wider spacing for fast motion. Set frame count and frame duration together against the intended total time. Draw transitions along arcs and redraw contours where compression, extension, or a turn changes the form. A fast action can use a single-frame smear between readable poses. Keep a free appendage moving on a slight delay where it adds follow-through.
5. Shade the approved poses with the source palette or the project's lighting rules. Keep the color-block pass available for comparison. If both passes come from the same geometry, compare their occupancy masks to catch a shape change introduced during shading. Preserve deliberate silhouette edits in both passes.

## Verify the deliverables

6. Inspect the motion at playback speed and step around contact, direction changes, and the loop seam. Check for unintended detached parts, clipping, sliding feet, and jitter. Compare actual exported frame durations to the source and inspect transparency and the frame order. Effects and separate props can add intentional components.
7. Deliver an animation preview and editable source. Include the color-blocked keys for review and a transparent sprite sheet when useful for import.

### With SpriteU

Locate the available checkout and read its `FORMAT.md` and the usages in `tools/check_sprite.py`, `tools/sheet.py`, and `tools/export_gif.py`. Use the current asset's grid and animation format. Keep scratch files outside the tool checkout unless the user asked to edit SpriteU itself. For example, from the SpriteU root:

```bash
python3 tools/sheet.py "$blocked_keys" "$contact_sheet" --anim "$clip" --cols 6
python3 tools/check_sprite.py "$sprite" --anim "$clip"
python3 tools/export_gif.py "$sprite" "$preview" --anim "$clip" --scale 4
```

If the feet should stay planted for the whole clip, run `check_sprite.py` on the character-only clip with the appropriate `--pinned` row. Use the viewer's frame stepping and onion skin when available. If the local viewer is unavailable, inspect the contact sheet and verify the decoded export. Report the checks that ran. GIF frame durations are rounded to 10 ms by the exporter. Use durations divisible by 10 ms when the GIF must match the SpriteU timing exactly.
