---
name: showcase-video
description: "Record a gangU gameplay video: a scripted hub -> gate -> boss fight -> exit run captured with Godot Movie Maker at 1920x1080 and encoded to a shareable MP4. Use when asked for a video, clip, trailer, demo, 'record gameplay', a GIF for a PR, or 'something to post'."
---

# Showcase video (gangU)

Driver: `tools/showcase/record_showcase.gd` (first used for #173). It walks the hero through `GATE_NAME` into `AREA_NAME`, autopilots the fight, kills the boss and walks out of the exit portal. Edit the constants at the top for another gate/area; bosses other than the Head get a generic kite-and-shoot fight. Recording-only cheats (boss HP floor per beat, player autoheal, lowered boss HP) are commented in the script - disclose them wherever the clip is posted.

## Workflow (from the repo root; `OUT` = your scratchpad, never the repo)
1. Temporary 1920x1080 window - create `override.cfg` at the project root (it is not tracked; delete it in step 6):
   ```
   [display]
   window/size/window_width_override=1920
   window/size/window_height_override=1080
   ```
   This upscales the normal 1152x648 framing (crisp art, readable HUD). Overriding `viewport_width/height` instead shows more of the map but with a tiny HUD and sprites.
2. Record (windowed, not `--headless`; it quits itself when the run ends):
   `godot --path . --write-movie $OUT/raw.avi --fixed-fps 60 --script res://tools/showcase/record_showcase.gd`
   Check the `[rec ...]` log lines: every beat printed, no `TIMEOUT waiting`, no `SCRIPT ERROR`.
3. Encode (target under ~20 MB; raise `-crf` if larger):
   `ffmpeg -y -i $OUT/raw.avi -c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p -movflags +faststart -an $OUT/showcase.mp4`
4. Verify it is not blank: pull 3-5 frames and Read them, e.g.
   `ffmpeg -i $OUT/showcase.mp4 -vf "fps=1/5" -frames:v 5 $OUT/frame_%02d.png`
5. Optional GIF for a PR: `scale=768:-1:flags=neighbor` + palettegen/paletteuse.
6. Clean up: `rm override.cfg`; `git status` must be clean (no videos, no `override.cfg`, no stray `.uid` files from a newer local Godot). Never commit videos; hand over the scratchpad path.
