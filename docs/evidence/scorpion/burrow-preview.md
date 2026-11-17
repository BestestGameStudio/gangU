# Scorpion emerge and bury, revision 2 (#853)

The reviewed second revision adds body shake, moving legs/tail and sand sliding off the back. Bury has separately generated downward debris. Art only, no behavior or spawn wiring in this PR.

## Production and reproduction

Original anatomy is deterministic Python pixel geometry in `tools/sprites/scorpion_pose_source.py`. `append_scorpion_burrow.py` generates SpriteU char-mode source; `pack_scorpion_spriteu.py` converts that source to the atlas and SpriteFrames. This is generator-based SpriteU art, not SpriteU-editor hand-drawing or image-model output.

Run with Pillow installed:

```
python tools/sprites/append_scorpion_burrow.py
python tools/sprites/pack_scorpion_spriteu.py
```

Regeneration of source, PNG and TRES is byte-identical. All original 216 source frames and the original 512x1728 RGBA atlas region are unchanged.

## Contract

- Eight directions: s, se, e, ne, n, nw, w, sw (atlas column order).
- `emerge_<direction>`, `bury_<direction>`: six 50ms frames, 0.30s total, non-looping.
- 64 animations, 312 frames. Atlas 512x2496, cells 64px.
- Original rows 0-26; emerge rows 27-32; bury rows 33-38.
- Final emerge and first bury equal the first idle frame in each direction.
- Last bury frame is a sand mound. Gameplay must hide the sprite after the transition.

## Evidence

`godot-burrow-playback.mp4` is eight seconds of actual Godot 4.5.1 SpriteFrames playback, all eight directions together. The scratch driver asserts six frames, non-looping and 0.30s per animation. `godot-burrow-frame.png` is a native emergence capture. All 96 new poses and representative encoded video frames were visually inspected for clipping, readable silhouettes and sand movement.

The clip is animation playback, not gameplay, state-machine, spawn, collision or browser evidence. No persistent recording driver is included.
